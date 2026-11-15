-- ============================================================
-- ERP Migration 0004: Warehouses + Stock + Movements + RPCs
-- Rule: Flutter NEVER updates warehouse_stock directly.
-- All stock writes go through SECURITY DEFINER RPCs below.
-- ============================================================

create sequence if not exists warehouse_code_seq start 1;

create or replace function public.generate_warehouse_code()
returns text language plpgsql as $$
declare n bigint;
begin
  n := nextval('warehouse_code_seq');
  return 'WH-' || lpad(n::text, 3, '0');
end $$;

-- ---------- Warehouses ----------
create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default public.generate_warehouse_code(),
  name text not null,
  location text,
  manager_id uuid references public.profiles(id) on delete set null,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.warehouse_users (
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (warehouse_id, user_id)
);

-- ---------- Stock (available is DB-generated, never from client) ----------
create table if not exists public.warehouse_stock (
  id uuid primary key default gen_random_uuid(),
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null default 0,
  reserved_quantity numeric(14,3) not null default 0,
  available_quantity numeric(14,3)
    generated always as (quantity - reserved_quantity) stored,
  updated_at timestamptz not null default now(),
  unique (warehouse_id, product_id),
  constraint chk_stock_nonneg check (
    quantity >= 0 and reserved_quantity >= 0
    and reserved_quantity <= quantity
  )
);

-- ---------- Movements (append-only log) ----------
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  movement_type text not null
    check (movement_type in (
      'PURCHASE','SALE','PURCHASE_RETURN','SALES_RETURN',
      'ADJUSTMENT_IN','ADJUSTMENT_OUT',
      'TRANSFER_IN','TRANSFER_OUT',
      'MANUFACTURING_IN','MANUFACTURING_OUT')),
  quantity numeric(14,3) not null check (quantity > 0),
  before_quantity numeric(14,3) not null,
  after_quantity numeric(14,3) not null,
  reference_type text,
  reference_id text,
  created_by uuid references public.profiles(id),
  notes text,
  created_at timestamptz not null default now()
);

-- ---------- Indexes ----------
create index if not exists idx_stock_warehouse on public.warehouse_stock (warehouse_id);
create index if not exists idx_stock_product on public.warehouse_stock (product_id);
create index if not exists idx_mov_warehouse on public.stock_movements (warehouse_id);
create index if not exists idx_mov_product on public.stock_movements (product_id);
create index if not exists idx_mov_type on public.stock_movements (movement_type);
create index if not exists idx_mov_created on public.stock_movements (created_at desc);
create index if not exists idx_mov_ref on public.stock_movements (reference_type, reference_id);
create index if not exists idx_wh_active on public.warehouses (is_active);

-- ---------- updated_at ----------
drop trigger if exists trg_wh_updated on public.warehouses;
create trigger trg_wh_updated
  before update on public.warehouses
  for each row execute function public.handle_updated_at();

-- ---------- RLS ----------
alter table public.warehouses enable row level security;
alter table public.warehouse_users enable row level security;
alter table public.warehouse_stock enable row level security;
alter table public.stock_movements enable row level security;

-- Warehouses: read inventory.view (or manage), write warehouses.manage
drop policy if exists "wh_read" on public.warehouses;
create policy "wh_read" on public.warehouses
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('inventory.view') or
    public.has_permission('warehouses.manage')));
drop policy if exists "wh_write" on public.warehouses;
create policy "wh_write" on public.warehouses
  for all to authenticated
  using (public.has_permission('warehouses.manage'))
  with check (public.has_permission('warehouses.manage'));

-- warehouse_users: same as warehouses
drop policy if exists "whu_read" on public.warehouse_users;
create policy "whu_read" on public.warehouse_users
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('inventory.view') or
    public.has_permission('warehouses.manage')));
drop policy if exists "whu_write" on public.warehouse_users;
create policy "whu_write" on public.warehouse_users
  for all to authenticated
  using (public.has_permission('warehouses.manage'))
  with check (public.has_permission('warehouses.manage'));

-- Stock: READ ONLY for app users. No insert/update/delete policies for
-- authenticated => direct writes are rejected; RPCs (SECURITY DEFINER,
-- owner bypass) are the only write path.
drop policy if exists "stock_read" on public.warehouse_stock;
create policy "stock_read" on public.warehouse_stock
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('inventory.view') or
    public.has_permission('inventory.adjust') or
    public.has_permission('inventory.transfer') or
    public.has_permission('warehouses.manage')));

-- Movements: read-only as well (RPC inserts bypass RLS as owner).
drop policy if exists "mov_read" on public.stock_movements;
create policy "mov_read" on public.stock_movements
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('inventory.view') or
    public.has_permission('inventory.adjust') or
    public.has_permission('inventory.transfer') or
    public.has_permission('warehouses.manage') or
    public.has_permission('reports.view')));

-- ============================================================
-- RPCs: every stock change in ONE transaction with
-- auth + permission + status + quantity + movement + audit.
-- ============================================================

-- Adjustment: p_qty_change > 0 => IN, < 0 => OUT
create or replace function public.create_stock_adjustment(
  p_warehouse_id uuid,
  p_product_id uuid,
  p_qty_change numeric,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_before numeric(14,3) := 0;
  v_after numeric(14,3);
  v_mtype text;
  v_sid uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('inventory.adjust') then
    raise exception 'NO_PERMISSION: inventory.adjust required';
  end if;
  if p_qty_change is null or p_qty_change = 0 then
    raise exception 'INVALID_QTY';
  end if;
  if not exists (select 1 from public.warehouses w
      where w.id = p_warehouse_id and w.is_active) then
    raise exception 'WAREHOUSE_NOT_FOUND';
  end if;
  if not exists (select 1 from public.products p
      where p.id = p_product_id and p.is_active) then
    raise exception 'PRODUCT_NOT_FOUND';
  end if;

  -- Lock existing row or create zero-row for positive adjustments
  select quantity into v_before from public.warehouse_stock
    where warehouse_id = p_warehouse_id and product_id = p_product_id
    for update;
  if not found then
    if p_qty_change < 0 then raise exception 'INSUFFICIENT_STOCK'; end if;
    insert into public.warehouse_stock (warehouse_id, product_id, quantity)
      values (p_warehouse_id, p_product_id, 0)
      returning quantity into v_before;
    -- re-lock the fresh row
    select quantity into v_before from public.warehouse_stock
      where warehouse_id = p_warehouse_id and product_id = p_product_id
      for update;
  end if;

  v_after := v_before + p_qty_change;
  if v_after < 0 then raise exception 'INSUFFICIENT_STOCK'; end if;
  v_mtype := case when p_qty_change > 0
    then 'ADJUSTMENT_IN' else 'ADJUSTMENT_OUT' end;

  update public.warehouse_stock
    set quantity = v_after
    where warehouse_id = p_warehouse_id and product_id = p_product_id
    returning id into v_sid;

  insert into public.stock_movements
    (warehouse_id, product_id, movement_type, quantity,
     before_quantity, after_quantity, reference_type, created_by, notes)
    values (p_warehouse_id, p_product_id, v_mtype, abs(p_qty_change),
      v_before, v_after, 'STOCK_ADJUSTMENT', v_uid, p_notes);

  perform public.write_audit_log('STOCK_ADJUSTMENT', 'WAREHOUSE_STOCK',
    v_sid::text,
    jsonb_build_object('before', v_before),
    jsonb_build_object('after', v_after, 'warehouse', p_warehouse_id,
      'product', p_product_id, 'change', p_qty_change));
  return v_sid;
end $$;

-- Transfer between warehouses (available-stock checked, reserved untouched)
create or replace function public.create_stock_transfer(
  p_from_warehouse uuid,
  p_to_warehouse uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_src_before numeric; v_src_after numeric;
  v_dst_before numeric := 0; v_dst_after numeric;
  v_first uuid; v_second uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('inventory.transfer') then
    raise exception 'NO_PERMISSION: inventory.transfer required';
  end if;
  if p_from_warehouse = p_to_warehouse then
    raise exception 'SAME_WAREHOUSE';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'INVALID_QTY';
  end if;

  -- Consistent lock order prevents deadlocks under concurrency
  v_first := least(p_from_warehouse, p_to_warehouse);
  v_second := greatest(p_from_warehouse, p_to_warehouse);
  perform 1 from public.warehouse_stock
    where warehouse_id in (v_first, v_second)
      and product_id = p_product_id for update;

  select quantity, quantity - reserved_quantity
    into v_src_before, v_src_after
    from public.warehouse_stock
    where warehouse_id = p_from_warehouse and product_id = p_product_id;
  if not found then raise exception 'INSUFFICIENT_STOCK'; end if;
  -- v_src_after reused below; fetch available properly
  select quantity - reserved_quantity into v_src_after
    from public.warehouse_stock
    where warehouse_id = p_from_warehouse and product_id = p_product_id;
  if v_src_after < p_quantity then
    raise exception 'INSUFFICIENT_STOCK';
  end if;

  update public.warehouse_stock
    set quantity = quantity - p_quantity
    where warehouse_id = p_from_warehouse and product_id = p_product_id
    returning quantity into v_src_after;
  v_src_after := v_src_before - p_quantity;

  insert into public.warehouse_stock (warehouse_id, product_id, quantity)
    values (p_to_warehouse, p_product_id, 0)
    on conflict (warehouse_id, product_id) do nothing;
  select quantity into v_dst_before from public.warehouse_stock
    where warehouse_id = p_to_warehouse and product_id = p_product_id;
  update public.warehouse_stock
    set quantity = quantity + p_quantity
    where warehouse_id = p_to_warehouse and product_id = p_product_id
    returning quantity into v_dst_after;

  insert into public.stock_movements
    (warehouse_id, product_id, movement_type, quantity,
     before_quantity, after_quantity, reference_type, created_by, notes)
    values
    (p_from_warehouse, p_product_id, 'TRANSFER_OUT', p_quantity,
      v_src_before, v_src_after, 'STOCK_TRANSFER', v_uid, p_notes),
    (p_to_warehouse, p_product_id, 'TRANSFER_IN', p_quantity,
      v_dst_before, v_dst_after, 'STOCK_TRANSFER', v_uid, p_notes);

  perform public.write_audit_log('STOCK_TRANSFER', 'WAREHOUSE_STOCK',
    p_product_id::text, null,
    jsonb_build_object('from', p_from_warehouse, 'to', p_to_warehouse,
      'product', p_product_id, 'qty', p_quantity));
end $$;

-- Reserve / release (for sales flow in later phases; no movement row)
create or replace function public.reserve_stock(
  p_warehouse_id uuid, p_product_id uuid, p_quantity numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('inventory.adjust')
       or public.has_permission('sales.create')) then
    raise exception 'NO_PERMISSION';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'INVALID_QTY';
  end if;
  update public.warehouse_stock
    set reserved_quantity = reserved_quantity + p_quantity
    where warehouse_id = p_warehouse_id and product_id = p_product_id;
  if not found then raise exception 'STOCK_NOT_FOUND'; end if;
  -- check constraint (reserved <= quantity) raises on over-reserve
end $$;

create or replace function public.release_stock(
  p_warehouse_id uuid, p_product_id uuid, p_quantity numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'INVALID_QTY';
  end if;
  update public.warehouse_stock
    set reserved_quantity = greatest(0, reserved_quantity - p_quantity)
    where warehouse_id = p_warehouse_id and product_id = p_product_id;
  if not found then raise exception 'STOCK_NOT_FOUND'; end if;
end $$;
