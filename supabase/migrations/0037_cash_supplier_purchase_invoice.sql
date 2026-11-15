-- المورد النقدي في فاتورة المشتريات: السماح بـ supplier_id فارغ
-- بشرط وجود اسم نقدي (supplier_name_snapshot) — نفس نمط العميل
-- النقدي في فواتير المبيعات (CUSTOMER_REQUIRED).
-- طلبات الشراء (submit_purchase_order) تبقى بمورد إجباري.
create or replace function public.submit_purchase_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record; s record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('purchases.create')
       or public.has_permission('purchases.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into v from public.purchase_invoices where id = p_invoice;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  if v.status not in ('DRAFT','REJECTED') then raise exception 'INVALID_STATUS'; end if;
  if v.supplier_id is null then
    -- مورد نقدي: يقبل بشرط اسم نقدي محفوظ، وإلا مرفوض كما قبل.
    if v.supplier_name_snapshot is null
       or length(trim(v.supplier_name_snapshot)) = 0 then
      raise exception 'SUPPLIER_REQUIRED';
    end if;
  end if;
  if v.warehouse_id is null then raise exception 'WAREHOUSE_REQUIRED'; end if;
  if not exists (select 1 from public.purchase_invoice_items
      where purchase_invoice_id = p_invoice) then
    raise exception 'EMPTY_INVOICE';
  end if;
  select * into s from public.suppliers where id = v.supplier_id;
  if found then
    update public.purchase_invoices set
      supplier_name_snapshot = s.name,
      supplier_phone_snapshot = s.phone,
      supplier_address_snapshot = s.address,
      supplier_tax_number_snapshot = s.tax_number
      where id = p_invoice;
  end if;
  perform public.recalc_purchase_invoice(p_invoice);
  update public.purchase_invoices set status='PENDING_APPROVAL',
    rejected_by=null, rejected_at=null, rejection_reason=null
    where id = p_invoice;
  perform public.write_audit_log('STATUS_CHANGE','PURCHASE_INVOICE',
    p_invoice::text, jsonb_build_object('from', v.status),
    jsonb_build_object('to','PENDING_APPROVAL'));
end $$;
