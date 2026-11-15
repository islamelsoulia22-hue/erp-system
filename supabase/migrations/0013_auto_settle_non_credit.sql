-- ============================================================
-- ERP Migration 0013: auto-settle non-credit invoices on approve.
-- Rule: choosing any payment method other than CREDIT (آجل) means
-- the money was already transferred, so the invoice must NOT sit
-- in outstanding balances. On approve, the remaining amount is
-- recorded as an automatic COMPLETED payment and payment_status
-- becomes PAID. CREDIT (or no method) stays UNPAID.
-- ============================================================

-- ---------- Sales ----------
create or replace function public.approve_sales_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record; it record; av numeric;
  v_total numeric; v_paid numeric; v_method text;
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
  -- Auto-settle: non-credit method = money already transferred.
  select pm.code into v_method from public.payment_methods pm
    where pm.id = v.payment_method_id;
  if v_method is not null and v_method != 'CREDIT' then
    select grand_total into v_total from public.sales_invoices
      where id = p_invoice;
    select coalesce(sum(amount), 0) into v_paid from public.payments
      where sales_invoice_id = p_invoice and status = 'COMPLETED';
    if v_total - v_paid > 0 then
      insert into public.payments
        (customer_id, sales_invoice_id, payment_method_id,
         amount, notes, created_by)
        values (v.customer_id, p_invoice, v.payment_method_id,
          v_total - v_paid, 'تحصيل تلقائي - ' || v_method, v_uid);
      select coalesce(sum(amount), 0) into v_paid from public.payments
        where sales_invoice_id = p_invoice and status = 'COMPLETED';
    end if;
    update public.sales_invoices set payment_status = case
      when v_paid <= 0 then 'UNPAID' when v_paid < v_total then 'PARTIAL'
      else 'PAID' end
      where id = p_invoice;
  end if;
  perform public.write_audit_log('APPROVE', 'SALES_INVOICE',
    p_invoice::text, jsonb_build_object('from', 'PENDING_APPROVAL'),
    jsonb_build_object('to', 'APPROVED'));
end $$;

-- ---------- Purchases ----------
create or replace function public.approve_purchase_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
  v_total numeric; v_paid numeric; v_method text;
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
  -- Auto-settle: non-credit method = money already transferred.
  select pm.code into v_method from public.payment_methods pm
    where pm.id = v.payment_method_id;
  if v_method is not null and v_method != 'CREDIT' then
    select grand_total into v_total from public.purchase_invoices
      where id = p_invoice;
    select coalesce(sum(amount), 0) into v_paid from public.payments
      where purchase_invoice_id = p_invoice and status = 'COMPLETED';
    if v_total - v_paid > 0 then
      insert into public.payments
        (supplier_id, purchase_invoice_id, payment_method_id,
         amount, notes, created_by)
        values (v.supplier_id, p_invoice, v.payment_method_id,
          v_total - v_paid, 'سداد تلقائي - ' || v_method, v_uid);
      select coalesce(sum(amount), 0) into v_paid from public.payments
        where purchase_invoice_id = p_invoice and status = 'COMPLETED';
    end if;
    update public.purchase_invoices set payment_status = case
      when v_paid <= 0 then 'UNPAID' when v_paid < v_total then 'PARTIAL'
      else 'PAID' end
      where id = p_invoice;
  end if;
  perform public.write_audit_log('APPROVE','PURCHASE_INVOICE',
    p_invoice::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','APPROVED'));
end $$;
