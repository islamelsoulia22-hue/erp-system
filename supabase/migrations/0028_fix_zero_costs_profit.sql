-- ============================================================
-- ERP Migration 0028: fix zero costs for profit (بيع - شراء).
-- المشكلة: أصناف average_cost=0 ولقطات unit_cost=0 فالربح طالع غلط
-- (البيع كله محسوب ربح). السبب coalesce بياخد 0 مش purchase_price.
-- الإصلاح: fallback لـ purchase_price عند الصفر + دالة الاعتماد.
-- ============================================================

-- 1) المتوسط الصفري = سعر الشراء.
update public.products
  set average_cost = purchase_price
  where average_cost = 0;

-- 2) لقطات التكلفة الصفرية للفواتير المعتمدة = سعر الشراء/المتوسط.
update public.sales_invoice_items sii
  set unit_cost = coalesce(nullif(p.average_cost, 0), p.purchase_price, 0)
  from public.products p, public.sales_invoices si
  where p.id = sii.product_id
    and si.id = sii.sales_invoice_id
    and sii.product_id is not null
    and sii.unit_cost = 0
    and si.status = 'APPROVED';

-- 3) إصلاح دالة الاعتماد: تجاهل الصفر في المتوسط.
create or replace function public.approve_sales_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record; it record; av numeric;
  v_total numeric; v_paid numeric; v_method text;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('sales.approve') then
    raise exception 'NO_PERMISSION: sales.approve required';
  end if;
  select * into v from public.sales_invoices where id = p_invoice for update;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid and not public.is_company_manager() then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذه الفاتورة';
  end if;
  perform public.recalc_sales_invoice(p_invoice);
  -- لقطة التكلفة: المتوسط (لو > 0) وإلا سعر الشراء.
  update public.sales_invoice_items sii
    set unit_cost = coalesce(nullif(p.average_cost, 0), p.purchase_price, 0)
    from public.products p
    where p.id = sii.product_id
      and sii.sales_invoice_id = p_invoice
      and sii.product_id is not null;
  for it in select sii.*, p.track_inventory
    from public.sales_invoice_items sii
    left join public.products p on p.id = sii.product_id
    where sii.sales_invoice_id = p_invoice loop
    if it.product_id is not null and coalesce(it.track_inventory, true) then
      select quantity - reserved_quantity into av
        from public.warehouse_stock
        where warehouse_id = v.warehouse_id and product_id = it.product_id
        for update;
      if not found or av < it.quantity then
        raise exception 'INSUFFICIENT_STOCK: %', it.item_name;
      end if;
      update public.warehouse_stock
        set reserved_quantity = reserved_quantity + it.quantity
        where warehouse_id = v.warehouse_id and product_id = it.product_id;
    end if;
  end loop;
  update public.sales_invoices
    set status = 'APPROVED', approved_by = v_uid, approved_at = now(),
        rejected_by = null, rejected_at = null, rejection_reason = null
    where id = p_invoice;
  select pm.code into v_method from public.payment_methods pm
    where pm.id = v.payment_method_id;
  if v_method is not null and v_method != 'CREDIT' then
    select grand_total into v_total from public.sales_invoices
      where id = p_invoice;
    select coalesce(sum(amount), 0) into v_paid from public.payments
      where sales_invoice_id = p_invoice and status = 'COMPLETED';
    if v_total - v_paid > 0 then
      insert into public.payments
        (customer_id, sales_invoice_id, payment_method_id,
         amount, notes, created_by)
        values (v.customer_id, p_invoice, v.payment_method_id,
          v_total - v_paid, 'تحصيل تلقائي - ' || v_method, v_uid);
      select coalesce(sum(amount), 0) into v_paid from public.payments
        where sales_invoice_id = p_invoice and status = 'COMPLETED';
    end if;
    update public.sales_invoices set payment_status = case
      when v_paid <= 0 then 'UNPAID' when v_paid < v_total then 'PARTIAL'
      else 'PAID' end
      where id = p_invoice;
  else
    select grand_total into v_total from public.sales_invoices
      where id = p_invoice;
    select coalesce(sum(amount), 0) into v_paid from public.payments
      where sales_invoice_id = p_invoice and status = 'COMPLETED';
    update public.sales_invoices set payment_status = case
      when v_paid <= 0 then 'UNPAID' when v_paid < v_total then 'PARTIAL'
      else 'PAID' end
      where id = p_invoice;
  end if;
  perform public.write_audit_log('APPROVE', 'SALES_INVOICE',
    p_invoice::text, jsonb_build_object('from', 'PENDING_APPROVAL'),
    jsonb_build_object('to', 'APPROVED'));
end $$;

-- 4) إصلاح المتوسط المرجح: تجاهل الصفر كمصدر.
create or replace function public.apply_purchase_cost(
  p_product uuid, p_qty numeric, p_cost numeric)
returns void language plpgsql security definer set search_path = public as $$
declare v_qty numeric; v_avg numeric;
begin
  if p_product is null then return; end if;
  if coalesce(p_qty, 0) <= 0 then return; end if;
  if p_cost is null or p_cost < 0 then return; end if;
  select coalesce(sum(quantity), 0) into v_qty
    from public.warehouse_stock where product_id = p_product;
  select coalesce(nullif(average_cost, 0), purchase_price, 0) into v_avg
    from public.products where id = p_product;
  if v_qty <= 0 then
    update public.products set average_cost = p_cost
      where id = p_product;
  else
    update public.products set average_cost =
      round((v_qty * v_avg + p_qty * p_cost) / (v_qty + p_qty), 2)
      where id = p_product;
  end if;
end $$;
