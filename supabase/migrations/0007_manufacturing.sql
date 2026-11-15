-- ============================================================
-- ERP Migration 0007: Customized items + Manufacturing
-- Start consumes raw materials; complete adds finished goods.
-- Every stock change logged in stock_movements, one transaction.
-- ============================================================

create sequence if not exists customized_item_seq start 1;
create sequence if not exists manufacturing_order_seq start 1;

create or replace function public.generate_customized_code()
returns text language plpgsql as $$
declare n bigint; y text;
begin
  n := nextval('customized_item_seq');
  y := to_char(now(), 'YYYY');
  return 'CZ-' || y || '-' || lpad(n::text, 6, '0');
end $$;

create or replace function public.generate_manufacturing_number()
returns text language plpgsql as $$
declare n bigint; y text;
begin
  n := nextval('manufacturing_order_seq');
  y := to_char(now(), 'YYYY');
  return 'MO-' || y || '-' || lpad(n::text, 6, '0');
end $$;

-- ---------- Customized items ----------
create table if not exists public.customized_items (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default public.generate_customized_code(),
  name text not null,
  description text,
  raw_material text,
  length numeric(10,2),
  width numeric(10,2),
  quantity numeric(14,3) not null default 1 check (quantity > 0),
  unit text,
  unit_price numeric(14,2) not null default 0 check (unit_price >= 0),
  total_price numeric(14,2) not null default 0,
  status text not null default 'DRAFT'
    check (status in ('DRAFT','PENDING_APPROVAL','APPROVED',
      'MANUFACTURING','READY','REJECTED','CANCELLED')),
  sales_order_id uuid references public.sales_orders(id) on delete set null,
  warehouse_id uuid references public.warehouses(id) on delete set null,
  created_by uuid references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Manufacturing orders ----------
create table if not exists public.manufacturing_orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique
    default public.generate_manufacturing_number(),
  customized_item_id uuid references public.customized_items(id) on delete set null,
  sales_order_id uuid references public.sales_orders(id) on delete set null,
  warehouse_id uuid references public.warehouses(id) on delete restrict,
  finished_product_id uuid references public.products(id) on delete set null,
  finished_quantity numeric(14,3) check (finished_quantity is null or finished_quantity > 0),
  status text not null default 'DRAFT'
    check (status in ('DRAFT','IN_PROGRESS','COMPLETED','CANCELLED')),
  quantity numeric(14,3) not null default 1 check (quantity > 0),
  started_at timestamptz,
  completed_at timestamptz,
  created_by uuid references public.profiles(id),
  approved_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.manufacturing_materials (
  id uuid primary key default gen_random_uuid(),
  manufacturing_order_id uuid not null references public.manufacturing_orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  required_quantity numeric(14,3) not null check (required_quantity > 0),
  consumed_quantity numeric(14,3) not null default 0 check (consumed_quantity >= 0),
  created_at timestamptz not null default now()
);

-- ---------- Indexes ----------
create index if not exists idx_cz_status on public.customized_items (status);
create index if not exists idx_cz_created on public.customized_items (created_at desc);
create index if not exists idx_mo_status on public.manufacturing_orders (status);
create index if not exists idx_mo_created on public.manufacturing_orders (created_at desc);
create index if not exists idx_mm_order on public.manufacturing_materials (manufacturing_order_id);

-- ---------- updated_at ----------
drop trigger if exists trg_cz_updated on public.customized_items;
create trigger trg_cz_updated before update on public.customized_items
  for each row execute function public.handle_updated_at();
drop trigger if exists trg_mo_updated on public.manufacturing_orders;
create trigger trg_mo_updated before update on public.manufacturing_orders
  for each row execute function public.handle_updated_at();

-- Keep total_price consistent on write
create or replace function public.cz_total()
returns trigger language plpgsql as $$
begin
  new.total_price := coalesce(new.quantity,0) * coalesce(new.unit_price,0);
  return new;
end $$;
drop trigger if exists trg_cz_total on public.customized_items;
create trigger trg_cz_total before insert or update of quantity, unit_price
  on public.customized_items for each row execute function public.cz_total();

-- ---------- RLS ----------
alter table public.customized_items enable row level security;
alter table public.manufacturing_orders enable row level security;
alter table public.manufacturing_materials enable row level security;

-- Customized: sales permissions family
drop policy if exists "cz_read" on public.customized_items;
create policy "cz_read" on public.customized_items
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('sales.view') or public.has_permission('sales.create')
    or public.has_permission('sales.edit') or public.has_permission('sales.approve')));
drop policy if exists "cz_insert" on public.customized_items;
create policy "cz_insert" on public.customized_items
  for insert to authenticated with check (public.has_permission('sales.create'));
drop policy if exists "cz_update" on public.customized_items;
create policy "cz_update" on public.customized_items
  for update to authenticated
  using (public.has_permission('sales.create') or public.has_permission('sales.edit'))
  with check (public.has_permission('sales.create') or public.has_permission('sales.edit'));
drop policy if exists "cz_delete" on public.customized_items;
create policy "cz_delete" on public.customized_items
  for delete to authenticated
  using (status = 'DRAFT' and (created_by = auth.uid()
    or public.has_permission('sales.delete')));

-- Manufacturing: inventory.adjust writes, wide read
drop policy if exists "mo_read" on public.manufacturing_orders;
create policy "mo_read" on public.manufacturing_orders
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('inventory.view') or public.has_permission('inventory.adjust')
    or public.has_permission('sales.view') or public.has_permission('warehouses.manage')));
drop policy if exists "mo_write" on public.manufacturing_orders;
create policy "mo_write" on public.manufacturing_orders
  for all to authenticated
  using (public.has_permission('inventory.adjust') or public.has_permission('warehouses.manage'))
  with check (public.has_permission('inventory.adjust') or public.has_permission('warehouses.manage'));

drop policy if exists "mm_read" on public.manufacturing_materials;
create policy "mm_read" on public.manufacturing_materials
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('inventory.view') or public.has_permission('inventory.adjust')
    or public.has_permission('sales.view') or public.has_permission('warehouses.manage')));
drop policy if exists "mm_write" on public.manufacturing_materials;
create policy "mm_write" on public.manufacturing_materials
  for all to authenticated
  using (public.has_permission('inventory.adjust') or public.has_permission('warehouses.manage'))
  with check (public.has_permission('inventory.adjust') or public.has_permission('warehouses.manage'));

-- ============================================================
-- RPCs
-- ============================================================
create or replace function public.submit_customized_item(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('sales.create')
       or public.has_permission('sales.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into v from public.customized_items where id = p_id;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status not in ('DRAFT','REJECTED') then raise exception 'INVALID_STATUS'; end if;
  update public.customized_items set status='PENDING_APPROVAL' where id=p_id;
  perform public.write_audit_log('STATUS_CHANGE','CUSTOMIZED_ITEM',
    p_id::text, jsonb_build_object('from', v.status),
    jsonb_build_object('to','PENDING_APPROVAL'));
end $$;

create or replace function public.approve_customized_item(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('sales.approve') then
    raise exception 'NO_PERMISSION: sales.approve required';
  end if;
  select * into v from public.customized_items where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذا الصنف';
  end if;
  update public.customized_items set status='APPROVED',
    approved_by=v_uid, approved_at=now() where id=p_id;
  perform public.write_audit_log('APPROVE','CUSTOMIZED_ITEM',
    p_id::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','APPROVED'));
end $$;

create or replace function public.reject_customized_item(
  p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('sales.approve') then
    raise exception 'NO_PERMISSION: sales.approve required';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'REASON_REQUIRED';
  end if;
  select * into v from public.customized_items where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذا الصنف';
  end if;
  update public.customized_items set status='REJECTED' where id=p_id;
  perform public.write_audit_log('REJECT','CUSTOMIZED_ITEM',
    p_id::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','REJECTED','reason',p_reason));
end $$;

-- Start: consume all required materials atomically
create or replace function public.start_manufacturing(p_order uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); o record; m record;
  av numeric; v_before numeric; v_after numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('inventory.adjust')
       or public.has_permission('warehouses.manage')) then
    raise exception 'NO_PERMISSION: inventory.adjust required';
  end if;
  select * into o from public.manufacturing_orders
    where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.status != 'DRAFT' then raise exception 'INVALID_STATUS'; end if;
  if o.warehouse_id is null then raise exception 'WAREHOUSE_REQUIRED'; end if;
  if o.customized_item_id is not null then
    if not exists (select 1 from public.customized_items
        where id = o.customized_item_id and status in ('APPROVED','MANUFACTURING')) then
      raise exception 'CUSTOMIZED_NOT_APPROVED';
    end if;
  end if;
  if not exists (select 1 from public.manufacturing_materials
      where manufacturing_order_id = p_order) then
    raise exception 'EMPTY_MATERIALS';
  end if;

  for m in select * from public.manufacturing_materials
    where manufacturing_order_id = p_order for update loop
    if m.product_id is null then raise exception 'MATERIAL_NO_PRODUCT'; end if;
    select quantity - reserved_quantity into av from public.warehouse_stock
      where warehouse_id = o.warehouse_id and product_id = m.product_id
      for update;
    if not found or av < m.required_quantity then
      raise exception 'INSUFFICIENT_STOCK';
    end if;
    select quantity into v_before from public.warehouse_stock
      where warehouse_id = o.warehouse_id and product_id = m.product_id;
    update public.warehouse_stock
      set quantity = quantity - m.required_quantity
      where warehouse_id = o.warehouse_id and product_id = m.product_id
      returning quantity into v_after;
    update public.manufacturing_materials
      set consumed_quantity = m.required_quantity where id = m.id;
    insert into public.stock_movements
      (warehouse_id, product_id, movement_type, quantity,
       before_quantity, after_quantity, reference_type, reference_id,
       created_by, notes)
      values (o.warehouse_id, m.product_id, 'MANUFACTURING_OUT',
        m.required_quantity, v_before, v_after,
        'MANUFACTURING_ORDER', p_order::text, v_uid, 'start');
  end loop;

  update public.manufacturing_orders
    set status='IN_PROGRESS', started_at=now() where id=p_order;
  if o.customized_item_id is not null then
    update public.customized_items set status='MANUFACTURING'
      where id=o.customized_item_id;
  end if;
  perform public.write_audit_log('STATUS_CHANGE','MANUFACTURING_ORDER',
    p_order::text, jsonb_build_object('from','DRAFT'),
    jsonb_build_object('to','IN_PROGRESS'));
end $$;

-- Complete: add finished goods (if set) with MANUFACTURING_IN
create or replace function public.complete_manufacturing(p_order uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); o record;
  v_before numeric(14,3) := 0; v_after numeric(14,3);
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('inventory.adjust')
       or public.has_permission('warehouses.manage')) then
    raise exception 'NO_PERMISSION: inventory.adjust required';
  end if;
  select * into o from public.manufacturing_orders
    where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.status != 'IN_PROGRESS' then raise exception 'INVALID_STATUS'; end if;

  if o.finished_product_id is not null
     and o.finished_quantity is not null then
    insert into public.warehouse_stock (warehouse_id, product_id, quantity)
      values (o.warehouse_id, o.finished_product_id, 0)
      on conflict (warehouse_id, product_id) do nothing;
    select quantity into v_before from public.warehouse_stock
      where warehouse_id = o.warehouse_id
        and product_id = o.finished_product_id for update;
    update public.warehouse_stock
      set quantity = quantity + o.finished_quantity
      where warehouse_id = o.warehouse_id
        and product_id = o.finished_product_id
      returning quantity into v_after;
    insert into public.stock_movements
      (warehouse_id, product_id, movement_type, quantity,
       before_quantity, after_quantity, reference_type, reference_id,
       created_by, notes)
      values (o.warehouse_id, o.finished_product_id, 'MANUFACTURING_IN',
        o.finished_quantity, v_before, v_after,
        'MANUFACTURING_ORDER', p_order::text, v_uid, 'complete');
  end if;

  update public.manufacturing_orders
    set status='COMPLETED', completed_at=now() where id=p_order;
  if o.customized_item_id is not null then
    update public.customized_items set status='READY'
      where id=o.customized_item_id;
  end if;
  perform public.write_audit_log('STATUS_CHANGE','MANUFACTURING_ORDER',
    p_order::text, jsonb_build_object('from','IN_PROGRESS'),
    jsonb_build_object('to','COMPLETED'));
end $$;
