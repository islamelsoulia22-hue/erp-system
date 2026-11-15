-- ============================================================
-- ERP Migration 0032: pick serials at invoice creation.
-- اختيار السيريال اللي طالع للعميل من فورم الفاتورة نفسها:
-- 1) عمود serial_numbers على سطور المبيعات (jsonb array).
-- 2) عند الاعتماد: أي سيريالات مختارة تتسجل بيع تلقائيا
--    (العميل + السعر + التكلفة من الفاتورة) وتخرج من مخزون
--    السيريالات. المتكرر يتخطى بدون كسر الاعتماد.
-- (باقي دالة الاعتماد كما في 0028: لقطة التكلفة + الحجز +
--  التسوية التلقائية + إعفاء المدير.)
-- ============================================================

alter table public.sales_invoice_items
  add column if not exists serial_numbers jsonb not null default '[]';

create or replace function public.approve_sales_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record; it record; av numeric;
  v_total numeric; v_paid numeric; v_method text;
  ln jsonb; v_serial text;
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
  -- تسجيل السيريالات المختارة في الفاتورة (بيع + خروج من المخزون).
  for it in select * from public.sales_invoice_items
    where sales_invoice_id = p_invoice
      and coalesce(serial_numbers, '[]'::jsonb) != '[]'::jsonb loop
    for ln in select * from jsonb_array_elements(it.serial_numbers) loop
      v_serial := trim(ln #>> '{}');
      continue when v_serial = '';
      continue when exists (select 1 from public.serial_sales
        where lower(serial) = lower(v_serial));
      insert into public.serial_sales
        (serial, product_id, product_name_snapshot,
         customer_id, customer_name_snapshot, customer_phone_snapshot,
         sales_invoice_id, sales_invoice_item_id,
         unit_price, unit_cost, created_by)
        values
        (v_serial, it.product_id, it.item_name,
         v.customer_id, v.customer_name_snapshot,
         v.customer_phone_snapshot,
         p_invoice, it.id,
         it.unit_price, coalesce(it.unit_cost, 0), v_uid);
      delete from public.product_serials
        where product_id = it.product_id and lower(serial) = lower(v_serial);
    end loop;
  end loop;
  perform public.write_audit_log('APPROVE', 'SALES_INVOICE',
    p_invoice::text, jsonb_build_object('from', 'PENDING_APPROVAL'),
    jsonb_build_object('to', 'APPROVED'));
end $$;
