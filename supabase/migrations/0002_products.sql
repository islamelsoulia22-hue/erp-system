-- ============================================================
-- ERP Migration 0002: Products (categories, units, products, barcodes)
-- ============================================================

-- ---------- App settings (tax config, no hard-coded VAT in app) ----------
create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

-- ---------- Categories ----------
create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  name_ar text,
  description text,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Units ----------
create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  name_ar text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- Products ----------
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  name text not null,
  description text,
  category_id uuid references public.product_categories(id) on delete set null,
  unit_id uuid references public.units(id) on delete set null,
  purchase_price numeric(14,2) not null default 0,
  sale_price numeric(14,2) not null default 0,
  taxable boolean not null default true,
  tax_rate numeric(5,2) not null default 14,
  minimum_stock numeric(14,3) not null default 0,
  track_inventory boolean not null default true,
  is_customizable boolean not null default false,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chk_prices_nonneg
    check (purchase_price >= 0 and sale_price >= 0 and minimum_stock >= 0),
  constraint chk_tax_rate check (tax_rate >= 0 and tax_rate <= 100)
);

-- ---------- Barcodes (optional, multiple per product, globally unique) ----------
create table if not exists public.product_barcodes (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  barcode text not null unique,
  barcode_type text not null default 'EAN13',
  is_primary boolean not null default false,
  created_at timestamptz not null default now()
);

-- One primary barcode per product (partial unique index)
create unique index if not exists uq_barcodes_primary_per_product
  on public.product_barcodes (product_id) where is_primary = true;

-- ---------- Indexes (search + barcode speed) ----------
create index if not exists idx_products_name_lower
  on public.products (lower(name));
create index if not exists idx_products_sku on public.products (sku);
create index if not exists idx_products_category on public.products (category_id);
create index if not exists idx_products_active on public.products (is_active);
create index if not exists idx_products_created on public.products (created_at desc);
create index if not exists idx_barcodes_product on public.product_barcodes (product_id);
create index if not exists idx_barcodes_code on public.product_barcodes (barcode);
create index if not exists idx_categories_active
  on public.product_categories (is_active);

-- ---------- updated_at triggers ----------
drop trigger if exists trg_categories_updated on public.product_categories;
create trigger trg_categories_updated
  before update on public.product_categories
  for each row execute function public.handle_updated_at();

drop trigger if exists trg_products_updated on public.products;
create trigger trg_products_updated
  before update on public.products
  for each row execute function public.handle_updated_at();

drop trigger if exists trg_settings_updated on public.app_settings;
create trigger trg_settings_updated
  before update on public.app_settings
  for each row execute function public.handle_updated_at();

-- ---------- RLS ----------
alter table public.product_categories enable row level security;
alter table public.units enable row level security;
alter table public.products enable row level security;
alter table public.product_barcodes enable row level security;
alter table public.app_settings enable row level security;

-- Helper predicate inlined: readable with products.view (or create/edit),
-- writable only with create/edit. Managers have all permissions via seed.

-- Categories
drop policy if exists "cat_read" on public.product_categories;
create policy "cat_read" on public.product_categories
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('products.view') or
    public.has_permission('products.create') or
    public.has_permission('products.edit')));
drop policy if exists "cat_insert" on public.product_categories;
create policy "cat_insert" on public.product_categories
  for insert to authenticated
  with check (public.has_permission('products.create'));
drop policy if exists "cat_update" on public.product_categories;
create policy "cat_update" on public.product_categories
  for update to authenticated
  using (public.has_permission('products.edit'))
  with check (public.has_permission('products.edit'));
drop policy if exists "cat_delete" on public.product_categories;
create policy "cat_delete" on public.product_categories
  for delete to authenticated
  using (public.has_permission('products.create'));

-- Units (same as categories, read for all active viewers)
drop policy if exists "units_read" on public.units;
create policy "units_read" on public.units
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('products.view') or
    public.has_permission('products.create') or
    public.has_permission('products.edit')));
drop policy if exists "units_insert" on public.units;
create policy "units_insert" on public.units
  for insert to authenticated
  with check (public.has_permission('products.create'));
drop policy if exists "units_update" on public.units;
create policy "units_update" on public.units
  for update to authenticated
  using (public.has_permission('products.edit'))
  with check (public.has_permission('products.edit'));
drop policy if exists "units_delete" on public.units;
create policy "units_delete" on public.units
  for delete to authenticated
  using (public.has_permission('products.create'));

-- Products
drop policy if exists "products_read" on public.products;
create policy "products_read" on public.products
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('products.view') or
    public.has_permission('products.create') or
    public.has_permission('products.edit')));
drop policy if exists "products_insert" on public.products;
create policy "products_insert" on public.products
  for insert to authenticated
  with check (public.has_permission('products.create'));
drop policy if exists "products_update" on public.products;
create policy "products_update" on public.products
  for update to authenticated
  using (public.has_permission('products.edit'))
  with check (public.has_permission('products.edit'));
drop policy if exists "products_delete" on public.products;
create policy "products_delete" on public.products
  for delete to authenticated
  using (public.has_permission('products.create'));

-- Barcodes
drop policy if exists "barcodes_read" on public.product_barcodes;
create policy "barcodes_read" on public.product_barcodes
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('products.view') or
    public.has_permission('products.create') or
    public.has_permission('products.edit')));
drop policy if exists "barcodes_insert" on public.product_barcodes;
create policy "barcodes_insert" on public.product_barcodes
  for insert to authenticated
  with check (public.has_permission('products.create') or
              public.has_permission('products.edit'));
drop policy if exists "barcodes_update" on public.product_barcodes;
create policy "barcodes_update" on public.product_barcodes
  for update to authenticated
  using (public.has_permission('products.edit'))
  with check (public.has_permission('products.edit'));
drop policy if exists "barcodes_delete" on public.product_barcodes;
create policy "barcodes_delete" on public.product_barcodes
  for delete to authenticated
  using (public.has_permission('products.create'));

-- Settings: read all active, write managers only
drop policy if exists "settings_read" on public.app_settings;
create policy "settings_read" on public.app_settings
  for select to authenticated using (public.is_active_user());
drop policy if exists "settings_write" on public.app_settings;
create policy "settings_write" on public.app_settings
  for all to authenticated
  using (public.has_permission('users.manage'))
  with check (public.has_permission('users.manage'));

-- ---------- Seed ----------
insert into public.units (code, name, name_ar) values
  ('PCS', 'Piece', 'قطعة'),
  ('KG', 'Kilogram', 'كيلو'),
  ('M', 'Meter', 'متر'),
  ('L', 'Liter', 'لتر'),
  ('BOX', 'Box', 'علبة'),
  ('PACK', 'Pack', 'باكت')
on conflict (code) do nothing;

insert into public.product_categories (code, name, name_ar) values
  ('GEN', 'General', 'عام'),
  ('RAW', 'Raw materials', 'خامات'),
  ('FIN', 'Finished goods', 'منتجات تامة'),
  ('CUS', 'Custom', 'مخصص')
on conflict (code) do nothing;

insert into public.app_settings (key, value) values
  ('tax', '{"default_rate": 14, "currency": "EGP"}')
on conflict (key) do nothing;
