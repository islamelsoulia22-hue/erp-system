-- ============================================================
-- ERP Migration 0024: Force delete product (for user-requested removal
-- even when stock / movements exist).
-- Rule: normal delete stays RESTRICT; this RPC is the only force path.
-- ============================================================

create or replace function public.delete_product_force(
  p_product_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_old jsonb;
  v_reserved numeric(14,3) := 0;
  v_qty numeric(14,3) := 0;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('products.create') then
    raise exception 'NO_PERMISSION: products.create required';
  end if;
  if p_product_id is null then raise exception 'PRODUCT_NOT_FOUND'; end if;

  select to_jsonb(p) into v_old from public.products p where p.id = p_product_id;
  if v_old is null then raise exception 'PRODUCT_NOT_FOUND'; end if;

  -- ممنوع الحذف النهائي لو عليه كمية محجوزة (محجوزة لفاتورة معتمدة).
  select coalesce(sum(reserved_quantity), 0), coalesce(sum(quantity), 0)
    into v_reserved, v_qty
    from public.warehouse_stock
    where product_id = p_product_id;
  if v_reserved > 0 then
    raise exception 'HAS_RESERVED_STOCK: cannot force-delete with reserved quantity %', v_reserved;
  end if;

  -- 1) امسح رصيد المخزون (حتى لو الكمية > 0 — حذف قسري بطلب المستخدم).
  delete from public.warehouse_stock where product_id = p_product_id;

  -- 2) امسح سجل حركات الصنف (خاص بالصنف فقط — باقي الفواتير product_id فيها SET NULL تلقائيا).
  delete from public.stock_movements where product_id = p_product_id;

  -- 3) امسح السيريالات والباركود (عادة CASCADE لكن نحذف صراحة للأمان).
  delete from public.product_serials where product_id = p_product_id;
  delete from public.product_barcodes where product_id = p_product_id;

  -- 4) احذف الصنف نفسه (الجداول الباقية كلها SET NULL فلا تمنع الحذف).
  delete from public.products where id = p_product_id;

  perform public.write_audit_log('DELETE_FORCE', 'PRODUCT', p_product_id::text, v_old,
    jsonb_build_object('deleted_qty', v_qty));
end $$;

-- السماح للمديرين باستدعاء الحذف القسري من التطبيق.
grant execute on function public.delete_product_force(uuid) to authenticated;
