-- ============================================================
-- ERP Migration 0027: fix non-credit auto-settle regression.
-- السبب: 0020 أعاد تعريف approve_sales_invoice من نسخة 0012
-- (لقطة التكلفة) فضاعت التسوية التلقائية بتاعة 0013، ففواتير
-- الكاش/انستاباي/تحويل... بقت تظهر في المستحقات رغم إنها مدفوعة.
-- القاعدة المطلوبة (من المستخدم):
--   أي وسيلة غير الآجل = الفلوس اتدفعت خلاص => PAID ولا مستحقات.
--   آجل (CREDIT) = قد يكون دفع عربون أو لا => المستحق = الإجمالي - المدفوع.
-- الإصلاح: دمج لقطة التكلفة (0020) + التسوية التلقائية (0013)
-- + إعفاء المدير (0012) في نفس الدالة، مع تسوية للقديم.
-- ============================================================

-- ---------- Sales: approve + cost snapshot + auto-settle ----------
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
  -- لقطة تكلفة البضاعة (المتوسط المرجح لحظة الاعتماد) — من 0020.
  update public.sales_invoice_items sii
    set unit_cost = coalesce(p.average_cost, p.purchase_price, 0)
    from public.products p
    where p.id = sii.product_id
      and sii.sales_invoice_id = p_invoice
      and sii.product_id is not null;
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
  -- التسوية التلقائية (من 0013): أي طريقة غير CREDIT = مدفوعة بالكامل.
  -- الآجل يفضل UNPAID/PARTIAL حسب العربون المسجل بدفعات.
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
  else
    -- آجل: حدث payment_status من الدفعات الموجودة (عربون) بدون تسوية.
    select grand_total into v_total from public.sales_invoices
      where id = p_invoice;
    select coalesce(sum(amount), 0) into v_paid from public.payments
      where sales_invoice_id = p_invoice and status = 'COMPLETED';
    update public.sales_invoices set payment_status = case
      when v_paid <= 0 then 'UNPAID' when v_paid < v_total then 'PARTIAL'
      else 'PAID' end
      where id = p_invoice;
  end if;
  perform public.write_audit_log('APPROVE', 'SALES_INVOICE',
    p_invoice::text, jsonb_build_object('from', 'PENDING_APPROVAL'),
    jsonb_build_object('to', 'APPROVED'));
end $$;

-- ---------- Purchases: تأكيد نفس القاعدة (غير آجل = مسدد) ----------
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
  update public.purchase_invoices set status='APPROVED',
    approved_by=v_uid, approved_at=now(),
    rejected_by=null, rejected_at=null, rejection_reason=null
    where id = p_invoice;
  select pm.code into v_method from public.payment_methods pm
    where pm.id = v.payment_method_id;
  select grand_total into v_total from public.purchase_invoices
    where id = p_invoice;
  select coalesce(sum(amount), 0) into v_paid from public.payments
    where purchase_invoice_id = p_invoice and status = 'COMPLETED';
  if v_method is not null and v_method != 'CREDIT' then
    if v_total - v_paid > 0 then
      insert into public.payments
        (supplier_id, purchase_invoice_id, payment_method_id,
         amount, notes, created_by)
        values (v.supplier_id, p_invoice, v.payment_method_id,
          v_total - v_paid, 'سداد تلقائي - ' || v_method, v_uid);
      select coalesce(sum(amount), 0) into v_paid from public.payments
        where purchase_invoice_id = p_invoice and status = 'COMPLETED';
    end if;
  end if;
  update public.purchase_invoices set payment_status = case
    when v_paid <= 0 then 'UNPAID' when v_paid < v_total then 'PARTIAL'
    else 'PAID' end
    where id = p_invoice;
  perform public.write_audit_log('APPROVE','PURCHASE_INVOICE',
    p_invoice::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','APPROVED'));
end $$;

-- ---------- تسوية الفواتير القديمة (كاش معتمد قبل الإصلاح) ----------
-- أي فاتورة APPROVED بطريقة غير آجل ولسه فيها باقي => سدد الباقي تلقائيا.
DO $$
DECLARE
  r record;
  v_method text;
  v_paid numeric;
  v_rem numeric;
BEGIN
  FOR r IN
    SELECT si.id, si.customer_id, si.payment_method_id,
           si.grand_total, si.created_by
      FROM public.sales_invoices si
     WHERE si.status = 'APPROVED'
  LOOP
    SELECT pm.code INTO v_method FROM public.payment_methods pm
      WHERE pm.id = r.payment_method_id;
    IF v_method IS NOT NULL AND v_method != 'CREDIT' THEN
      SELECT coalesce(sum(amount), 0) INTO v_paid FROM public.payments
        WHERE sales_invoice_id = r.id AND status = 'COMPLETED';
      v_rem := r.grand_total - v_paid;
      IF v_rem > 0 THEN
        INSERT INTO public.payments
          (customer_id, sales_invoice_id, payment_method_id,
           amount, notes, created_by)
          VALUES (r.customer_id, r.id, r.payment_method_id,
            v_rem, 'تحصيل تلقائي - ' || v_method || ' (تسوية 0027)', r.created_by);
        SELECT coalesce(sum(amount), 0) INTO v_paid FROM public.payments
          WHERE sales_invoice_id = r.id AND status = 'COMPLETED';
      END IF;
      UPDATE public.sales_invoices SET payment_status = CASE
        WHEN v_paid <= 0 THEN 'UNPAID'
        WHEN v_paid < r.grand_total THEN 'PARTIAL'
        ELSE 'PAID' END
        WHERE id = r.id;
    ELSE
      -- آجل قديم: ظبط payment_status من العربون بدون تسوية.
      SELECT coalesce(sum(amount), 0) INTO v_paid FROM public.payments
        WHERE sales_invoice_id = r.id AND status = 'COMPLETED';
      UPDATE public.sales_invoices SET payment_status = CASE
        WHEN v_paid <= 0 THEN 'UNPAID'
        WHEN v_paid < r.grand_total THEN 'PARTIAL'
        ELSE 'PAID' END
        WHERE id = r.id
          AND payment_status IS DISTINCT FROM (CASE
            WHEN v_paid <= 0 THEN 'UNPAID'
            WHEN v_paid < r.grand_total THEN 'PARTIAL'
            ELSE 'PAID' END);
    END IF;
  END LOOP;

  FOR r IN
    SELECT pi.id, pi.supplier_id, pi.payment_method_id,
           pi.grand_total, pi.created_by
      FROM public.purchase_invoices pi
     WHERE pi.status = 'APPROVED'
  LOOP
    SELECT pm.code INTO v_method FROM public.payment_methods pm
      WHERE pm.id = r.payment_method_id;
    IF v_method IS NOT NULL AND v_method != 'CREDIT' THEN
      SELECT coalesce(sum(amount), 0) INTO v_paid FROM public.payments
        WHERE purchase_invoice_id = r.id AND status = 'COMPLETED';
      v_rem := r.grand_total - v_paid;
      IF v_rem > 0 THEN
        INSERT INTO public.payments
          (supplier_id, purchase_invoice_id, payment_method_id,
           amount, notes, created_by)
          VALUES (r.supplier_id, r.id, r.payment_method_id,
            v_rem, 'سداد تلقائي - ' || v_method || ' (تسوية 0027)', r.created_by);
        SELECT coalesce(sum(amount), 0) INTO v_paid FROM public.payments
          WHERE purchase_invoice_id = r.id AND status = 'COMPLETED';
      END IF;
      UPDATE public.purchase_invoices SET payment_status = CASE
        WHEN v_paid <= 0 THEN 'UNPAID'
        WHEN v_paid < r.grand_total THEN 'PARTIAL'
        ELSE 'PAID' END
        WHERE id = r.id;
    END IF;
  END LOOP;
END $$;
