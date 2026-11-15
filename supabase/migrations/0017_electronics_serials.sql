-- ============================================================
-- ERP Migration 0017: Electronics devices (brand/model/serials)
-- ============================================================
-- 1) فئة "إلكترونيات" الأساسية (كود ELEC).
-- 2) أعمدة وصف الجهاز على products (نوع/ماركة/موديل).
-- 3) جدول السيريالات: سيريال لكل جهاز حسب الكمية.
--
-- طريقة التطبيق: نفّذ الملف ده في Supabase Dashboard > SQL Editor
-- قبل تشغيل نسخة التطبيق اللي فيها حقول الإلكترونيات.

-- ---------- 1) فئة إلكترونيات ----------
insert into public.product_categories (code, name, name_ar)
values ('ELEC', 'Electronics', 'إلكترونيات')
on conflict (code) do nothing;

-- ---------- 2) أعمدة الجهاز ----------
alter table public.products
  add column if not exists device_type text
  check (device_type is null or device_type in
    ('RECEIPT','BARCODE_PRINTER','BARCODE_SCANNER','HANDHELD'));

alter table public.products
  add column if not exists brand text;

alter table public.products
  add column if not exists model text;

-- ---------- 3) جدول السيريالات ----------
create table if not exists public.product_serials (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null
    references public.products(id) on delete cascade,
  serial text not null,
  created_at timestamptz not null default now(),
  unique (product_id, serial)
);

create index if not exists idx_serials_product
  on public.product_serials (product_id);

alter table public.product_serials enable row level security;

-- قراءة: نفس صلاحيات رؤية الأصناف.
drop policy if exists "serials_read" on public.product_serials;
create policy "serials_read" on public.product_serials
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('products.view') or
    public.has_permission('products.create') or
    public.has_permission('products.edit')));

-- كتابة: إنشاء/تعديل الأصناف.
drop policy if exists "serials_write" on public.product_serials;
create policy "serials_write" on public.product_serials
  for all to authenticated
  using (public.has_permission('products.create') or
         public.has_permission('products.edit'))
  with check (public.has_permission('products.create') or
              public.has_permission('products.edit'));
