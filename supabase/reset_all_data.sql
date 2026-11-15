-- ============================================================================
-- ⚠️  RESET ALL BUSINESS DATA — DESTRUCTIVE, NO UNDO
-- ============================================================================
-- التشغيل: انسخ محتوى هذا الملف والصقه في Supabase Dashboard → SQL Editor
-- ثم اضغط Run (يعمل بصلاحيات postgres فيتجاوز RLS).
--
-- ممنوع منعاً باتاً نقل هذا الملف إلى مجلد migrations/ — سيؤدي لمسح
-- البيانات تلقائياً عند أي db push/reset.
--
-- ما يُمسح: كل الحركات (فواتير/طلبات/مدفوعات/شحنات/مرتجعات/مشتريات/
-- تصنيع/مخزون/مرفقات/موافقات/سجلات/إشعارات/مصروفات/نواقص/سيريالات)
-- + البيانات الأساسية (عملاء/موردين/منتجات/مخازن).
-- ملاحظة: نفس المسح ينفذه زر قسم "الصيانة والإصلاح" عبر الدالة
-- reset_all_data_keep_users (migration 0022) — هذا الملف للطوارئ اليدوية فقط.
--
-- ما يُحفظ: المستخدمون (profiles)، الأدوار والصلاحيات
-- (roles/user_roles/role_permissions/permissions/user_page_overrides)،
-- طرق الدفع (payment_methods)، الوحدات (units)، تصنيفات المنتجات
-- (product_categories)، تصنيفات المصروفات (expense_categories)،
-- إعدادات التطبيق (app_settings).
--
-- العدّادات تُصفَّر: كل الفواتير الجديدة تبدأ من 000001.
-- ============================================================================

BEGIN;

-- ---------- 1) مسح البيانات (CASCADE يتعامل مع ترتيب المفاتيح الأجنبية) ----------
TRUNCATE TABLE public.sales_return_items,
              public.sales_returns,
              public.purchase_return_items,
              public.purchase_returns,
              public.payments,
              public.shipments,
              public.sales_invoice_items,
              public.sales_invoices,
              public.sales_order_items,
              public.sales_orders,
              public.purchase_invoice_items,
              public.purchase_invoices,
              public.purchase_order_items,
              public.purchase_orders,
              public.procurement_items,
              public.procurement_requests,
              public.manufacturing_materials,
              public.manufacturing_orders,
              public.customized_items,
              public.warehouse_stock,
              public.stock_movements,
              public.shortages,
              public.product_serials,
              public.attachments,
              public.approvals,
              public.audit_logs,
              public.notifications,
              public.expenses,
              public.product_barcodes,
              public.products,
              public.customer_addresses,
              public.customers,
              public.suppliers,
              public.warehouse_users,
              public.warehouses
  RESTART IDENTITY CASCADE;

-- ---------- 2) ملفات المرفقات: لا يمكن مسحها بـ SQL مباشر (Supabase يمنع
-- DELETE FROM storage.objects بـ trigger حماية). احذفها من
-- Dashboard → Storage → bucket attachments، أو اتركها (باكت خاص).
-- سجلات المرفقات نفسها تُمسح مع الجداول بالأسفل. ----------

-- ---------- 3) تصفير عدّادات الترقيم ----------
ALTER SEQUENCE public.customer_code_seq RESTART WITH 1;
ALTER SEQUENCE public.customized_item_seq RESTART WITH 1;
ALTER SEQUENCE public.manufacturing_order_seq RESTART WITH 1;
ALTER SEQUENCE public.payment_seq RESTART WITH 1;
ALTER SEQUENCE public.procurement_seq RESTART WITH 1;
ALTER SEQUENCE public.purchase_invoice_seq RESTART WITH 1;
ALTER SEQUENCE public.purchase_order_seq RESTART WITH 1;
ALTER SEQUENCE public.purchase_return_seq RESTART WITH 1;
ALTER SEQUENCE public.sales_invoice_seq RESTART WITH 1;
ALTER SEQUENCE public.sales_order_seq RESTART WITH 1;
ALTER SEQUENCE public.sales_return_seq RESTART WITH 1;
ALTER SEQUENCE public.shipment_seq RESTART WITH 1;
ALTER SEQUENCE public.supplier_code_seq RESTART WITH 1;
ALTER SEQUENCE public.warehouse_code_seq RESTART WITH 1;
ALTER SEQUENCE public.expense_seq RESTART WITH 1;

COMMIT;

-- ---------- 4) تحقق: يجب أن تكون كلها أصفار ----------
SELECT 'sales_invoices' AS tbl, count(*) AS rows FROM public.sales_invoices
UNION ALL SELECT 'sales_orders', count(*) FROM public.sales_orders
UNION ALL SELECT 'purchase_invoices', count(*) FROM public.purchase_invoices
UNION ALL SELECT 'purchase_orders', count(*) FROM public.purchase_orders
UNION ALL SELECT 'payments', count(*) FROM public.payments
UNION ALL SELECT 'shipments', count(*) FROM public.shipments
UNION ALL SELECT 'sales_returns', count(*) FROM public.sales_returns
UNION ALL SELECT 'purchase_returns', count(*) FROM public.purchase_returns
UNION ALL SELECT 'manufacturing_orders', count(*) FROM public.manufacturing_orders
UNION ALL SELECT 'procurement_requests', count(*) FROM public.procurement_requests
UNION ALL SELECT 'products', count(*) FROM public.products
UNION ALL SELECT 'customers', count(*) FROM public.customers
UNION ALL SELECT 'suppliers', count(*) FROM public.suppliers
UNION ALL SELECT 'warehouses', count(*) FROM public.warehouses
UNION ALL SELECT 'warehouse_stock', count(*) FROM public.warehouse_stock
UNION ALL SELECT 'attachments', count(*) FROM public.attachments
UNION ALL SELECT 'notifications', count(*) FROM public.notifications
UNION ALL SELECT 'profiles (kept)', count(*) FROM public.profiles
UNION ALL SELECT 'payment_methods (kept)', count(*) FROM public.payment_methods;
