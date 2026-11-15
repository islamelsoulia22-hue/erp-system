-- ============================================================
-- ERP Migration 0003: Customers + Suppliers + Addresses
-- default_payment_method_id left as uuid (FK added in payments phase)
-- ============================================================

-- Sequences for auto codes (concurrency-safe)
create sequence if not exists customer_code_seq start 1;
create sequence if not exists supplier_code_seq start 1;

create or replace function public.generate_customer_code()
returns text language plpgsql as $$
declare n bigint;
begin
  n := nextval('customer_code_seq');
  return 'CUST-' || lpad(n::text, 6, '0');
end $$;

create or replace function public.generate_supplier_code()
returns text language plpgsql as $$
declare n bigint;
begin
  n := nextval('supplier_code_seq');
  return 'SUP-' || lpad(n::text, 6, '0');
end $$;

-- ---------- Customers ----------
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  customer_code text not null unique default public.generate_customer_code(),
  name text not null,
  phone text,
  email text,
  tax_number text,
  credit_limit numeric(14,2) not null default 0,
  default_payment_method_id uuid,
  is_active boolean not null default true,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chk_cust_credit check (credit_limit >= 0)
);

-- ---------- Customer addresses ----------
create table if not exists public.customer_addresses (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  label text,
  address_line text,
  governorate text,
  city text,
  area text,
  latitude double precision,
  longitude double precision,
  phone text,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One default address per customer
create unique index if not exists uq_customer_default_addr
  on public.customer_addresses (customer_id) where is_default = true;

-- ---------- Suppliers ----------
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  supplier_code text not null unique default public.generate_supplier_code(),
  name text not null,
  phone text,
  email text,
  tax_number text,
  address text,
  credit_limit numeric(14,2) not null default 0,
  default_payment_method_id uuid,
  is_active boolean not null default true,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chk_sup_credit check (credit_limit >= 0)
);

-- ---------- Indexes ----------
create index if not exists idx_customers_name on public.customers (lower(name));
create index if not exists idx_customers_phone on public.customers (phone);
create index if not exists idx_customers_active on public.customers (is_active);
create index if not exists idx_customers_created on public.customers (created_at desc);
create index if not exists idx_cust_addr_customer on public.customer_addresses (customer_id);
create index if not exists idx_suppliers_name on public.suppliers (lower(name));
create index if not exists idx_suppliers_phone on public.suppliers (phone);
create index if not exists idx_suppliers_active on public.suppliers (is_active);
create index if not exists idx_suppliers_created on public.suppliers (created_at desc);

-- ---------- updated_at ----------
drop trigger if exists trg_customers_updated on public.customers;
create trigger trg_customers_updated
  before update on public.customers
  for each row execute function public.handle_updated_at();

drop trigger if exists trg_cust_addr_updated on public.customer_addresses;
create trigger trg_cust_addr_updated
  before update on public.customer_addresses
  for each row execute function public.handle_updated_at();

drop trigger if exists trg_suppliers_updated on public.suppliers;
create trigger trg_suppliers_updated
  before update on public.suppliers
  for each row execute function public.handle_updated_at();

-- ---------- RLS ----------
alter table public.customers enable row level security;
alter table public.customer_addresses enable row level security;
alter table public.suppliers enable row level security;

-- Customers
drop policy if exists "cust_read" on public.customers;
create policy "cust_read" on public.customers
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('customers.view') or
    public.has_permission('customers.create') or
    public.has_permission('customers.edit')));
drop policy if exists "cust_insert" on public.customers;
create policy "cust_insert" on public.customers
  for insert to authenticated
  with check (public.has_permission('customers.create'));
drop policy if exists "cust_update" on public.customers;
create policy "cust_update" on public.customers
  for update to authenticated
  using (public.has_permission('customers.edit'))
  with check (public.has_permission('customers.edit'));
drop policy if exists "cust_delete" on public.customers;
create policy "cust_delete" on public.customers
  for delete to authenticated
  using (public.has_permission('customers.create'));

-- Addresses follow customer permissions
drop policy if exists "caddr_read" on public.customer_addresses;
create policy "caddr_read" on public.customer_addresses
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('customers.view') or
    public.has_permission('customers.create') or
    public.has_permission('customers.edit')));
drop policy if exists "caddr_insert" on public.customer_addresses;
create policy "caddr_insert" on public.customer_addresses
  for insert to authenticated
  with check (public.has_permission('customers.create') or
              public.has_permission('customers.edit'));
drop policy if exists "caddr_update" on public.customer_addresses;
create policy "caddr_update" on public.customer_addresses
  for update to authenticated
  using (public.has_permission('customers.edit'))
  with check (public.has_permission('customers.edit'));
drop policy if exists "caddr_delete" on public.customer_addresses;
create policy "caddr_delete" on public.customer_addresses
  for delete to authenticated
  using (public.has_permission('customers.create') or
         public.has_permission('customers.edit'));

-- Suppliers
drop policy if exists "sup_read" on public.suppliers;
create policy "sup_read" on public.suppliers
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('suppliers.view') or
    public.has_permission('suppliers.create') or
    public.has_permission('suppliers.edit')));
drop policy if exists "sup_insert" on public.suppliers;
create policy "sup_insert" on public.suppliers
  for insert to authenticated
  with check (public.has_permission('suppliers.create'));
drop policy if exists "sup_update" on public.suppliers;
create policy "sup_update" on public.suppliers
  for update to authenticated
  using (public.has_permission('suppliers.edit'))
  with check (public.has_permission('suppliers.edit'));
drop policy if exists "sup_delete" on public.suppliers;
create policy "sup_delete" on public.suppliers
  for delete to authenticated
  using (public.has_permission('suppliers.create'));
