-- ============================================================
-- ERP Migration 0010: Returns + Attachments + Report views
-- Sales return: stock UP (SALES_RETURN), reduces customer outstanding.
-- Purchase return: stock DOWN (PURCHASE_RETURN), reduces supplier payable.
-- ============================================================

create sequence if not exists sales_return_seq start 1;
create sequence if not exists purchase_return_seq start 1;

create or replace function public.generate_sales_return_number()
returns text language plpgsql as $$
declare n bigint; y text;
begin
  n := nextval('sales_return_seq');
  y := to_char(now(), 'YYYY');
  return 'RET-SAL-' || y || '-' || lpad(n::text, 6, '0');
end $$;

create or replace function public.generate_purchase_return_number()
returns text language plpgsql as $$
declare n bigint; y text;
begin
  n := nextval('purchase_return_seq');
  y := to_char(now(), 'YYYY');
  return 'RET-PUR-' || y || '-' || lpad(n::text, 6, '0');
end $$;

-- ---------- Sales returns ----------
create table if not exists public.sales_returns (
  id uuid primary key default gen_random_uuid(),
  return_number text not null unique
    default public.generate_sales_return_number(),
  sales_invoice_id uuid references public.sales_invoices(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  warehouse_id uuid references public.warehouses(id) on delete restrict,
  status text not null default 'DRAFT'
    check (status in ('DRAFT','COMPLETED','CANCELLED')),
  subtotal numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  reason text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sales_return_items (
  id uuid primary key default gen_random_uuid(),
  sales_return_id uuid not null references public.sales_returns(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  item_name text not null,
  sku text,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  tax_rate numeric(5,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0
);

-- ---------- Purchase returns ----------
create table if not exists public.purchase_returns (
  id uuid primary key default gen_random_uuid(),
  return_number text not null unique
    default public.generate_purchase_return_number(),
  purchase_invoice_id uuid references public.purchase_invoices(id) on delete set null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  warehouse_id uuid references public.warehouses(id) on delete restrict,
  status text not null default 'DRAFT'
    check (status in ('DRAFT','COMPLETED','CANCELLED')),
  subtotal numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  reason text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.purchase_return_items (
  id uuid primary key default gen_random_uuid(),
  purchase_return_id uuid not null references public.purchase_returns(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  sku text,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  tax_rate numeric(5,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0
);

create index if not exists idx_sr_number on public.sales_returns (return_number);
create index if not exists idx_sr_invoice on public.sales_returns (sales_invoice_id);
create index if not exists idx_sr_customer on public.sales_returns (customer_id);
create index if not exists idx_sri_ret on public.sales_return_items (sales_return_id);
create index if not exists idx_prt_number on public.purchase_returns (return_number);
create index if not exists idx_prt_invoice on public.purchase_returns (purchase_invoice_id);
create index if not exists idx_prt_supplier on public.purchase_returns (supplier_id);
create index if not exists idx_prti_ret on public.purchase_return_items (purchase_return_id);

drop trigger if exists trg_sr_updated on public.sales_returns;
create trigger trg_sr_updated before update on public.sales_returns
  for each row execute function public.handle_updated_at();
drop trigger if exists trg_prt_updated on public.purchase_returns;
create trigger trg_prt_updated before update on public.purchase_returns
  for each row execute function public.handle_updated_at();

-- ---------- Attachments registry ----------
create table if not exists public.attachments (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id text not null,
  file_name text not null,
  file_path text not null,
  file_type text,
  file_size bigint,
  uploaded_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_att_entity
  on public.attachments (entity_type, entity_id);

-- Storage bucket (private)
insert into storage.buckets (id, name, public)
  values ('attachments', 'attachments', false)
  on conflict (id) do nothing;

-- ---------- RLS ----------
alter table public.sales_returns enable row level security;
alter table public.sales_return_items enable row level security;
alter table public.purchase_returns enable row level security;
alter table public.purchase_return_items enable row level security;
alter table public.attachments enable row level security;

drop policy if exists "sr_read" on public.sales_returns;
create policy "sr_read" on public.sales_returns
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('sales.view') or public.has_permission('sales.create')
    or public.has_permission('sales.edit')));
drop policy if exists "sr_write" on public.sales_returns;
create policy "sr_write" on public.sales_returns
  for all to authenticated
  using (public.has_permission('sales.create') or public.has_permission('sales.edit'))
  with check (public.has_permission('sales.create') or public.has_permission('sales.edit'));

drop policy if exists "sri_rw" on public.sales_return_items;
create policy "sri_rw" on public.sales_return_items
  for all to authenticated
  using (public.has_permission('sales.create') or public.has_permission('sales.edit')
    or public.has_permission('sales.view'))
  with check (public.has_permission('sales.create') or public.has_permission('sales.edit'));

drop policy if exists "prt_read" on public.purchase_returns;
create policy "prt_read" on public.purchase_returns
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('purchases.view') or public.has_permission('purchases.create')
    or public.has_permission('purchases.edit')));
drop policy if exists "prt_write" on public.purchase_returns;
create policy "prt_write" on public.purchase_returns
  for all to authenticated
  using (public.has_permission('purchases.create') or public.has_permission('purchases.edit'))
  with check (public.has_permission('purchases.create') or public.has_permission('purchases.edit'));

drop policy if exists "prti_rw" on public.purchase_return_items;
create policy "prti_rw" on public.purchase_return_items
  for all to authenticated
  using (public.has_permission('purchases.create') or public.has_permission('purchases.edit')
    or public.has_permission('purchases.view'))
  with check (public.has_permission('purchases.create') or public.has_permission('purchases.edit'));

drop policy if exists "att_read" on public.attachments;
create policy "att_read" on public.attachments
  for select to authenticated using (public.is_active_user());
drop policy if exists "att_write" on public.attachments;
create policy "att_write" on public.attachments
  for all to authenticated
  using (public.is_active_user())
  with check (public.is_active_user());

-- Storage objects: active users manage their bucket paths
drop policy if exists "att_storage_read" on storage.objects;
create policy "att_storage_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'attachments' and public.is_active_user());
drop policy if exists "att_storage_write" on storage.objects;
create policy "att_storage_write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'attachments' and public.is_active_user());
drop policy if exists "att_storage_delete" on storage.objects;
create policy "att_storage_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'attachments' and public.is_active_user());

-- ---------- Low-stock view (reports) ----------
create or replace view public.low_stock_products as
select
  ws.warehouse_id, w.name as warehouse_name,
  ws.product_id, p.name as product_name, p.sku,
  p.minimum_stock,
  ws.quantity, ws.reserved_quantity, ws.available_quantity
from public.warehouse_stock ws
join public.products p on p.id = ws.product_id
join public.warehouses w on w.id = ws.warehouse_id
where p.track_inventory = true
  and p.is_active = true
  and ws.available_quantity <= p.minimum_stock;

-- ---------- Balances now subtract completed returns ----------
create or replace function public.customer_balance(p_customer uuid)
returns table (total numeric, paid numeric, outstanding numeric)
language sql stable security definer set search_path = public as $$
  with inv as (
    select coalesce(sum(grand_total),0) as t
    from public.sales_invoices
    where customer_id = p_customer
      and status in ('APPROVED','PENDING_APPROVAL')),
  pay as (
    select coalesce(sum(amount),0) as p
    from public.payments
    where customer_id = p_customer and status='COMPLETED'),
  ret as (
    select coalesce(sum(grand_total),0) as r
    from public.sales_returns
    where customer_id = p_customer and status='COMPLETED')
  select (select t from inv),
         (select p from pay),
         (select t from inv) - (select p from pay)
         - (select r from ret);
$$;

create or replace function public.supplier_balance(p_supplier uuid)
returns table (total numeric, paid numeric, outstanding numeric)
language sql stable security definer set search_path = public as $$
  with inv as (
    select coalesce(sum(grand_total),0) as t
    from public.purchase_invoices
    where supplier_id = p_supplier
      and status in ('APPROVED','PENDING_APPROVAL')),
  pay as (
    select coalesce(sum(amount),0) as p
    from public.payments
    where supplier_id = p_supplier and status='COMPLETED'),
  ret as (
    select coalesce(sum(grand_total),0) as r
    from public.purchase_returns
    where supplier_id = p_supplier and status='COMPLETED')
  select (select t from inv),
         (select p from pay),
         (select t from inv) - (select p from pay)
         - (select r from ret);
$$;

-- ============================================================
-- RPCs
-- ============================================================
create or replace function public.complete_sales_return(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); r record; it record;
  v_before numeric(14,3); v_after numeric(14,3);
  v_sub numeric(14,2) := 0; v_tax numeric(14,2) := 0;
  inv_qty numeric;
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

  for it in select * from public.sales_return_items
    where sales_return_id = p_id for update loop
    -- Cap by invoiced qty minus previously completed returns
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

create or replace function public.complete_purchase_return(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); r record; it record;
  v_before numeric(14,3); v_after numeric(14,3);
  v_sub numeric(14,2) := 0; v_tax numeric(14,2) := 0;
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
