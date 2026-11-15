-- ============================================================
-- ERP Migration 0035: purchase invoice increases stock +
-- shortages auto-resolve when covered.
-- مشكلتين:
-- 1) فاتورة المشتريات المباشرة (بدون طلب مرتبط) كانت لا تزيد
--    المخزون أبدا — الكمية المتاحة تفضل صفر رغم الشراء من
--    المورد، ومرتجع المشتريات كان يفشل لعدم وجود رصيد.
--    الإصلاح: عند الاعتماد، أصناف الفاتورة تنزل في مخزن
--    الفاتورة المختار. الفواتير المرتبطة بطلب
--    (purchase_order_id) تتخطى لأن مخزونها دخل بالفعل
--    عبر الاستلام — عشان ميتضاعفش.
-- 2) طلبات النواقص (shortages) كانت تفضل PENDING حتى بعد
--    وصول البضاعة — بس تنبيهات stock_alerts هي اللي
--    بتتقفل تلقائيا. الإصلاح: check_stock_levels يقفل
--    طلبات PENDING/ORDERED لنفس الصنف+المخزن كـ DONE
--    لما المتاح الحر يغطي الكمية المطلوبة — الرسالة
--    تتشال لوحدها أول ما الصنف ينزل المخزن.
-- ============================================================

-- ---------- 1) اعتماد فاتورة المشتريات + زيادة المخزون ----------
-- نسخة كاملة من 0027 (صلاحيات + اعتماد + تسوية تلقائية لغير
-- الآجل + تحديث payment_status) مع إضافة كتلة المخزون.
create or replace function public.approve_purchase_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
  v_total numeric; v_paid numeric; v_method text;
  v_before numeric(14,3); v_after numeric(14,3);
  it record;
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
  -- زيادة المخزون للفواتير المباشرة فقط: الكمية تنزل في مخزن
  -- الفاتورة. المرتبطة بطلب تتخطى (دخلت بالاستلام).
  if v.purchase_order_id is null and v.warehouse_id is not null then
    for it in select * from public.purchase_invoice_items
        where purchase_invoice_id = p_invoice for update loop
      if it.product_id is not null and coalesce(it.quantity, 0) > 0 then
        insert into public.warehouse_stock
          (warehouse_id, product_id, quantity)
          values (v.warehouse_id, it.product_id, 0)
          on conflict (warehouse_id, product_id) do nothing;
        select quantity into v_before from public.warehouse_stock
          where warehouse_id = v.warehouse_id
            and product_id = it.product_id for update;
        update public.warehouse_stock
          set quantity = quantity + it.quantity
          where warehouse_id = v.warehouse_id
            and product_id = it.product_id
          returning quantity into v_after;
        insert into public.stock_movements
          (warehouse_id, product_id, movement_type, quantity,
           before_quantity, after_quantity, reference_type, reference_id,
           created_by, notes)
          values (v.warehouse_id, it.product_id, 'PURCHASE', it.quantity,
            v_before, v_after, 'PURCHASE_INVOICE', p_invoice::text,
            v_uid, 'اعتماد فاتورة مشتريات');
      end if;
    end loop;
  end if;
  perform public.write_audit_log('APPROVE','PURCHASE_INVOICE',
    p_invoice::text, jsonb_build_object('from','PENDING_APPROVAL'),
    jsonb_build_object('to','APPROVED'));
end $$;

-- ---------- 2) إقفال النواقص المغطاة تلقائيا ----------
-- نسخة كاملة من check_stock_levels (0034) مع إضافة إقفال
-- طلبات النواقص PENDING/ORDERED لنفس الصنف+المخزن كـ DONE
-- عندما يغطي المتاح الحر الكمية المطلوبة.
create or replace function public.check_stock_levels(
  p_warehouse uuid, p_product uuid)
returns void language plpgsql security definer
set search_path = public as $$
declare v_avail numeric; v_min numeric;
  v_pname text; v_wname text; v_sup uuid;
  v_need numeric; v_aid uuid; v_sh uuid;
begin
  select ws.quantity - ws.reserved_quantity into v_avail
    from public.warehouse_stock ws
   where ws.warehouse_id = p_warehouse
     and ws.product_id = p_product;
  if not found then return; end if;
  select coalesce(p.minimum_stock, 0), p.name, p.supplier_id
    into v_min, v_pname, v_sup
    from public.products p where p.id = p_product;
  if not found then return; end if;
  select w.name into v_wname
    from public.warehouses w where w.id = p_warehouse;

  -- قفل القديم اللي اتحل.
  if v_avail > 0 then
    update public.stock_alerts set status = 'RESOLVED'
     where product_id = p_product and warehouse_id = p_warehouse
       and level = 'OUT_OF_STOCK' and status = 'NEW';
  end if;
  if v_min <= 0 or v_avail > v_min then
    update public.stock_alerts set status = 'RESOLVED'
     where product_id = p_product and warehouse_id = p_warehouse
       and level = 'MINIMUM' and status = 'NEW';
  end if;

  -- النواقص المغطاة تتقفل تلقائيا: المتاح الحر >= المطلوب.
  if v_avail > 0 then
    update public.shortages set status = 'DONE'
     where product_id = p_product and warehouse_id = p_warehouse
       and status in ('PENDING', 'ORDERED')
       and required_qty <= v_avail;
  end if;

  -- نفذ (صفر): تنبيه + نواقص تلقائي + إشعار.
  if v_avail <= 0 then
    if not exists (select 1 from public.stock_alerts
        where product_id = p_product and warehouse_id = p_warehouse
          and level = 'OUT_OF_STOCK' and status = 'NEW') then
      insert into public.stock_alerts
        (product_id, warehouse_id, level, available_qty)
        values (p_product, p_warehouse, 'OUT_OF_STOCK', v_avail)
        returning id into v_aid;
      -- نواقص تلقائي (كمية = الحد الأدنى، أو 1 لو بدون حد).
      v_need := greatest(v_min, 1);
      select id into v_sh from public.shortages
       where product_id = p_product and warehouse_id = p_warehouse
         and status = 'PENDING' limit 1;
      if found then
        update public.shortages
           set required_qty = required_qty + v_need,
               updated_at = now()
         where id = v_sh;
      else
        insert into public.shortages
          (product_id, warehouse_id, supplier_id, required_qty,
           status, source_type, source_id)
          values (p_product, p_warehouse, v_sup, v_need,
            'PENDING', 'STOCK_ALERT', v_aid::text);
      end if;
      perform public.notify_by_permission(
        'purchases.approve', 'STOCK_ALERT',
        'صنف نفذ من المخزون',
        coalesce(v_pname, 'صنف') || ' — مخزن ' ||
          coalesce(v_wname, '') ||
          ' (واتسجل في النواقص تلقائيا)',
        'STOCK_ALERT', v_aid::text);
    end if;
    return;
  end if;

  -- وصل الحد الأدنى: تنبيه + إشعار (طلب بضاعة للمدير).
  if v_min > 0 and v_avail <= v_min then
    if not exists (select 1 from public.stock_alerts
        where product_id = p_product and warehouse_id = p_warehouse
          and level = 'MINIMUM' and status = 'NEW') then
      insert into public.stock_alerts
        (product_id, warehouse_id, level, available_qty)
        values (p_product, p_warehouse, 'MINIMUM', v_avail)
        returning id into v_aid;
      perform public.notify_by_permission(
        'purchases.approve', 'STOCK_ALERT',
        'صنف وصل للحد الأدنى',
        coalesce(v_pname, 'صنف') || ' — مخزن ' ||
          coalesce(v_wname, '') ||
          ' (المتاح ' || v_avail::text || ')',
        'STOCK_ALERT', v_aid::text);
    end if;
  end if;
end $$;
