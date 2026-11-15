-- ============================================================
-- ERP Migration 0026: Sales reservation flow (حجز المبيعات والنواقص)
-- 1) ربط طلب التوريد بفاتورة المبيعات (sales_invoice_id).
-- 2) تعديل المدير لطلب التوريد (كمية/مخزن) قبل الاستلام.
-- 3) الاستلام في مخزن يحدده المدير + إشعار منشئ الفاتورة.
-- ============================================================

-- ---------- 1) عمود ربط الفاتورة ----------
alter table public.procurement_requests
  add column if not exists sales_invoice_id uuid
    references public.sales_invoices(id) on delete set null;

create index if not exists idx_pr_sales_invoice
  on public.procurement_requests (sales_invoice_id);

-- ---------- 2) تعديل طلب التوريد (المدير: كمية/مخزن) ----------
-- purchases.approve فقط، والحالات قبل الاستلام فقط.
create or replace function public.adjust_procurement_request(
  p_id uuid,
  p_warehouse_id uuid default null,
  p_items jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v record;
  ln jsonb;
  it record;
  v_qty numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('purchases.approve') then
    raise exception 'NO_PERMISSION: purchases.approve required';
  end if;

  select * into v from public.procurement_requests
    where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status not in ('DRAFT','PENDING_APPROVAL','REJECTED') then
    raise exception 'INVALID_STATUS';
  end if;

  -- تغيير المخزن (الزيادة هتنزل فيه عند الاستلام).
  if p_warehouse_id is not null then
    if not exists (select 1 from public.warehouses
        where id = p_warehouse_id) then
      raise exception 'WAREHOUSE_NOT_FOUND';
    end if;
    update public.procurement_requests
      set warehouse_id = p_warehouse_id
      where id = p_id;
  end if;

  -- تعديل الكميات المطلوبة (زيادة أو نقصان).
  if p_items is not null and jsonb_array_length(p_items) > 0 then
    for ln in select * from jsonb_array_elements(p_items) loop
      select * into it from public.procurement_items
        where id = (ln->>'item_id')::uuid
          and procurement_id = p_id for update;
      if not found then raise exception 'ITEM_NOT_FOUND'; end if;
      v_qty := coalesce((ln->>'qty')::numeric, 0);
      if v_qty <= 0 then raise exception 'INVALID_QTY'; end if;
      if v_qty < it.received_quantity then
        raise exception 'QTY_BELOW_RECEIVED';
      end if;
      update public.procurement_items
        set requested_quantity = v_qty
        where id = it.id;
    end loop;
  end if;

  perform public.refresh_procurement_availability(p_id);
  perform public.write_audit_log('ADJUST','PROCUREMENT_REQUEST',
    p_id::text, null,
    jsonb_build_object('warehouse_id', p_warehouse_id,
      'items', p_items));
end $$;

grant execute on function
  public.adjust_procurement_request(uuid, uuid, jsonb)
  to authenticated;

-- ---------- 3) الاستلام في مخزن محدد + إشعار منشئ فاتورة المبيعات ----------
-- نفس receive_procurement مع باراميتر اختياري للمخزن (توافق رجعي كامل).
create or replace function public.receive_procurement(
  p_id uuid, p_lines jsonb, p_notes text default null,
  p_warehouse_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
  ln jsonb; it record; v_take numeric;
  v_before numeric(14,3); v_after numeric(14,3);
  v_done boolean := true;
  v_wh uuid;
  v_inv record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('purchases.create')
       or public.has_permission('purchases.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into v from public.procurement_requests
    where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status not in ('APPROVED','PARTIALLY_RECEIVED') then
    raise exception 'INVALID_STATUS';
  end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'EMPTY_LINES';
  end if;

  -- المخزن المستلم: المحدد من المدير أو مخزن الطلب.
  v_wh := coalesce(p_warehouse_id, v.warehouse_id);
  if v_wh is null then raise exception 'WAREHOUSE_REQUIRED'; end if;
  if not exists (select 1 from public.warehouses
      where id = v_wh) then
    raise exception 'WAREHOUSE_NOT_FOUND';
  end if;
  if v_wh != v.warehouse_id then
    update public.procurement_requests
      set warehouse_id = v_wh where id = p_id;
  end if;

  for ln in select * from jsonb_array_elements(p_lines) loop
    select * into it from public.procurement_items
      where id = (ln->>'item_id')::uuid
        and procurement_id = p_id for update;
    if not found then raise exception 'ITEM_NOT_FOUND'; end if;
    v_take := coalesce((ln->>'qty')::numeric, 0);
    if v_take <= 0 then raise exception 'INVALID_QTY'; end if;
    if it.received_quantity + v_take >
       it.requested_quantity then
      raise exception 'OVER_RECEIVE';
    end if;
    update public.procurement_items
      set received_quantity = received_quantity + v_take
      where id = it.id;
    if it.product_id is not null then
      insert into public.warehouse_stock (warehouse_id, product_id, quantity)
        values (v_wh, it.product_id, 0)
        on conflict (warehouse_id, product_id) do nothing;
      select quantity into v_before from public.warehouse_stock
        where warehouse_id = v_wh
          and product_id = it.product_id for update;
      update public.warehouse_stock
        set quantity = quantity + v_take
        where warehouse_id = v_wh
          and product_id = it.product_id
        returning quantity into v_after;
      insert into public.stock_movements
        (warehouse_id, product_id, movement_type, quantity,
         before_quantity, after_quantity, reference_type, reference_id,
         created_by, notes)
        values (v_wh, it.product_id, 'PURCHASE', v_take,
          v_before, v_after, 'PROCUREMENT_REQUEST', p_id::text,
          v_uid, p_notes);
    end if;
  end loop;

  if exists (select 1 from public.procurement_items
      where procurement_id = p_id
        and received_quantity < requested_quantity) then
    v_done := false;
  end if;
  update public.procurement_requests
    set status = case when v_done then 'RECEIVED'::text
                      else 'PARTIALLY_RECEIVED'::text end
    where id = p_id;
  perform public.write_audit_log('RECEIVE','PROCUREMENT_REQUEST',
    p_id::text, null,
    jsonb_build_object('lines', p_lines,
      'warehouse_id', v_wh,
      'status', case when v_done then 'RECEIVED'
                     else 'PARTIALLY_RECEIVED' end));
  if v.requested_by is not null then
    perform public.create_notification(v.requested_by, 'RECEIVE',
      'تم استلام طلب توريد',
      'طلب ' || v.request_number || ' وصل ' ||
        case when v_done then 'بالكامل.' else 'جزئيا.' end,
      'PROCUREMENT_REQUEST', p_id::text);
  end if;

  -- لو الطلب مربوط بفاتورة مبيعات: نبه منشئها إن التوريد وصل
  -- والفاتورة جاهزة للاعتماد (حالة الفاتورة تتغير عند الاعتماد).
  if v.sales_invoice_id is not null then
    select * into v_inv from public.sales_invoices
      where id = v.sales_invoice_id;
    if found and v_inv.created_by is not null
        and v_inv.created_by != v_uid
        and v_inv.created_by != v.requested_by then
      perform public.create_notification(v_inv.created_by, 'RECEIVE',
        'التوريد وصل لفاتورتك',
        'طلب التوريد ' || v.request_number || ' وصل ' ||
          case when v_done then 'بالكامل.' else 'جزئيا.' end ||
          ' — الفاتورة ' ||
          coalesce(v_inv.invoice_number, '') ||
          ' جاهزة للاعتماد.',
        'SALES_INVOICE', v.sales_invoice_id::text);
    end if;
  end if;
end $$;

grant execute on function
  public.receive_procurement(uuid, jsonb, text, uuid)
  to authenticated;
