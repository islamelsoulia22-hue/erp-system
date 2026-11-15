-- ============================================================
-- ERP Migration 0036: backfill stock for approved standalone
-- purchase invoices (one-time).
-- الفواتير المعتمدة قبل ترحيل 0035 لم تنزل مخزونها لأن
-- القاعدة لم تكن موجودة لحظة اعتمادها. التسوية تضيف كمية
-- كل صنف لمخزن فاتورته (مرة واحدة فقط لكل فاتورة+صنف —
-- بوجود حركة PURCHASE_INVOICE مسجلة يتخطى).
-- الشروط: APPROVED + بدون طلب مرتبط + مخزن موجود +
-- صنف مرتبط + كمية > صفر.
-- تحديث warehouse_stock يطلق تريجر check_stock_levels
-- فيقفل التنبيهات والنواقص المغطاة تلقائيا.
-- ============================================================

DO $$
DECLARE r record; it record;
  v_before numeric(14,3); v_after numeric(14,3);
BEGIN
  FOR r IN
    SELECT * FROM public.purchase_invoices
     WHERE status = 'APPROVED'
       AND purchase_order_id IS NULL
       AND warehouse_id IS NOT NULL
  LOOP
    FOR it IN
      SELECT * FROM public.purchase_invoice_items
       WHERE purchase_invoice_id = r.id
         AND product_id IS NOT NULL
         AND coalesce(quantity, 0) > 0
    LOOP
      -- متسجل قبل كده (اعتماد جديد أو تسوية سابقة): تخطى.
      IF EXISTS (
        SELECT 1 FROM public.stock_movements
         WHERE reference_type = 'PURCHASE_INVOICE'
           AND reference_id = r.id::text
           AND product_id = it.product_id
      ) THEN CONTINUE; END IF;

      INSERT INTO public.warehouse_stock
        (warehouse_id, product_id, quantity)
        VALUES (r.warehouse_id, it.product_id, 0)
        ON CONFLICT (warehouse_id, product_id) DO NOTHING;
      SELECT quantity INTO v_before FROM public.warehouse_stock
       WHERE warehouse_id = r.warehouse_id
         AND product_id = it.product_id FOR UPDATE;
      UPDATE public.warehouse_stock
         SET quantity = quantity + it.quantity
       WHERE warehouse_id = r.warehouse_id
         AND product_id = it.product_id
       RETURNING quantity INTO v_after;
      INSERT INTO public.stock_movements
        (warehouse_id, product_id, movement_type, quantity,
         before_quantity, after_quantity, reference_type, reference_id,
         created_by, notes)
        VALUES (r.warehouse_id, it.product_id, 'PURCHASE', it.quantity,
          v_before, v_after, 'PURCHASE_INVOICE', r.id::text,
          r.created_by, 'تسوية بأثر رجعي 0036');
    END LOOP;
  END LOOP;
END $$;
