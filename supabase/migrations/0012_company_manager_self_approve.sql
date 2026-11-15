-- ============================================================
-- ERP Migration 0012: company_manager bypasses self-approval block.
-- Rule: maker != checker for everyone EXCEPT مدير الشركة,
-- who may approve/reject his own documents.
-- ============================================================

create or replace function public.is_company_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_role('company_manager');
$$;

-- ---------- Sales ----------
create or replace function public.approve_sales_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record; it record; av numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('sales.approve') then
    raise exception 'NO_PERMISSION: sales.approve required';
  end if;
  select * into v from public.sales_invoices where id = p_invoice for update;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid and not public.is_company_manager() then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذه الفاتورة';
  end if;
  perform public.recalc_sales_invoice(p_invoice);
  -- Reserve each tracked product
  for it in select sii.*, p.track_inventory
    from public.sales_invoice_items sii
    left join public.products p on p.id = sii.product_id
    where sii.sales_invoice_id = p_invoice loop
    if it.product_id is not null and coalesce(it.track_inventory, true) then
      select quantity - reserved_quantity into av
        from public.warehouse_stock
        where warehouse_id = v.warehouse_id and product_id = it.product_id
        for update;
      if not found or av < it.quantity then
        raise exception 'INSUFFICIENT_STOCK: %', it.item_name;
      end if;
      update public.warehouse_stock
        set reserved_quantity = reserved_quantity + it.quantity
        where warehouse_id = v.warehouse_id and product_id = it.product_id;
    end if;
  end loop;
  update public.sales_invoices
    set status = 'APPROVED', approved_by = v_uid, approved_at = now(),
        rejected_by = null, rejected_at = null, rejection_reason = null
    where id = p_invoice;
  perform public.write_audit_log('APPROVE', 'SALES_INVOICE',
    p_invoice::text, jsonb_build_object('from', 'PENDING_APPROVAL'),
    jsonb_build_object('to', 'APPROVED'));
end $$;

create or replace function public.reject_sales_invoice(
  p_invoice uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('sales.approve') then
    raise exception 'NO_PERMISSION: sales.approve required';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'REASON_REQUIRED';
  end if;
  select * into v from public.sales_invoices where id = p_invoice for update;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid and not public.is_company_manager() then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذه الفاتورة';
  end if;
  update public.sales_invoices
    set status = 'REJECTED', rejected_by = v_uid, rejected_at = now(),
        rejection_reason = p_reason,
        approved_by = null, approved_at = null
    where id = p_invoice;
  perform public.write_audit_log('REJECT', 'SALES_INVOICE',
    p_invoice::text, jsonb_build_object('from', 'PENDING_APPROVAL'),
    jsonb_build_object('to', 'REJECTED', 'reason', p_reason));
end $$;

-- ---------- Purchases ----------
create or replace function public.approve_purchase_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('purchases.approve') then
    raise exception 'NO_PERMISSION: purchases.approve required';
  end if;
  select * into v from public.purchase_invoices where id = p_invoice for update;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid and not public.is_company_manager() then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذه الفاتورة';
  end if;
  perform public.recalc_purchase_invoice(p_invoice);
  -- NOTE: no stock change here by design.
  update public.purchase_invoices set status='APPROVED',
    approved_by=v_uid, approved_at=now(),
    rejected_by=null, rejected_at=null, rejection_reason=null
    where id = p_invoice;
  perform public.write_audit_log('APPROVE','PURCHASE_INVOICE',
    p_invoice::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','APPROVED'));
end $$;

create or replace function public.reject_purchase_invoice(
  p_invoice uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('purchases.approve') then
    raise exception 'NO_PERMISSION: purchases.approve required';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'REASON_REQUIRED';
  end if;
  select * into v from public.purchase_invoices where id = p_invoice for update;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid and not public.is_company_manager() then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذه الفاتورة';
  end if;
  update public.purchase_invoices set status='REJECTED',
    rejected_by=v_uid, rejected_at=now(), rejection_reason=p_reason,
    approved_by=null, approved_at=null where id = p_invoice;
  perform public.write_audit_log('REJECT','PURCHASE_INVOICE',
    p_invoice::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','REJECTED','reason',p_reason));
end $$;

-- ---------- Customized (manufacturing) ----------
create or replace function public.approve_customized_item(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('sales.approve') then
    raise exception 'NO_PERMISSION: sales.approve required';
  end if;
  select * into v from public.customized_items where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid and not public.is_company_manager() then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذا الصنف';
  end if;
  update public.customized_items set status='APPROVED',
    approved_by=v_uid, approved_at=now() where id=p_id;
  perform public.write_audit_log('APPROVE','CUSTOMIZED_ITEM',
    p_id::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','APPROVED'));
end $$;

create or replace function public.reject_customized_item(
  p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('sales.approve') then
    raise exception 'NO_PERMISSION: sales.approve required';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'REASON_REQUIRED';
  end if;
  select * into v from public.customized_items where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid and not public.is_company_manager() then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذا الصنف';
  end if;
  update public.customized_items set status='REJECTED' where id=p_id;
  perform public.write_audit_log('REJECT','CUSTOMIZED_ITEM',
    p_id::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','REJECTED','reason',p_reason));
end $$;

-- ---------- Procurement ----------
create or replace function public.approve_procurement(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('purchases.approve') then
    raise exception 'NO_PERMISSION: purchases.approve required';
  end if;
  select * into v from public.procurement_requests
    where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.requested_by = v_uid and not public.is_company_manager() then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذا الطلب';
  end if;
  perform public.refresh_procurement_availability(p_id);
  update public.procurement_requests set status='APPROVED',
    approved_by=v_uid, approved_at=now() where id=p_id;
  update public.approvals set status='APPROVED',
    approved_by=v_uid, approved_at=now()
    where entity_type='PROCUREMENT_REQUEST' and entity_id=p_id::text
      and status='PENDING';
  perform public.write_audit_log('APPROVE','PROCUREMENT_REQUEST',
    p_id::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','APPROVED'));
  if v.requested_by is not null then
    perform public.create_notification(v.requested_by, 'APPROVAL',
      'تم اعتماد طلب التوريد',
      'طلب ' || v.request_number || ' تم اعتماده.',
      'PROCUREMENT_REQUEST', p_id::text);
  end if;
end $$;

create or replace function public.reject_procurement(
  p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('purchases.approve') then
    raise exception 'NO_PERMISSION: purchases.approve required';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'REASON_REQUIRED';
  end if;
  select * into v from public.procurement_requests
    where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.requested_by = v_uid and not public.is_company_manager() then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذا الطلب';
  end if;
  update public.procurement_requests set status='REJECTED' where id=p_id;
  update public.approvals set status='REJECTED',
    approved_by=v_uid, approved_at=now(), comment=p_reason
    where entity_type='PROCUREMENT_REQUEST' and entity_id=p_id::text
      and status='PENDING';
  perform public.write_audit_log('REJECT','PROCUREMENT_REQUEST',
    p_id::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','REJECTED','reason',p_reason));
end $$;
