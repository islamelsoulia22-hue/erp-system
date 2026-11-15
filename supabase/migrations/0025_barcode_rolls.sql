-- ============================================================
-- ERP Migration 0025: Barcode sticker rolls (بكر الباركود)
-- 1) فئة محمية غير قابلة للمسح: BARCODE_ROLL
-- 2) جدول خامات الباركود بسعر شراء/بيع ثابت لكل خامة
-- 3) أعمدة البكرة على products (الخامة + المقاس + العدد)
-- ============================================================

-- ---------- 0) عمود حماية الفئات النظامية ----------
alter table public.product_categories
  add column if not exists is_system boolean not null default false;

-- ---------- 1) فئة بكر الباركود (محمية) ----------
insert into public.product_categories (code, name, name_ar, is_active, is_system)
values ('BARCODE_ROLL', 'Barcode Sticker Roll', 'بكر الباركود', true, true)
on conflict (code) do update
  set name_ar = excluded.name_ar,
      is_active = true,
      is_system = true;

-- منع مسح/إيقاف الفئات النظامية على مستوى الداتا بيز.
create or replace function public.prevent_system_category_change()
returns trigger
language plpgsql
as $$
begin
  if old.is_system = true or old.code = 'BARCODE_ROLL' then
    if tg_op = 'DELETE' then
      raise exception 'SYSTEM_CATEGORY: لا يمكن مسح فئة بكر الباركود المحمية';
    end if;
    if tg_op = 'UPDATE' and new.is_active = false then
      raise exception 'SYSTEM_CATEGORY: لا يمكن إيقاف فئة بكر الباركود المحمية';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_protect_system_category on public.product_categories;
create trigger trg_protect_system_category
  before update or delete on public.product_categories
  for each row execute function public.prevent_system_category_change();

-- ---------- 2) جدول خامات الباركود ----------
create table if not exists public.barcode_materials (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_ar text,
  purchase_price numeric(14,6) not null default 0,
  sale_price numeric(14,6) not null default 0,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chk_material_prices_nonneg
    check (purchase_price >= 0 and sale_price >= 0),
  constraint uq_material_name unique (name)
);

create index if not exists idx_materials_active
  on public.barcode_materials (is_active);

drop trigger if exists trg_materials_updated on public.barcode_materials;
create trigger trg_materials_updated
  before update on public.barcode_materials
  for each row execute function public.handle_updated_at();

alter table public.barcode_materials enable row level security;

drop policy if exists "bmat_read" on public.barcode_materials;
create policy "bmat_read" on public.barcode_materials
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('products.view') or
    public.has_permission('products.create') or
    public.has_permission('products.edit')));
drop policy if exists "bmat_insert" on public.barcode_materials;
create policy "bmat_insert" on public.barcode_materials
  for insert to authenticated
  with check (public.has_permission('products.create'));
drop policy if exists "bmat_update" on public.barcode_materials;
create policy "bmat_update" on public.barcode_materials
  for update to authenticated
  using (public.has_permission('products.edit'))
  with check (public.has_permission('products.edit'));
drop policy if exists "bmat_delete" on public.barcode_materials;
create policy "bmat_delete" on public.barcode_materials
  for delete to authenticated
  using (public.has_permission('products.create'));

-- ---------- 3) الخامات الستة الافتراضية ----------
insert into public.barcode_materials (name, name_ar, purchase_price, sale_price) values
  ('semi-gloss', 'نص لميع', 0, 0),
  ('white-plastic', 'بلاستك ابيض', 0, 0),
  ('thermal', 'حراري', 0, 0),
  ('thermal-fridge', 'حراري ثلاجة', 0, 0),
  ('thermal-plastic', 'بلاستك حراري', 0, 0),
  ('silver-plastic', 'بلاستك سيلفر', 0, 0)
on conflict (name) do nothing;

-- ---------- 4) أعمدة البكرة على products ----------
alter table public.products
  add column if not exists barcode_material_id uuid
    references public.barcode_materials(id) on delete set null;
alter table public.products
  add column if not exists label_length_mm numeric(10,2);
alter table public.products
  add column if not exists label_width_mm numeric(10,2);
alter table public.products
  add column if not exists qty_per_roll numeric(14,0);

create index if not exists idx_products_material
  on public.products (barcode_material_id);
