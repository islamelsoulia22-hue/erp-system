-- ============================================================
-- ERP Migration 0009: Shipping + Payments + Credit due dates
-- Ship deducts reserved stock (SALE); payments update invoice status.
-- ============================================================

create sequence if not exists shipment_seq start 1;
create sequence if not exists payment_seq start 1;

create or replace function public.generate_shipment_number()
returns text language plpgsql as $$
declare n bigint; y text;
begin
  n := nextval('shipment_seq');
  y := to_char(now(), 'YYYY');
  return 'SHP-' || y || '-' || lpad(n::text, 6, '0');
end $$;

create or replace function public.generate_payment_number()
returns text language plpgsql as $$
declare n bigint; y text;
begin
  n := nextval('payment_seq');
  y := to_char(now(), 'YYYY');
  return 'PAY-' || y || '-' || lpad(n::text, 6, '0');
end $$;

-- ---------- Shipments ----------
create table if not exists public.shipments (
  id uuid primary key default gen_random_uuid(),
  shipment_number text not null unique
    default public.generate_shipment_number(),
  sales_invoice_id uuid references public.sales_invoices(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  shipping_company text,
  tracking_number text,
  recipient_name text,
  recipient_phone text,
  address text,
  governorate text,
  city text,
  latitude double precision,
  longitude double precision,
  shipping_cost numeric(14,2) not null default 0 check (shipping_cost >= 0),
  collection_method text
    check (collection_method is null or collection_method in
      ('CASH','INSTAPAY','VODAFONE_CASH','BANK_TRANSFER','SHIPPING_COMPANY','CREDIT','NONE')),
  collection_amount numeric(14,2) not null default 0 check (collection_amount >= 0),
  status text not null default 'PREPARING'
    check (status in ('PREPARING','SHIPPED','DELIVERED','CANCELLED')),
  shipped_at timestamptz,
  delivered_at timestamptz,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_shp_number on public.shipments (shipment_number);
create index if not exists idx_shp_invoice on public.shipments (sales_invoice_id);
create index if not exists idx_shp_customer on public.shipments (customer_id);
create index if not exists idx_shp_status on public.shipments (status);

drop trigger if exists trg_shp_updated on public.shipments;
create trigger trg_shp_updated before update on public.shipments
  for each row execute function public.handle_updated_at();

-- ---------- Payments ----------
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  payment_number text not null unique
    default public.generate_payment_number(),
  customer_id uuid references public.customers(id) on delete set null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  sales_invoice_id uuid references public.sales_invoices(id) on delete set null,
  purchase_invoice_id uuid references public.purchase_invoices(id) on delete set null,
  payment_method_id uuid references public.payment_methods(id),
  amount numeric(14,2) not null check (amount > 0),
  transaction_reference text,
  payment_date date not null default CURRENT_DATE,
  status text not null default 'COMPLETED'
    check (status in ('COMPLETED','CANCELLED')),
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint chk_pay_link check (
    (sales_invoice_id is not null)::int
    + (purchase_invoice_id is not null)::int <= 1
  )
);

create index if not exists idx_pay_number on public.payments (payment_number);
create index if not exists idx_pay_customer on public.payments (customer_id);
create index if not exists idx_pay_supplier on public.payments (supplier_id);
create index if not exists idx_pay_sinv on public.payments (sales_invoice_id);
create index if not exists idx_pay_pinv on public.payments (purchase_invoice_id);
create index if not exists idx_pay_date on public.payments (payment_date desc);

-- ---------- Credit due-date auto-fill ----------
create or replace function public.sales_credit_due()
returns trigger language plpgsql as $$
begin
  if new.credit_period_days is not null
     and new.due_date is null then
    new.due_date := CURRENT_DATE + new.credit_period_days;
  end if;
  return new;
end $$;
drop trigger if exists trg_sales_credit_due on public.sales_invoices;
create trigger trg_sales_credit_due
  before insert or update of credit_period_days
  on public.sales_invoices for each row
  execute function public.sales_credit_due();

-- ---------- RLS ----------
alter table public.shipments enable row level security;
alter table public.payments enable row level security;

drop policy if exists "shp_read" on public.shipments;
create policy "shp_read" on public.shipments
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('sales.view') or public.has_permission('sales.create')
    or public.has_permission('sales.edit')));
drop policy if exists "shp_insert" on public.shipments;
create policy "shp_insert" on public.shipments
  for insert to authenticated
  with check (public.has_permission('sales.create') or public.has_permission('sales.edit'));
drop policy if exists "shp_update" on public.shipments;
create policy "shp_update" on public.shipments
  for update to authenticated
  using (public.has_permission('sales.create') or public.has_permission('sales.edit'))
  with check (public.has_permission('sales.create') or public.has_permission('sales.edit'));

drop policy if exists "pay_read" on public.payments;
create policy "pay_read" on public.payments
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('sales.view') or public.has_permission('purchases.view')
    or public.has_permission('reports.view')));
drop policy if exists "pay_insert" on public.payments;
create policy "pay_insert" on public.payments
  for insert to authenticated
  with check (public.has_permission('sales.create') or public.has_permission('purchases.create'));

-- ============================================================
-- RPCs
-- ============================================================

-- Ship: PREPARING -> SHIPPED + final stock deduction (reserve released)
create or replace function public.ship_shipment(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); s record; inv record; it record;
  v_q numeric; v_r numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('sales.create')
       or public.has_permission('sales.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into s from public.shipments where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if s.status != 'PREPARING' then raise exception 'INVALID_STATUS'; end if;
  if s.sales_invoice_id is null then
    update public.shipments set status='SHIPPED', shipped_at=now()
      where id = p_id;
    return;
  end if;
  select * into inv from public.sales_invoices
    where id = s.sales_invoice_id for update;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  if inv.status != 'APPROVED' then raise exception 'INVOICE_NOT_APPROVED'; end if;
  if inv.warehouse_id is null then raise exception 'WAREHOUSE_REQUIRED'; end if;

  for it in select sii.*, p.track_inventory
    from public.sales_invoice_items sii
    left join public.products p on p.id = sii.product_id
    where sii.sales_invoice_id = inv.id loop
    if it.product_id is not null and coalesce(it.track_inventory, true) then
      select quantity, reserved_quantity into v_q, v_r
        from public.warehouse_stock
        where warehouse_id = inv.warehouse_id
          and product_id = it.product_id for update;
      if not found then raise exception 'STOCK_NOT_FOUND: %', it.item_name; end if;
      if v_q < it.quantity then
        raise exception 'INSUFFICIENT_STOCK: %', it.item_name;
      end if;
      if v_r < it.quantity then
        raise exception 'NOT_RESERVED: %', it.item_name;
      end if;
      update public.warehouse_stock
        set quantity = quantity - it.quantity,
            reserved_quantity = reserved_quantity - it.quantity
        where warehouse_id = inv.warehouse_id
          and product_id = it.product_id;
      insert into public.stock_movements
        (warehouse_id, product_id, movement_type, quantity,
         before_quantity, after_quantity, reference_type, reference_id,
         created_by, notes)
        values (inv.warehouse_id, it.product_id, 'SALE', it.quantity,
          v_q, v_q - it.quantity, 'SALES_INVOICE', inv.id::text,
          v_uid, 'ship ' || s.shipment_number);
    end if;
  end loop;

  update public.shipments set status='SHIPPED', shipped_at=now()
    where id = p_id;
  perform public.write_audit_log('STATUS_CHANGE','SHIPMENT',
    p_id::text, jsonb_build_object('from','PREPARING'),
    jsonb_build_object('to','SHIPPED'));
end $$;

create or replace function public.deliver_shipment(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); s record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('sales.create')
       or public.has_permission('sales.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into s from public.shipments where id = p_id;
  if not found then raise exception 'NOT_FOUND'; end if;
  if s.status != 'SHIPPED' then raise exception 'INVALID_STATUS'; end if;
  update public.shipments set status='DELIVERED', delivered_at=now()
    where id = p_id;
  perform public.write_audit_log('STATUS_CHANGE','SHIPMENT',
    p_id::text, jsonb_build_object('from','SHIPPED'),
    jsonb_build_object('to','DELIVERED'));
end $$;

-- Payment: inserts + refreshes linked invoice payment_status
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

-- Balance helpers (derived, never stored)
create or replace function public.customer_balance(p_customer uuid)
returns table (total numeric, paid numeric, outstanding numeric)
language sql stable security definer set search_path = public as $$
  select
    coalesce((select sum(grand_total) from public.sales_invoices
      where customer_id = p_customer
        and status in ('APPROVED','PENDING_APPROVAL')), 0),
    coalesce((select sum(amount) from public.payments
      where customer_id = p_customer and status='COMPLETED'), 0),
    coalesce((select sum(grand_total) from public.sales_invoices
      where customer_id = p_customer
        and status in ('APPROVED','PENDING_APPROVAL')), 0)
    - coalesce((select sum(amount) from public.payments
      where customer_id = p_customer and status='COMPLETED'), 0);
$$;

create or replace function public.supplier_balance(p_supplier uuid)
returns table (total numeric, paid numeric, outstanding numeric)
language sql stable security definer set search_path = public as $$
  select
    coalesce((select sum(grand_total) from public.purchase_invoices
      where supplier_id = p_supplier
        and status in ('APPROVED','PENDING_APPROVAL')), 0),
    coalesce((select sum(amount) from public.payments
      where supplier_id = p_supplier and status='COMPLETED'), 0),
    coalesce((select sum(grand_total) from public.purchase_invoices
      where supplier_id = p_supplier
        and status in ('APPROVED','PENDING_APPROVAL')), 0)
    - coalesce((select sum(amount) from public.payments
      where supplier_id = p_supplier and status='COMPLETED'), 0);
$$;
