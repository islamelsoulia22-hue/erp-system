-- ============================================================
-- ERP Migration 0011: company for customers/suppliers +
-- supply category for suppliers (which category they supply)
-- ============================================================

alter table public.customers
  add column if not exists company text;

alter table public.suppliers
  add column if not exists company text;

alter table public.suppliers
  add column if not exists supply_category_id uuid
    references public.product_categories(id) on delete set null;

create index if not exists idx_suppliers_supply_cat
  on public.suppliers (supply_category_id);
