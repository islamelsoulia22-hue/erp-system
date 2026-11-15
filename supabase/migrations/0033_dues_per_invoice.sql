-- ============================================================
-- ERP Migration 0033: dues correctness (per-invoice clamp + link).
-- مشكلتين كانوا مصفرين المستحقات:
-- 1) الدفعة المسجلة من الفاتورة (عربون) كانت بتتحفظ بدون
--    customer_id/supplier_id، فكشف العميل مبيشوفهاش.
--    الإصلاح: create_payment تملأ الطرف من الفاتورة تلقائيا
--    + تسوية المدفوعات القديمة.
-- 2) المرتجع على فاتورة مدفوعة كان بيعمل سالب ياكل المستحق
--    الحقيقي للفواتير الآجلة، والتقفيل clamp(0) على الإجمالي
--    كان بيخفي الـ 400 جنيه المستحقة فعلا.
--    الإصلاح: المستحق = مجموع max(0, الفاتورة − مدفوعها −
--    مرتجعها) per فاتورة — لا فاتورة تسحب التانية بالسالب.
-- ============================================================

-- ---------- 1) create_payment يملأ الطرف من الفاتورة ----------
create or replace function public.create_payment(
  p_customer_id uuid default null,
  p_supplier_id uuid default null,
  p_sales_invoice_id uuid default null,
  p_purchase_invoice_id uuid default null,
  p_method_id uuid default null,
  p_amount numeric default null,
  p_reference text default null,
  p_notes text default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_pid uuid;
  v_total numeric; v_paid numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('sales.create')
       or public.has_permission('purchases.create')) then
    raise exception 'NO_PERMISSION';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
  if p_sales_invoice_id is not null and p_purchase_invoice_id is not null then
    raise exception 'ONE_INVOICE_ONLY';
  end if;
  -- وراثة الطرف من الفاتورة لو مش متبعت (عربون من التفاصيل).
  if p_sales_invoice_id is not null and p_customer_id is null then
    select customer_id into p_customer_id from public.sales_invoices
      where id = p_sales_invoice_id;
  end if;
  if p_purchase_invoice_id is not null and p_supplier_id is null then
    select supplier_id into p_supplier_id from public.purchase_invoices
      where id = p_purchase_invoice_id;
  end if;

  insert into public.payments
    (customer_id, supplier_id, sales_invoice_id, purchase_invoice_id,
     payment_method_id, amount, transaction_reference, notes, created_by)
    values (p_customer_id, p_supplier_id, p_sales_invoice_id,
      p_purchase_invoice_id, p_method_id, p_amount, p_reference,
      p_notes, v_uid)
    returning id into v_pid;

  if p_sales_invoice_id is not null then
    select grand_total into v_total from public.sales_invoices
      where id = p_sales_invoice_id;
    select coalesce(sum(amount),0) into v_paid from public.payments
      where sales_invoice_id = p_sales_invoice_id and status='COMPLETED';
    update public.sales_invoices set payment_status = case
      when v_paid <= 0 then 'UNPAID' when v_paid < v_total then 'PARTIAL'
      else 'PAID' end
      where id = p_sales_invoice_id;
  end if;
  if p_purchase_invoice_id is not null then
    select grand_total into v_total from public.purchase_invoices
      where id = p_purchase_invoice_id;
    select coalesce(sum(amount),0) into v_paid from public.payments
      where purchase_invoice_id = p_purchase_invoice_id and status='COMPLETED';
    update public.purchase_invoices set payment_status = case
      when v_paid <= 0 then 'UNPAID' when v_paid < v_total then 'PARTIAL'
      else 'PAID' end
      where id = p_purchase_invoice_id;
  end if;

  perform public.write_audit_log('PAYMENT',
    case when p_sales_invoice_id is not null then 'SALES_INVOICE'
         else 'PURCHASE_INVOICE' end,
    coalesce(p_sales_invoice_id, p_purchase_invoice_id)::text,
    null, jsonb_build_object('payment', v_pid, 'amount', p_amount));
  return v_pid;
end $$;

-- ---------- 2) تسوية الدفعات القديمة بدون طرف ----------
update public.payments p
  set customer_id = si.customer_id
  from public.sales_invoices si
  where p.sales_invoice_id = si.id
    and p.customer_id is null
    and si.customer_id is not null;

update public.payments p
  set supplier_id = pi.supplier_id
  from public.purchase_invoices pi
  where p.purchase_invoice_id = pi.id
    and p.supplier_id is null
    and pi.supplier_id is not null;

-- ---------- 3) أرصدة per فاتورة (clamp لكل فاتورة) ----------
create or replace function public.customer_balance(p_customer uuid)
returns table (total numeric, paid numeric, outstanding numeric)
language sql stable security definer set search_path = public as $$
  with inv as (
    select si.id, si.grand_total as t
      from public.sales_invoices si
     where si.customer_id = p_customer
       and si.status in ('APPROVED','PENDING_APPROVAL')),
  pay as (
    select p.sales_invoice_id as id, sum(p.amount) as p
      from public.payments p
     where p.customer_id = p_customer and p.status='COMPLETED'
     group by p.sales_invoice_id),
  ret as (
    select sr.sales_invoice_id as id, sum(sr.grand_total) as r
      from public.sales_returns sr
     where sr.customer_id = p_customer and sr.status='COMPLETED'
     group by sr.sales_invoice_id)
  select coalesce((select sum(t) from inv), 0),
         coalesce((select sum(amount) from public.payments
           where customer_id = p_customer and status='COMPLETED'), 0),
         coalesce((select sum(
             greatest(0, i.t - coalesce(p.p,0) - coalesce(r.r,0)))
           from inv i
           left join pay p on p.id = i.id
           left join ret r on r.id = i.id), 0);
$$;

create or replace function public.supplier_balance(p_supplier uuid)
returns table (total numeric, paid numeric, outstanding numeric)
language sql stable security definer set search_path = public as $$
  with inv as (
    select pi.id, pi.grand_total as t
      from public.purchase_invoices pi
     where pi.supplier_id = p_supplier
       and pi.status in ('APPROVED','PENDING_APPROVAL')),
  pay as (
    select p.purchase_invoice_id as id, sum(p.amount) as p
      from public.payments p
     where p.supplier_id = p_supplier and p.status='COMPLETED'
     group by p.purchase_invoice_id),
  ret as (
    select pr.purchase_invoice_id as id, sum(pr.grand_total) as r
      from public.purchase_returns pr
     where pr.supplier_id = p_supplier and pr.status='COMPLETED'
     group by pr.purchase_invoice_id)
  select coalesce((select sum(t) from inv), 0),
         coalesce((select sum(amount) from public.payments
           where supplier_id = p_supplier and status='COMPLETED'), 0),
         coalesce((select sum(
             greatest(0, i.t - coalesce(p.p,0) - coalesce(r.r,0)))
           from inv i
           left join pay p on p.id = i.id
           left join ret r on r.id = i.id), 0);
$$;

-- ---------- 4) إجمالي المستحقات (للداشبورد) ----------
create or replace function public.total_customer_outstanding()
returns numeric language sql stable security definer
set search_path = public as $$
  with inv as (
    select si.id, si.grand_total as t
      from public.sales_invoices si
     where si.status in ('APPROVED','PENDING_APPROVAL')),
  pay as (
    select p.sales_invoice_id as id, sum(p.amount) as p
      from public.payments p
     where p.sales_invoice_id is not null and p.status='COMPLETED'
     group by p.sales_invoice_id),
  ret as (
    select sr.sales_invoice_id as id, sum(sr.grand_total) as r
      from public.sales_returns sr
     where sr.sales_invoice_id is not null and sr.status='COMPLETED'
     group by sr.sales_invoice_id)
  select coalesce(sum(
      greatest(0, i.t - coalesce(p.p,0) - coalesce(r.r,0))), 0)
    from inv i
    left join pay p on p.id = i.id
    left join ret r on r.id = i.id;
$$;

create or replace function public.total_supplier_outstanding()
returns numeric language sql stable security definer
set search_path = public as $$
  with inv as (
    select pi.id, pi.grand_total as t
      from public.purchase_invoices pi
     where pi.status in ('APPROVED','PENDING_APPROVAL')),
  pay as (
    select p.purchase_invoice_id as id, sum(p.amount) as p
      from public.payments p
     where p.purchase_invoice_id is not null and p.status='COMPLETED'
     group by p.purchase_invoice_id),
  ret as (
    select pr.purchase_invoice_id as id, sum(pr.grand_total) as r
      from public.purchase_returns pr
     where pr.purchase_invoice_id is not null and pr.status='COMPLETED'
     group by pr.purchase_invoice_id)
  select coalesce(sum(
      greatest(0, i.t - coalesce(p.p,0) - coalesce(r.r,0))), 0)
    from inv i
    left join pay p on p.id = i.id
    left join ret r on r.id = i.id;
$$;
