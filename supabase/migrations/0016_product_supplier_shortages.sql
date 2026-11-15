-- ============================================================
-- ERP Migration 0016: Product supplier + shortages (النواقص)
-- ============================================================
-- 1) ربط كل صنف بالمورد الأساسي اللي بنجيب منه الصنف.
-- 2) جدول النواقص: طلبات تلقائية بتتسجل عند إنشاء فاتورة بيع
--    لو الكمية المطلوبة مش متاحة أو هتنزل تحت الحد الأدنى.
--
-- طريقة التطبيق: نفّذ الملف ده في Supabase Dashboard > SQL Editor
-- قبل تشغيل نسخة التطبيق اللي فيها قسم النواقص.

-- ---------- 1) مورد الصنف ----------
alter table public.products
  add column if not exists supplier_id uuid
  references public.suppliers(id) on delete set null;

create index if not exists idx_products_supplier
  on public.products (supplier_id);

-- ---------- 2) جدول النواقص ----------
create table if not exists public.shortages (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete set null,
  warehouse_id uuid references public.warehouses(id) on delete set null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  required_qty numeric(14,3) not null default 0
    check (required_qty >= 0),
  status text not null default 'PENDING'
    check (status in ('PENDING','ORDERED','DONE','CANCELLED')),
  source_type text,
  source_id text,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_shortages_status
  on public.shortages (status);
create index if not exists idx_shortages_product
  on public.shortages (product_id);
create index if not exists idx_shortages_warehouse
  on public.shortages (warehouse_id);
create index if not exists idx_shortages_created
  on public.shortages (created_at desc);
create index if not exists idx_shortages_pending_pw
  on public.shortages (product_id, warehouse_id)
  where status = 'PENDING';

drop trigger if exists trg_shortages_updated on public.shortages;
create trigger trg_shortages_updated
  before update on public.shortages
  for each row execute function public.handle_updated_at();

-- ---------- 3) RLS ----------
alter table public.shortages enable row level security;

-- قراءة: المشتريات + المبيعات (اللي أنشأ الفاتورة) + المخزون.
drop policy if exists "sh_read" on public.shortages;
create policy "sh_read" on public.shortages
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('purchases.view')
    or public.has_permission('purchases.create')
    or public.has_permission('purchases.edit')
    or public.has_permission('sales.create')
    or public.has_permission('inventory.view')));

-- إنشاء: اللي يقدر يعمل فاتورة بيع (الطلب التلقائي) أو طلب شراء.
drop policy if exists "sh_insert" on public.shortages;
create policy "sh_insert" on public.shortages
  for insert to authenticated
  with check (public.has_permission('sales.create')
    or public.has_permission('purchases.create'));

-- تعديل الحالة: فريق المشتريات.
drop policy if exists "sh_update" on public.shortages;
create policy "sh_update" on public.shortages
  for update to authenticated
  using (public.has_permission('purchases.create')
    or public.has_permission('purchases.edit'))
  with check (public.has_permission('purchases.create')
    or public.has_permission('purchases.edit'));
