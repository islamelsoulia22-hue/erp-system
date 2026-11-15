-- ============================================================
-- ERP Migration 0029: Returns policy + remaining qty + window.
-- 1) سياسة المرتجعات في app_settings (المدير يحدد مدة المرتجع
--    بعد إنشاء الفاتورة: null = بدون حد، أو عدد ساعات).
--    مفاتيح: return_policy = {"sales_window_hours": null,
--                             "purchase_window_hours": null}
-- 2) RPCs للمتبقي القابل للإرجاع per صنف (الفاتورة - المكتمل).
-- 3) منع إتمام المرتجع بعد انتهاء المدة (RETURN_WINDOW_EXPIRED).
-- ملاحظة: المخزون كان بيرجع تلقائيا لمخزن المرتجع عند الإتمام
-- (complete_* يزود/يخصم warehouse_stock) — الترحيل ده يضيف
-- حد المدة + قراءة المتبقي، بدون تغيير حركة المخزون.
-- ============================================================

-- ---------- 1) seed السياسة (بدون حد = سلوك اليوم) ----------
insert into public.app_settings (key, value) values
  ('return_policy',
   '{"sales_window_hours": null, "purchase_window_hours": null}')
on conflict (key) do nothing;

-- ---------- 2) المتبقي القابل للإرجاع: مبيعات ----------
create or replace function public.sales_returnable(p_invoice uuid)
returns table (
  product_id uuid, item_name text, sku text,
  unit_price numeric, tax_rate numeric,
  invoiced_qty numeric, returned_qty numeric, remaining_qty numeric
)
language sql stable security definer set search_path = public as $$
  with inv as (
    select sii.product_id,
           min(sii.item_name) as item_name,
           min(sii.sku) as sku,
           min(sii.unit_price) as unit_price,
           min(sii.tax_rate) as tax_rate,
           sum(sii.quantity) as invoiced_qty
      from public.sales_invoice_items sii
     where sii.sales_invoice_id = p_invoice
     group by sii.product_id
  ),
  ret as (
    select sri.product_id, sum(sri.quantity) as returned_qty
      from public.sales_return_items sri
      join public.sales_returns sr on sr.id = sri.sales_return_id
     where sr.sales_invoice_id = p_invoice
       and sr.status = 'COMPLETED'
     group by sri.product_id
  )
  select i.product_id, i.item_name, i.sku, i.unit_price, i.tax_rate,
         i.invoiced_qty,
         coalesce(r.returned_qty, 0) as returned_qty,
         greatest(0, i.invoiced_qty - coalesce(r.returned_qty, 0))
           as remaining_qty
    from inv i
    left join ret r on r.product_id is not distinct from i.product_id
   order by i.item_name;
$$;

-- ---------- 3) المتبقي القابل للإرجاع: مشتريات ----------
create or replace function public.purchase_returnable(p_invoice uuid)
returns table (
  product_id uuid, item_name text, sku text,
  unit_cost numeric, tax_rate numeric,
  invoiced_qty numeric, returned_qty numeric, remaining_qty numeric
)
language sql stable security definer set search_path = public as $$
  with inv as (
    select poi.product_id,
           min(poi.product_name_snapshot) as item_name,
           min(poi.sku_snapshot) as sku,
           min(poi.unit_cost) as unit_cost,
           min(poi.tax_rate) as tax_rate,
           sum(poi.quantity) as invoiced_qty
      from public.purchase_invoice_items poi
     where poi.purchase_invoice_id = p_invoice
     group by poi.product_id
  ),
  ret as (
    select pri.product_id, sum(pri.quantity) as returned_qty
      from public.purchase_return_items pri
      join public.purchase_returns pr on pr.id = pri.purchase_return_id
     where pr.purchase_invoice_id = p_invoice
       and pr.status = 'COMPLETED'
     group by pri.product_id
  )
  select i.product_id, i.item_name, i.sku, i.unit_cost, i.tax_rate,
         i.invoiced_qty,
         coalesce(r.returned_qty, 0) as returned_qty,
         greatest(0, i.invoiced_qty - coalesce(r.returned_qty, 0))
           as remaining_qty
    from inv i
    left join ret r on r.product_id is not distinct from i.product_id
   order by i.item_name;
$$;

-- ---------- 4) حد المدة عند إتمام مرتجع المبيعات ----------
create or replace function public.return_window_hours(p_kind text)
returns numeric language sql stable security definer
set search_path = public as $$
  select case
    when p_kind = 'SALES' then
      ((select value->>'sales_window_hours' from public.app_settings
         where key = 'return_policy')::numeric)
    else
      ((select value->>'purchase_window_hours' from public.app_settings
         where key = 'return_policy')::numeric)
  end;
$$;

create or replace function public.assert_return_window(
  p_kind text, p_invoice_created timestamptz)
returns void language plpgsql security definer
set search_path = public as $$
declare v_hours numeric;
begin
  -- null أو غائب = بدون حد (سلوك اليوم).
  begin
    v_hours := public.return_window_hours(p_kind);
  exception when others then
    v_hours := null;
  end;
  if v_hours is null then return; end if;
  if v_hours < 0 then return; end if;
  if p_invoice_created is null then return; end if;
  if now() > p_invoice_created + (v_hours || ' hours')::interval then
    raise exception
      'RETURN_WINDOW_EXPIRED: انتهت مدة المرتجع لهذه الفاتورة (المسموح % ساعة من إنشائها)',
      v_hours;
  end if;
end $$;

-- ---------- 5) ترقيع إتمام المبيعات: حد المدة ----------
-- (نفس complete_sales_return في 0010 + سطر حد المدة فقط.
--  منع التجاوز موجود أصلا OVER_RETURN، وزيادة المخزون تلقائية.)
create or replace function public.complete_sales_return(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); r record; it record;
  v_before numeric(14,3); v_after numeric(14,3);
  v_sub numeric(14,2) := 0; v_tax numeric(14,2) := 0;
  inv_qty numeric; inv_created timestamptz;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('sales.create')
       or public.has_permission('sales.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into r from public.sales_returns where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if r.status != 'DRAFT' then raise exception 'INVALID_STATUS'; end if;
  if r.warehouse_id is null then raise exception 'WAREHOUSE_REQUIRED'; end if;
  -- حد مدة المرتجع (سياسة المدير).
  if r.sales_invoice_id is not null then
    select si.created_at into inv_created from public.sales_invoices si
      where si.id = r.sales_invoice_id;
    perform public.assert_return_window('SALES', inv_created);
  end if;

  for it in select * from public.sales_return_items
    where sales_return_id = p_id for update loop
    if r.sales_invoice_id is not null and it.product_id is not null then
      select coalesce(sum(quantity),0) into inv_qty
        from public.sales_invoice_items
        where sales_invoice_id = r.sales_invoice_id
          and product_id = it.product_id;
      if it.quantity > inv_qty - coalesce((
          select sum(sri.quantity) from public.sales_return_items sri
          join public.sales_returns sr on sr.id = sri.sales_return_id
          where sr.sales_invoice_id = r.sales_invoice_id
            and sri.product_id = it.product_id
            and sr.status = 'COMPLETED'), 0) then
        raise exception 'OVER_RETURN: %', it.item_name;
      end if;
    end if;
    declare line numeric(14,2); t numeric(14,2);
    begin
      line := it.quantity * it.unit_price;
      t := round(line * coalesce(it.tax_rate,0) / 100, 2);
      update public.sales_return_items
        set tax_amount = t, total = line + t where id = it.id;
      v_sub := v_sub + line; v_tax := v_tax + t;
    end;
    if it.product_id is not null then
      insert into public.warehouse_stock (warehouse_id, product_id, quantity)
        values (r.warehouse_id, it.product_id, 0)
        on conflict (warehouse_id, product_id) do nothing;
      select quantity into v_before from public.warehouse_stock
        where warehouse_id = r.warehouse_id
          and product_id = it.product_id for update;
      update public.warehouse_stock
        set quantity = quantity + it.quantity
        where warehouse_id = r.warehouse_id
          and product_id = it.product_id
        returning quantity into v_after;
      insert into public.stock_movements
        (warehouse_id, product_id, movement_type, quantity,
         before_quantity, after_quantity, reference_type, reference_id,
         created_by, notes)
        values (r.warehouse_id, it.product_id, 'SALES_RETURN',
          it.quantity, v_before, v_after,
          'SALES_RETURN', p_id::text, v_uid, r.reason);
    end if;
  end loop;

  update public.sales_returns
    set status='COMPLETED', subtotal=v_sub, tax_amount=v_tax,
        grand_total=v_sub + v_tax where id=p_id;
  perform public.write_audit_log('COMPLETE','SALES_RETURN',
    p_id::text, jsonb_build_object('from','DRAFT'),
    jsonb_build_object('to','COMPLETED'));
end $$;

-- ---------- 6) ترقيع إتمام المشتريات: حد المدة ----------
create or replace function public.complete_purchase_return(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); r record; it record;
  v_before numeric(14,3); v_after numeric(14,3);
  v_sub numeric(14,2) := 0; v_tax numeric(14,2) := 0;
  inv_created timestamptz;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('purchases.create')
       or public.has_permission('purchases.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into r from public.purchase_returns where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if r.status != 'DRAFT' then raise exception 'INVALID_STATUS'; end if;
  if r.warehouse_id is null then raise exception 'WAREHOUSE_REQUIRED'; end if;
  if r.purchase_invoice_id is not null then
    select pi.created_at into inv_created from public.purchase_invoices pi
      where pi.id = r.purchase_invoice_id;
    perform public.assert_return_window('PURCHASE', inv_created);
  end if;

  for it in select * from public.purchase_return_items
    where purchase_return_id = p_id for update loop
    declare line numeric(14,2); t numeric(14,2);
    begin
      line := it.quantity * it.unit_cost;
      t := round(line * coalesce(it.tax_rate,0) / 100, 2);
      update public.purchase_return_items
        set tax_amount = t, total = line + t where id = it.id;
      v_sub := v_sub + line; v_tax := v_tax + t;
    end;
    if it.product_id is not null then
      select quantity into v_before from public.warehouse_stock
        where warehouse_id = r.warehouse_id
          and product_id = it.product_id for update;
      if not found or v_before < it.quantity then
        raise exception 'INSUFFICIENT_STOCK';
      end if;
      update public.warehouse_stock
        set quantity = quantity - it.quantity
        where warehouse_id = r.warehouse_id
          and product_id = it.product_id
        returning quantity into v_after;
      insert into public.stock_movements
        (warehouse_id, product_id, movement_type, quantity,
         before_quantity, after_quantity, reference_type, reference_id,
         created_by, notes)
        values (r.warehouse_id, it.product_id, 'PURCHASE_RETURN',
          it.quantity, v_before, v_after,
          'PURCHASE_RETURN', p_id::text, v_uid, r.reason);
    end if;
  end loop;

  update public.purchase_returns
    set status='COMPLETED', subtotal=v_sub, tax_amount=v_tax,
        grand_total=v_sub + v_tax where id=p_id;
  perform public.write_audit_log('COMPLETE','PURCHASE_RETURN',
    p_id::text, jsonb_build_object('from','DRAFT'),
    jsonb_build_object('to','COMPLETED'));
end $$;
