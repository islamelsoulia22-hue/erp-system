-- ============================================================
-- ERP Migration 0014: one-time backfill for non-credit invoices
-- approved BEFORE 0013 (no auto payment was recorded then).
-- Same remainder logic: settle only the unpaid remainder, update
-- payment_status. Safe to re-run (inserts only when remainder > 0).
-- ============================================================

DO $$
DECLARE
  r record;
  v_method text;
  v_paid numeric;
  v_rem numeric;
BEGIN
  -- ---------- Sales ----------
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
            v_rem, 'تحصيل تلقائي - ' || v_method || ' (تسوية)', r.created_by);
        SELECT coalesce(sum(amount), 0) INTO v_paid FROM public.payments
          WHERE sales_invoice_id = r.id AND status = 'COMPLETED';
      END IF;
      UPDATE public.sales_invoices SET payment_status = CASE
        WHEN v_paid <= 0 THEN 'UNPAID'
        WHEN v_paid < r.grand_total THEN 'PARTIAL'
        ELSE 'PAID' END
        WHERE id = r.id;
    END IF;
  END LOOP;

  -- ---------- Purchases ----------
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
            v_rem, 'سداد تلقائي - ' || v_method || ' (تسوية)', r.created_by);
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
