-- ============================================================
-- ERP Migration 0006: Purchases (orders, invoices, receiving)
-- Stock increases ONLY on receiving, never on invoice creation.
-- ============================================================

create sequence if not exists purchase_order_seq start 1;
create sequence if not exists purchase_invoice_seq start 1;

create or replace function public.generate_purchase_order_number()
returns text language plpgsql as $$
declare n bigint; y text;
begin
  n := nextval('purchase_order_seq');
  y := to_char(now(), 'YYYY');
  return 'PO-' || y || '-' || lpad(n::text, 6, '0');
end $$;

create or replace function public.generate_purchase_invoice_number()
returns text language plpgsql as $$
declare n bigint; y text;
begin
  n := nextval('purchase_invoice_seq');
  y := to_char(now(), 'YYYY');
  return 'PUR-' || y || '-' || lpad(n::text, 6, '0');
end $$;

-- ---------- Purchase orders ----------
create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique default public.generate_purchase_order_number(),
  reference_number text,
  supplier_id uuid references public.suppliers(id) on delete set null,
  warehouse_id uuid references public.warehouses(id) on delete restrict,
  status text not null default 'DRAFT'
    check (status in ('DRAFT','ORDERED','PARTIALLY_RECEIVED','RECEIVED','CANCELLED')),
  subtotal numeric(14,2) not null default 0,
  discount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  sku text,
  quantity numeric(14,3) not null check (quantity > 0),
  received_quantity numeric(14,3) not null default 0 check (received_quantity >= 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  discount numeric(14,2) not null default 0 check (discount >= 0),
  tax_rate numeric(5,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0
);

-- ---------- Purchase invoices ----------
create table if not exists public.purchase_invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique default public.generate_purchase_invoice_number(),
  reference_number text,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  supplier_name_snapshot text,
  supplier_phone_snapshot text,
  supplier_address_snapshot text,
  supplier_tax_number_snapshot text,
  warehouse_id uuid references public.warehouses(id) on delete restrict,
  status text not null default 'DRAFT'
    check (status in ('DRAFT','PENDING_APPROVAL','APPROVED','REJECTED','CANCELLED')),
  subtotal numeric(14,2) not null default 0,
  discount numeric(14,2) not null default 0,
  taxable_amount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  payment_method_id uuid references public.payment_methods(id),
  payment_status text not null default 'UNPAID'
    check (payment_status in ('UNPAID','PARTIAL','PAID')),
  created_by uuid references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  rejected_by uuid references public.profiles(id),
  rejected_at timestamptz,
  rejection_reason text,
  received_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.purchase_invoice_items (
  id uuid primary key default gen_random_uuid(),
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name_snapshot text not null,
  sku_snapshot text,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  discount numeric(14,2) not null default 0 check (discount >= 0),
  tax_rate numeric(5,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0
);

-- ---------- Indexes ----------
create index if not exists idx_po_number on public.purchase_orders (order_number);
create index if not exists idx_po_supplier on public.purchase_orders (supplier_id);
create index if not exists idx_po_status on public.purchase_orders (status);
create index if not exists idx_po_created on public.purchase_orders (created_at desc);
create index if not exists idx_poi_order on public.purchase_order_items (purchase_order_id);
create index if not exists idx_pi_number on public.purchase_invoices (invoice_number);
create index if not exists idx_pi_supplier on public.purchase_invoices (supplier_id);
create index if not exists idx_pi_status on public.purchase_invoices (status);
create index if not exists idx_pi_created on public.purchase_invoices (created_at desc);
create index if not exists idx_pii_invoice on public.purchase_invoice_items (purchase_invoice_id);

-- ---------- updated_at ----------
drop trigger if exists trg_po_updated on public.purchase_orders;
create trigger trg_po_updated before update on public.purchase_orders
  for each row execute function public.handle_updated_at();
drop trigger if exists trg_pi_updated on public.purchase_invoices;
create trigger trg_pi_updated before update on public.purchase_invoices
  for each row execute function public.handle_updated_at();

-- ---------- RLS ----------
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.purchase_invoices enable row level security;
alter table public.purchase_invoice_items enable row level security;

drop policy if exists "po_read" on public.purchase_orders;
create policy "po_read" on public.purchase_orders
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('purchases.view') or public.has_permission('purchases.create')
    or public.has_permission('purchases.edit') or public.has_permission('purchases.approve')));
drop policy if exists "po_insert" on public.purchase_orders;
create policy "po_insert" on public.purchase_orders
  for insert to authenticated with check (public.has_permission('purchases.create'));
drop policy if exists "po_update" on public.purchase_orders;
create policy "po_update" on public.purchase_orders
  for update to authenticated
  using (public.has_permission('purchases.create') or public.has_permission('purchases.edit'))
  with check (public.has_permission('purchases.create') or public.has_permission('purchases.edit'));
drop policy if exists "po_delete" on public.purchase_orders;
create policy "po_delete" on public.purchase_orders
  for delete to authenticated
  using (status = 'DRAFT' and (created_by = auth.uid()
    or public.has_permission('purchases.create')));

drop policy if exists "poi_rw" on public.purchase_order_items;
create policy "poi_rw" on public.purchase_order_items
  for all to authenticated
  using (public.has_permission('purchases.create') or public.has_permission('purchases.edit')
    or public.has_permission('purchases.view'))
  with check (public.has_permission('purchases.create') or public.has_permission('purchases.edit'));

drop policy if exists "pi_read" on public.purchase_invoices;
create policy "pi_read" on public.purchase_invoices
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('purchases.view') or public.has_permission('purchases.create')
    or public.has_permission('purchases.edit') or public.has_permission('purchases.approve')));
drop policy if exists "pi_insert" on public.purchase_invoices;
create policy "pi_insert" on public.purchase_invoices
  for insert to authenticated with check (public.has_permission('purchases.create'));
drop policy if exists "pi_update" on public.purchase_invoices;
create policy "pi_update" on public.purchase_invoices
  for update to authenticated
  using (public.has_permission('purchases.create') or public.has_permission('purchases.edit'))
  with check (public.has_permission('purchases.create') or public.has_permission('purchases.edit'));
drop policy if exists "pi_delete" on public.purchase_invoices;
create policy "pi_delete" on public.purchase_invoices
  for delete to authenticated
  using (status = 'DRAFT' and (created_by = auth.uid()
    or public.has_permission('purchases.create')));

drop policy if exists "pii_rw" on public.purchase_invoice_items;
create policy "pii_rw" on public.purchase_invoice_items
  for all to authenticated
  using (public.has_permission('purchases.create') or public.has_permission('purchases.edit')
    or public.has_permission('purchases.view'))
  with check (public.has_permission('purchases.create') or public.has_permission('purchases.edit'));

-- ============================================================
-- RPCs
-- ============================================================
create or replace function public.recalc_purchase_order(p_order uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_sub numeric(14,2):=0; v_disc numeric(14,2):=0;
  v_tax numeric(14,2):=0; v_tot numeric(14,2):=0; r record;
begin
  for r in select * from public.purchase_order_items
    where purchase_order_id = p_order loop
    declare line numeric(14,2); t numeric(14,2);
    begin
      line := greatest(0, r.quantity * r.unit_cost - coalesce(r.discount,0));
      t := round(line * coalesce(r.tax_rate,0) / 100, 2);
      update public.purchase_order_items
        set tax_amount = t, total = line + t where id = r.id;
      v_sub := v_sub + r.quantity * r.unit_cost;
      v_disc := v_disc + coalesce(r.discount,0);
      v_tax := v_tax + t; v_tot := v_tot + line + t;
    end;
  end loop;
  update public.purchase_orders set subtotal=v_sub, discount=v_disc,
    tax_amount=v_tax, grand_total=v_tot where id=p_order;
end $$;

create or replace function public.recalc_purchase_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_sub numeric(14,2):=0; v_disc numeric(14,2):=0;
  v_tax numeric(14,2):=0; v_tot numeric(14,2):=0; r record;
begin
  for r in select * from public.purchase_invoice_items
    where purchase_invoice_id = p_invoice loop
    declare line numeric(14,2); t numeric(14,2);
    begin
      line := greatest(0, r.quantity * r.unit_cost - coalesce(r.discount,0));
      t := round(line * coalesce(r.tax_rate,0) / 100, 2);
      update public.purchase_invoice_items
        set tax_amount = t, total = line + t where id = r.id;
      v_sub := v_sub + r.quantity * r.unit_cost;
      v_disc := v_disc + coalesce(r.discount,0);
      v_tax := v_tax + t; v_tot := v_tot + line + t;
    end;
  end loop;
  update public.purchase_invoices set subtotal=v_sub, discount=v_disc,
    taxable_amount=greatest(0, v_sub - v_disc),
    tax_amount=v_tax, grand_total=v_tot where id=p_invoice;
end $$;

-- Order DRAFT -> ORDERED
create or replace function public.submit_purchase_order(p_order uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('purchases.create')
       or public.has_permission('purchases.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into v from public.purchase_orders where id = p_order;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v.status != 'DRAFT' then raise exception 'INVALID_STATUS'; end if;
  if v.supplier_id is null then raise exception 'SUPPLIER_REQUIRED'; end if;
  if v.warehouse_id is null then raise exception 'WAREHOUSE_REQUIRED'; end if;
  if not exists (select 1 from public.purchase_order_items
      where purchase_order_id = p_order) then
    raise exception 'EMPTY_ORDER';
  end if;
  perform public.recalc_purchase_order(p_order);
  update public.purchase_orders set status='ORDERED' where id=p_order;
  perform public.write_audit_log('STATUS_CHANGE','PURCHASE_ORDER',
    p_order::text, jsonb_build_object('from','DRAFT'),
    jsonb_build_object('to','ORDERED'));
end $$;

-- Invoice DRAFT/REJECTED -> PENDING (snapshot supplier; NO stock change)
create or replace function public.submit_purchase_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record; s record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('purchases.create')
       or public.has_permission('purchases.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into v from public.purchase_invoices where id = p_invoice;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  if v.status not in ('DRAFT','REJECTED') then raise exception 'INVALID_STATUS'; end if;
  if v.supplier_id is null then raise exception 'SUPPLIER_REQUIRED'; end if;
  if v.warehouse_id is null then raise exception 'WAREHOUSE_REQUIRED'; end if;
  if not exists (select 1 from public.purchase_invoice_items
      where purchase_invoice_id = p_invoice) then
    raise exception 'EMPTY_INVOICE';
  end if;
  select * into s from public.suppliers where id = v.supplier_id;
  if found then
    update public.purchase_invoices set
      supplier_name_snapshot = s.name,
      supplier_phone_snapshot = s.phone,
      supplier_address_snapshot = s.address,
      supplier_tax_number_snapshot = s.tax_number
      where id = p_invoice;
  end if;
  perform public.recalc_purchase_invoice(p_invoice);
  update public.purchase_invoices set status='PENDING_APPROVAL',
    rejected_by=null, rejected_at=null, rejection_reason=null
    where id = p_invoice;
  perform public.write_audit_log('STATUS_CHANGE','PURCHASE_INVOICE',
    p_invoice::text, jsonb_build_object('from', v.status),
    jsonb_build_object('to','PENDING_APPROVAL'));
end $$;

create or replace function public.approve_purchase_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('purchases.approve') then
    raise exception 'NO_PERMISSION: purchases.approve required';
  end if;
  select * into v from public.purchase_invoices where id = p_invoice for update;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذه الفاتورة';
  end if;
  perform public.recalc_purchase_invoice(p_invoice);
  -- NOTE: no stock change here by design.
  update public.purchase_invoices set status='APPROVED',
    approved_by=v_uid, approved_at=now(),
    rejected_by=null, rejected_at=null, rejection_reason=null
    where id = p_invoice;
  perform public.write_audit_log('APPROVE','PURCHASE_INVOICE',
    p_invoice::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','APPROVED'));
end $$;

create or replace function public.reject_purchase_invoice(
  p_invoice uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('purchases.approve') then
    raise exception 'NO_PERMISSION: purchases.approve required';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'REASON_REQUIRED';
  end if;
  select * into v from public.purchase_invoices where id = p_invoice for update;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذه الفاتورة';
  end if;
  update public.purchase_invoices set status='REJECTED',
    rejected_by=v_uid, rejected_at=now(), rejection_reason=p_reason,
    approved_by=null, approved_at=null where id = p_invoice;
  perform public.write_audit_log('REJECT','PURCHASE_INVOICE',
    p_invoice::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','REJECTED','reason',p_reason));
end $$;

-- Receiving: partial supported; ONLY path that increases stock.
-- p_lines: jsonb array [{item_id, qty}]
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
