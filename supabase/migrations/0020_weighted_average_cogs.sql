-- ============================================================
-- ERP Migration 0020: Profits phase 3 — Weighted Average COGS
-- ============================================================
-- 1) products.average_cost: متوسط مرجح متحرك لكل صنف.
-- 2) apply_purchase_cost(): تحدث المتوسط عند كل استلام مشتريات.
-- 3) sales_invoice_items.unit_cost: لقطة التكلفة لحظة الاعتماد
--    (تثبت التاريخ حتى لو تغير المتوسط بعدها).
-- 4) ترقيع receive_purchase_order + approve_sales_invoice.
--
-- طريقة التطبيق: نفّذ الملف ده في Supabase Dashboard > SQL Editor.

-- ---------- 1) عمود المتوسط + تعبئة أولية ----------
alter table public.products
  add column if not exists average_cost numeric(14,2) not null default 0;

-- الأصناف الحالية: المتوسط الافتتاحي = سعر الشراء المسجل.
update public.products
  set average_cost = purchase_price
  where average_cost = 0;

-- ---------- 2) دالة المتوسط المرجح ----------
create or replace function public.apply_purchase_cost(
  p_product uuid, p_qty numeric, p_cost numeric)
returns void language plpgsql security definer set search_path = public as $$
declare v_qty numeric; v_avg numeric;
begin
  if p_product is null then return; end if;
  if coalesce(p_qty, 0) <= 0 then return; end if;
  if p_cost is null or p_cost < 0 then return; end if;
  -- إجمالي الرصيد قبل الاستلام الحالي.
  select coalesce(sum(quantity), 0) into v_qty
    from public.warehouse_stock where product_id = p_product;
  select coalesce(average_cost, 0) into v_avg
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

-- ---------- 3) عمود لقطة التكلفة على سطور البيع ----------
alter table public.sales_invoice_items
  add column if not exists unit_cost numeric(14,2) not null default 0;

-- تعبئة تاريخية للفواتير المعتمدة بالفعل (تقريبية بالمتوسط الحالي).
update public.sales_invoice_items sii
  set unit_cost = coalesce(p.average_cost, p.purchase_price, 0)
  from public.products p, public.sales_invoices si
  where p.id = sii.product_id
    and si.id = sii.sales_invoice_id
    and sii.product_id is not null
    and sii.unit_cost = 0
    and si.status = 'APPROVED';

-- ---------- 4) ترقيع الاستلام: تحديث المتوسط قبل زيادة الرصيد ----------
create or replace function public.receive_purchase_order(
  p_order uuid, p_lines jsonb, p_notes text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v record;
  ln jsonb; v_item record;
  v_rem numeric; v_take numeric;
  v_before numeric(14,3); v_after numeric(14,3);
  v_all_done boolean := true;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('purchases.create')
       or public.has_permission('purchases.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into v from public.purchase_orders where id = p_order for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v.status not in ('ORDERED','PARTIALLY_RECEIVED') then
    raise exception 'INVALID_STATUS';
  end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'EMPTY_LINES';
  end if;

  for ln in select * from jsonb_array_elements(p_lines) loop
    select * into v_item from public.purchase_order_items
      where id = (ln->>'item_id')::uuid
        and purchase_order_id = p_order for update;
    if not found then raise exception 'ITEM_NOT_FOUND'; end if;
    v_take := coalesce((ln->>'qty')::numeric, 0);
    if v_take <= 0 then raise exception 'INVALID_QTY'; end if;
    v_rem := v_item.quantity - v_item.received_quantity;
    if v_take > v_rem then
      raise exception 'OVER_RECEIVE: %', v_item.product_name;
    end if;

    update public.purchase_order_items
      set received_quantity = received_quantity + v_take
      where id = v_item.id;

    -- Stock increase (create row if missing)
    if v_item.product_id is not null then
      -- المتوسط المرجح قبل الزيادة (المرحلة 3: الأرباح).
      perform public.apply_purchase_cost(
        v_item.product_id, v_take, v_item.unit_cost);
      insert into public.warehouse_stock (warehouse_id, product_id, quantity)
        values (v.warehouse_id, v_item.product_id, 0)
        on conflict (warehouse_id, product_id) do nothing;
      select quantity into v_before from public.warehouse_stock
        where warehouse_id = v.warehouse_id
          and product_id = v_item.product_id for update;
      update public.warehouse_stock
        set quantity = quantity + v_take
        where warehouse_id = v.warehouse_id
          and product_id = v_item.product_id
        returning quantity into v_after;
      insert into public.stock_movements
        (warehouse_id, product_id, movement_type, quantity,
         before_quantity, after_quantity, reference_type, reference_id,
         created_by, notes)
        values (v.warehouse_id, v_item.product_id, 'PURCHASE', v_take,
          v_before, v_after, 'PURCHASE_ORDER', p_order::text, v_uid, p_notes);
    end if;
  end loop;

  -- Recompute order status
  if exists (select 1 from public.purchase_order_items
      where purchase_order_id = p_order
        and received_quantity < quantity) then
    v_all_done := false;
  end if;
  update public.purchase_orders
    set status = case when v_all_done then 'RECEIVED'::text
                      else 'PARTIALLY_RECEIVED'::text end
    where id = p_order;
  perform public.write_audit_log('RECEIVE','PURCHASE_ORDER',
    p_order::text, null,
    jsonb_build_object('lines', p_lines,
      'status', case when v_all_done then 'RECEIVED'
                     else 'PARTIALLY_RECEIVED' end));
end $$;

-- ---------- 5) ترقيع الاعتماد: لقطة التكلفة لكل سطر ----------
-- (نفس نسخة 0012 مع خطوة اللقطة؛ تحافظ على إعفاء المدير.)
create or replace function public.approve_sales_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record; it record; av numeric;
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
  -- لقطة تكلفة البضاعة (المتوسط المرجح لحظة الاعتماد).
  update public.sales_invoice_items sii
    set unit_cost = coalesce(p.average_cost, p.purchase_price, 0)
    from public.products p
    where p.id = sii.product_id
      and sii.sales_invoice_id = p_invoice
      and sii.product_id is not null;
  -- Reserve each tracked product
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
  perform public.write_audit_log('APPROVE', 'SALES_INVOICE',
    p_invoice::text, jsonb_build_object('from', 'PENDING_APPROVAL'),
    jsonb_build_object('to', 'APPROVED'));
end $$;
