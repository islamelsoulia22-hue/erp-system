-- ============================================================================
-- ⚠️  RESET SALES + PURCHASES ONLY — DESTRUCTIVE, NO UNDO
-- ============================================================================
-- التشغيل: انسخ محتوى هذا الملف والصقه في Supabase Dashboard → SQL Editor
-- ثم اضغط Run (يعمل بصلاحيات postgres فيتجاوز RLS).
--
-- ممنوع منعاً باتاً نقل هذا الملف إلى مجلد migrations/.
--
-- ما يُمسح: فواتير المبيعات + أصنافها، طلبات المبيعات + أصنافها،
-- فواتير المشتريات + أصنافها، طلبات المشتريات + أصنافها،
-- ومرفقات الفواتير (سجلات + ملفات).
--
-- ما يُحفظ: كل شيء آخر (العملاء/الموردون/المنتجات/المخازن/المخزون/
-- المستخدمون/الأدوار/طرق الدفع).
--
-- ملاحظة: المدفوعات والشحنات والمرتجعات المرتبطة بالفواتير الممسوحة
-- تبقى كسجلات لكن رابط الفاتورة فيها يصبح null (SET NULL تلقائي).
-- المخزون المحجوز من فواتير معتمدة ممسوحة يبقى محجوزاً — أخبرني لو
-- تريد تحريره أيضاً.
--
-- العدّادات تُصفَّر: SAL-… و PUR-… و SO-… و PO-… ترجع من 000001.
-- ============================================================================

BEGIN;

-- ---------- 1) ملفات مرفقات فواتير المبيعات والمشتريات من الـ Storage ----------
DELETE FROM storage.objects o
USING public.attachments a
WHERE a.entity_type IN ('SALES_INVOICE', 'PURCHASE_INVOICE')
  AND o.bucket_id = 'attachments'
  AND o.name = a.file_path;

-- ---------- 2) سجلات المرفقات ----------
DELETE FROM public.attachments
WHERE entity_type IN ('SALES_INVOICE', 'PURCHASE_INVOICE');

-- ---------- 3) المبيعات: الأصناف ثم الفواتير ثم أصناف الطلبات ثم الطلبات ----------
DELETE FROM public.sales_invoice_items;
DELETE FROM public.sales_invoices;
DELETE FROM public.sales_order_items;
DELETE FROM public.sales_orders;

-- ---------- 4) المشتريات: بنفس الترتيب ----------
DELETE FROM public.purchase_invoice_items;
DELETE FROM public.purchase_invoices;
DELETE FROM public.purchase_order_items;
DELETE FROM public.purchase_orders;

-- ---------- 5) تصفير عدّادات الترقيم ----------
ALTER SEQUENCE public.sales_invoice_seq RESTART WITH 1;
ALTER SEQUENCE public.sales_order_seq RESTART WITH 1;
ALTER SEQUENCE public.purchase_invoice_seq RESTART WITH 1;
ALTER SEQUENCE public.purchase_order_seq RESTART WITH 1;

COMMIT;

-- ---------- 6) تحقق: يجب أن تكون كلها أصفار ----------
SELECT 'sales_invoices' AS tbl, count(*) AS rows FROM public.sales_invoices
UNION ALL SELECT 'sales_invoice_items', count(*) FROM public.sales_invoice_items
UNION ALL SELECT 'sales_orders', count(*) FROM public.sales_orders
UNION ALL SELECT 'sales_order_items', count(*) FROM public.sales_order_items
UNION ALL SELECT 'purchase_invoices', count(*) FROM public.purchase_invoices
UNION ALL SELECT 'purchase_invoice_items', count(*) FROM public.purchase_invoice_items
UNION ALL SELECT 'purchase_orders', count(*) FROM public.purchase_orders
UNION ALL SELECT 'purchase_order_items', count(*) FROM public.purchase_order_items
UNION ALL SELECT 'products (kept)', count(*) FROM public.products
UNION ALL SELECT 'customers (kept)', count(*) FROM public.customers
UNION ALL SELECT 'suppliers (kept)', count(*) FROM public.suppliers;
