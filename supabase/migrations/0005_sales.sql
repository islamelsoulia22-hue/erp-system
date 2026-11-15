-- ============================================================
-- ERP Migration 0005: Sales (payment methods, orders, invoices)
-- Drafts via RLS direct writes; submit/approve/reject via RPC only.
-- Approve reserves stock (no deduction yet; shipping deducts later).
-- ============================================================

-- ---------- Minimal payment methods (extended in payments phase) ----------
create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  name_ar text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.payment_methods (code, name, name_ar) values
  ('CASH', 'Cash', 'كاش'),
  ('INSTAPAY', 'Instapay', 'انستاباي'),
  ('VODAFONE_CASH', 'Vodafone Cash', 'فودافون كاش'),
  ('BANK_TRANSFER', 'Bank Transfer', 'تحويل بنكي'),
  ('SHIPPING_COMPANY', 'Shipping Company', 'شركة شحن'),
  ('CREDIT', 'Credit', 'آجل')
on conflict (code) do nothing;

-- ---------- Number sequences (concurrency-safe) ----------
create sequence if not exists sales_order_seq start 1;
create sequence if not exists sales_invoice_seq start 1;

create or replace function public.generate_sales_order_number()
returns text language plpgsql as $$
declare n bigint; y text;
begin
  n := nextval('sales_order_seq');
  y := to_char(now(), 'YYYY');
  return 'SO-' || y || '-' || lpad(n::text, 6, '0');
end $$;

create or replace function public.generate_sales_invoice_number()
returns text language plpgsql as $$
declare n bigint; y text;
begin
  n := nextval('sales_invoice_seq');
  y := to_char(now(), 'YYYY');
  return 'SAL-' || y || '-' || lpad(n::text, 6, '0');
end $$;

-- ---------- Sales orders ----------
create table if not exists public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique default public.generate_sales_order_number(),
  reference_number text,
  customer_id uuid references public.customers(id) on delete set null,
  customer_name_snapshot text,
  customer_phone_snapshot text,
  customer_address_snapshot text,
  warehouse_id uuid references public.warehouses(id) on delete restrict,
  status text not null default 'DRAFT'
    check (status in ('DRAFT','CONFIRMED','PROCESSING','READY','DELIVERED','CANCELLED')),
  subtotal numeric(14,2) not null default 0,
  discount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  payment_method_id uuid references public.payment_methods(id),
  payment_status text not null default 'UNPAID'
    check (payment_status in ('UNPAID','PARTIAL','PAID')),
  delivery_method text not null default 'OFFICE_PICKUP'
    check (delivery_method in ('OFFICE_PICKUP','SHIPPING')),
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sales_order_items (
  id uuid primary key default gen_random_uuid(),
  sales_order_id uuid not null references public.sales_orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  item_type text not null default 'STANDARD'
    check (item_type in ('STANDARD','CUSTOMIZED','MANUFACTURED')),
  item_name text not null,
  sku text,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  discount numeric(14,2) not null default 0 check (discount >= 0),
  tax_rate numeric(5,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  notes text
);

-- ---------- Sales invoices ----------
create table if not exists public.sales_invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique default public.generate_sales_invoice_number(),
  reference_number text,
  sales_order_id uuid references public.sales_orders(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  customer_name_snapshot text,
  customer_phone_snapshot text,
  customer_address_snapshot text,
  customer_tax_number_snapshot text,
  warehouse_id uuid references public.warehouses(id) on delete restrict,
  status text not null default 'DRAFT'
    check (status in ('DRAFT','PENDING_APPROVAL','APPROVED','REJECTED','CANCELLED')),
  subtotal numeric(14,2) not null default 0,
  discount numeric(14,2) not null default 0,
  taxable_amount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  payment_method_id uuid references public.payment_methods(id),
  payment_status text not null default 'UNPAID'
    check (payment_status in ('UNPAID','PARTIAL','PAID')),
  delivery_method text not null default 'OFFICE_PICKUP'
    check (delivery_method in ('OFFICE_PICKUP','SHIPPING')),
  credit_period_days int,
  due_date date,
  credit_reason text,
  created_by uuid references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  rejected_by uuid references public.profiles(id),
  rejected_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sales_invoice_items (
  id uuid primary key default gen_random_uuid(),
  sales_invoice_id uuid not null references public.sales_invoices(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  item_type text not null default 'STANDARD'
    check (item_type in ('STANDARD','CUSTOMIZED','MANUFACTURED')),
  item_name text not null,
  sku text,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  discount numeric(14,2) not null default 0 check (discount >= 0),
  tax_rate numeric(5,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  customized_item_id uuid
);

-- ---------- Indexes ----------
create index if not exists idx_so_number on public.sales_orders (order_number);
create index if not exists idx_so_customer on public.sales_orders (customer_id);
create index if not exists idx_so_status on public.sales_orders (status);
create index if not exists idx_so_created on public.sales_orders (created_at desc);
create index if not exists idx_soi_order on public.sales_order_items (sales_order_id);
create index if not exists idx_si_number on public.sales_invoices (invoice_number);
create index if not exists idx_si_ref on public.sales_invoices (reference_number);
create index if not exists idx_si_customer on public.sales_invoices (customer_id);
create index if not exists idx_si_status on public.sales_invoices (status);
create index if not exists idx_si_created on public.sales_invoices (created_at desc);
create index if not exists idx_si_warehouse on public.sales_invoices (warehouse_id);
create index if not exists idx_sii_invoice on public.sales_invoice_items (sales_invoice_id);
create index if not exists idx_sii_product on public.sales_invoice_items (product_id);

-- ---------- updated_at ----------
drop trigger if exists trg_so_updated on public.sales_orders;
create trigger trg_so_updated before update on public.sales_orders
  for each row execute function public.handle_updated_at();
drop trigger if exists trg_si_updated on public.sales_invoices;
create trigger trg_si_updated before update on public.sales_invoices
  for each row execute function public.handle_updated_at();

-- ---------- RLS ----------
alter table public.payment_methods enable row level security;
alter table public.sales_orders enable row level security;
alter table public.sales_order_items enable row level security;
alter table public.sales_invoices enable row level security;
alter table public.sales_invoice_items enable row level security;

drop policy if exists "pm_read" on public.payment_methods;
create policy "pm_read" on public.payment_methods
  for select to authenticated using (public.is_active_user());

-- Orders: read sales.view, write sales.create/edit, delete draft
drop policy if exists "so_read" on public.sales_orders;
create policy "so_read" on public.sales_orders
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('sales.view') or public.has_permission('sales.create')
    or public.has_permission('sales.edit') or public.has_permission('sales.approve')));
drop policy if exists "so_insert" on public.sales_orders;
create policy "so_insert" on public.sales_orders
  for insert to authenticated with check (public.has_permission('sales.create'));
drop policy if exists "so_update" on public.sales_orders;
create policy "so_update" on public.sales_orders
  for update to authenticated
  using (public.has_permission('sales.create') or public.has_permission('sales.edit'))
  with check (public.has_permission('sales.create') or public.has_permission('sales.edit'));
drop policy if exists "so_delete" on public.sales_orders;
create policy "so_delete" on public.sales_orders
  for delete to authenticated
  using (status = 'DRAFT' and (created_by = auth.uid()
    or public.has_permission('sales.delete')));

drop policy if exists "soi_read" on public.sales_order_items;
create policy "soi_read" on public.sales_order_items
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('sales.view') or public.has_permission('sales.create')
    or public.has_permission('sales.edit') or public.has_permission('sales.approve')));
drop policy if exists "soi_write" on public.sales_order_items;
create policy "soi_write" on public.sales_order_items
  for all to authenticated
  using (public.has_permission('sales.create') or public.has_permission('sales.edit'))
  with check (public.has_permission('sales.create') or public.has_permission('sales.edit'));

-- Invoices: same shape; status transitions enforced in RPC, not RLS
drop policy if exists "si_read" on public.sales_invoices;
create policy "si_read" on public.sales_invoices
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('sales.view') or public.has_permission('sales.create')
    or public.has_permission('sales.edit') or public.has_permission('sales.approve')));
drop policy if exists "si_insert" on public.sales_invoices;
create policy "si_insert" on public.sales_invoices
  for insert to authenticated with check (public.has_permission('sales.create'));
drop policy if exists "si_update" on public.sales_invoices;
create policy "si_update" on public.sales_invoices
  for update to authenticated
  using (public.has_permission('sales.create') or public.has_permission('sales.edit'))
  with check (public.has_permission('sales.create') or public.has_permission('sales.edit'));
drop policy if exists "si_delete" on public.sales_invoices;
create policy "si_delete" on public.sales_invoices
  for delete to authenticated
  using (status = 'DRAFT' and (created_by = auth.uid()
    or public.has_permission('sales.delete')));

drop policy if exists "sii_read" on public.sales_invoice_items;
create policy "sii_read" on public.sales_invoice_items
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('sales.view') or public.has_permission('sales.create')
    or public.has_permission('sales.edit') or public.has_permission('sales.approve')));
drop policy if exists "sii_write" on public.sales_invoice_items;
create policy "sii_write" on public.sales_invoice_items
  for all to authenticated
  using (public.has_permission('sales.create') or public.has_permission('sales.edit'))
  with check (public.has_permission('sales.create') or public.has_permission('sales.edit'));

-- ============================================================
-- Helpers: recalc totals server-side (single source of truth)
-- ============================================================
create or replace function public.recalc_sales_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_sub numeric(14,2) := 0; v_disc numeric(14,2) := 0;
  v_tax numeric(14,2) := 0; v_total numeric(14,2) := 0;
  r record;
begin
  for r in select * from public.sales_invoice_items
    where sales_invoice_id = p_invoice loop
    declare line numeric(14,2);
      t numeric(14,2);
    begin
      line := greatest(0, r.quantity * r.unit_price - coalesce(r.discount, 0));
      t := round(line * coalesce(r.tax_rate, 0) / 100, 2);
      update public.sales_invoice_items
        set tax_amount = t, total = line + t where id = r.id;
      v_sub := v_sub + (r.quantity * r.unit_price);
      v_disc := v_disc + coalesce(r.discount, 0);
      v_tax := v_tax + t;
      v_total := v_total + line + t;
    end;
  end loop;
  update public.sales_invoices
    set subtotal = v_sub, discount = v_disc,
        taxable_amount = greatest(0, v_sub - v_disc),
        tax_amount = v_tax, grand_total = v_total
    where id = p_invoice;
end $$;

-- Submit DRAFT/REJECTED -> PENDING (snapshot customer, recalc)
create or replace function public.submit_sales_invoice(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record; c record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('sales.create')
       or public.has_permission('sales.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into v from public.sales_invoices where id = p_invoice;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  if v.status not in ('DRAFT','REJECTED') then
    raise exception 'INVALID_STATUS';
  end if;
  if v.warehouse_id is null then raise exception 'WAREHOUSE_REQUIRED'; end if;
  if not exists (select 1 from public.sales_invoice_items
      where sales_invoice_id = p_invoice) then
    raise exception 'EMPTY_INVOICE';
  end if;
  -- Snapshot known customer
  if v.customer_id is not null then
    select * into c from public.customers where id = v.customer_id;
    if found then
      update public.sales_invoices set
        customer_name_snapshot = c.name,
        customer_phone_snapshot = c.phone,
        customer_tax_number_snapshot = c.tax_number
        where id = p_invoice;
    end if;
  elsif v.customer_name_snapshot is null
     or length(trim(v.customer_name_snapshot)) = 0 then
    raise exception 'CUSTOMER_REQUIRED';
  end if;
  -- Credit sales require reason (manager approves later)
  if exists (select 1 from public.payment_methods pm
      join public.sales_invoices si on si.payment_method_id = pm.id
      where si.id = p_invoice and pm.code = 'CREDIT')
    and (v.credit_reason is null or length(trim(v.credit_reason)) = 0) then
    raise exception 'CREDIT_REASON_REQUIRED';
  end if;
  perform public.recalc_sales_invoice(p_invoice);
  update public.sales_invoices
    set status = 'PENDING_APPROVAL',
        rejected_by = null, rejected_at = null, rejection_reason = null
    where id = p_invoice;
  perform public.write_audit_log('STATUS_CHANGE', 'SALES_INVOICE',
    p_invoice::text, jsonb_build_object('from', v.status),
    jsonb_build_object('to', 'PENDING_APPROVAL'));
end $$;

-- Approve: permission + not-self + stock reserve in one transaction
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
  if v.created_by = v_uid then
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
  if v.created_by = v_uid then
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
