-- ============================================================
-- ERP Migration 0022: Reset all business data (RPC للمدير فقط)
-- ============================================================
-- دالة واحدة آمنة ينده عليها زر "مسح كل البيانات" من قسم الصيانة.
-- تمسح كل بيانات الشغل وتبدأ على نظافة، مع الحفاظ على:
--   المستخدمين (profiles)، الأدوار والصلاحيات
--   (roles/permissions/role_permissions/user_roles/user_page_overrides)،
--   وبيانات التأسيس (payment_methods, units, product_categories,
--   expense_categories, app_settings).
--
-- الحماية: SECURITY DEFINER + فحص users.manage عبر has_permission.
-- أي مستخدم بدون الصلاحية ياخد NO_PERMISSION.
-- التطبيق: supabase db push أو نفّذ الملف في SQL Editor.
-- ============================================================

create or replace function public.reset_all_data_keep_users()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('users.manage') then
    raise exception 'NO_PERMISSION';
  end if;

  -- 1) الحركات والتفاصيل (الأبناء أولا لتفادي كسر المفاتيح الأجنبية،
  --    وCASCADE كأمان إضافي).
  truncate table
    public.sales_return_items,
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
    public.product_barcodes,
    public.products,
    public.customer_addresses,
    public.customers,
    public.suppliers,
    public.warehouse_users,
    public.warehouses,
    public.expenses,
    public.attachments,
    public.approvals,
    public.audit_logs,
    public.notifications
  restart identity cascade;

  -- 2) تصفير عدّادات الترقيم (الفواتير الجديدة تبدأ من 000001).
  --    expense_categories تُحفظ لكن عدّاد المصروفات يُصفَّر.
  alter sequence if exists public.customer_code_seq restart with 1;
  alter sequence if exists public.supplier_code_seq restart with 1;
  alter sequence if exists public.warehouse_code_seq restart with 1;
  alter sequence if exists public.sales_order_seq restart with 1;
  alter sequence if exists public.sales_invoice_seq restart with 1;
  alter sequence if exists public.purchase_order_seq restart with 1;
  alter sequence if exists public.purchase_invoice_seq restart with 1;
  alter sequence if exists public.sales_return_seq restart with 1;
  alter sequence if exists public.purchase_return_seq restart with 1;
  alter sequence if exists public.shipment_seq restart with 1;
  alter sequence if exists public.payment_seq restart with 1;
  alter sequence if exists public.procurement_seq restart with 1;
  alter sequence if exists public.customized_item_seq restart with 1;
  alter sequence if exists public.manufacturing_order_seq restart with 1;
  alter sequence if exists public.expense_seq restart with 1;

  -- 3) سجل تدقيق واحد يوثّق المسح (بعد المسح حتى لا يُمسح).
  insert into public.audit_logs (user_id, action, entity_type, entity_id, new_data)
  values (
    auth.uid(),
    'RESET',
    'ALL_DATA',
    'ALL',
    jsonb_build_object('kept', 'users/roles/permissions/settings')
  );

  return jsonb_build_object('ok', true);
exception
  when raise_exception then
    raise;
  when others then
    raise exception 'RESET_FAILED: %', sqlerrm;
end;
$$;

-- النداء مسموح لأي مستخدم مسجّل، والفحص الداخلي يمنع غير المدير.
revoke all on function public.reset_all_data_keep_users() from public, anon;
grant execute on function public.reset_all_data_keep_users() to authenticated;
