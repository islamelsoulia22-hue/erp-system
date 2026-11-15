-- ============================================================
-- ERP Migration 0018: Custom sales items -> manufacturing
-- ============================================================
-- 1) مواصفات الصنف الخاص على سطور فواتير المبيعات.
-- 2) ربط الصنف المخصص (customized_items) بفاتورة وسطر البيع
--    + وحدات المقاس + Qty/Roll + اسم منشئ الطلب.
--
-- طريقة التطبيق: نفّذ الملف ده في Supabase Dashboard > SQL Editor
-- قبل تشغيل نسخة التطبيق اللي فيها "إضافة صنف خاص".

-- ---------- 1) مواصفات الصنف الخاص على سطور البيع ----------
alter table public.sales_invoice_items
  add column if not exists item_type text not null default 'STANDARD'
    check (item_type in ('STANDARD','CUSTOMIZED','MANUFACTURED'));

alter table public.sales_invoice_items
  add column if not exists custom_unit text;

alter table public.sales_invoice_items
  add column if not exists length_value numeric(10,2);

alter table public.sales_invoice_items
  add column if not exists length_unit text;

alter table public.sales_invoice_items
  add column if not exists width_value numeric(10,2);

alter table public.sales_invoice_items
  add column if not exists width_unit text;

alter table public.sales_invoice_items
  add column if not exists raw_material_id uuid
    references public.products(id) on delete set null;

alter table public.sales_invoice_items
  add column if not exists raw_material_name text;

alter table public.sales_invoice_items
  add column if not exists qty_per_roll numeric(14,3);

alter table public.sales_invoice_items
  add column if not exists custom_notes text;

alter table public.sales_invoice_items
  add column if not exists customized_item_id uuid
    references public.customized_items(id) on delete set null;

create index if not exists idx_sii_customized_item
  on public.sales_invoice_items (customized_item_id);

-- ---------- 2) ربط المخصص بالفاتورة + حقول العرض ----------
alter table public.customized_items
  add column if not exists sales_invoice_id uuid
    references public.sales_invoices(id) on delete set null;

alter table public.customized_items
  add column if not exists sales_invoice_item_id uuid
    references public.sales_invoice_items(id) on delete set null;

alter table public.customized_items
  add column if not exists length_unit text;

alter table public.customized_items
  add column if not exists width_unit text;

alter table public.customized_items
  add column if not exists qty_per_roll numeric(14,3);

alter table public.customized_items
  add column if not exists raw_material_id uuid
    references public.products(id) on delete set null;

alter table public.customized_items
  add column if not exists created_by_name text;

create index if not exists idx_cz_invoice
  on public.customized_items (sales_invoice_id);
