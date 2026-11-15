-- ============================================================
-- ERP Migration 0030: Serial sales registry + verification.
-- الطابعات (إلكترونيات) بسيريال: عند البيع نسجل كل سيريال
-- (العميل + الفاتورة + السعر + التكلفة)، وبعدين أي حد معاه
-- صلاحية التحقق يدخل السيريال فيظهر ملف العميل كامل
-- (الجهاز، العميل، الفاتورة، تاريخ وسعر البيع، الربح).
-- الصلاحية: serials.verify (مدير الشركة + مدير المبيعات،
-- والمدير يسندها/يشيلها لأي حد من شاشة المستخدمين).
-- ============================================================

-- ---------- 1) الصلاحية + منحها ----------
insert into public.permissions (key, name_ar, module) values
  ('serials.verify', 'تحقق من السيريال', 'sales')
on conflict (key) do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r
join public.permissions p on p.key = 'serials.verify'
where r.key in ('company_manager', 'sales_manager')
on conflict do nothing;

-- ---------- 2) سجل بيع السيريالات ----------
create table if not exists public.serial_sales (
  id uuid primary key default gen_random_uuid(),
  serial text not null,
  product_id uuid references public.products(id) on delete set null,
  product_name_snapshot text,
  customer_id uuid references public.customers(id) on delete set null,
  customer_name_snapshot text,
  customer_phone_snapshot text,
  sales_invoice_id uuid references public.sales_invoices(id) on delete set null,
  sales_invoice_item_id uuid references public.sales_invoice_items(id)
    on delete set null,
  unit_price numeric(14,2) not null default 0,
  unit_cost numeric(14,2) not null default 0,
  sold_at timestamptz not null default now(),
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint uq_serial_sales_serial unique (serial)
);

create index if not exists idx_serial_sales_serial
  on public.serial_sales (serial);
create index if not exists idx_serial_sales_customer
  on public.serial_sales (customer_id);
create index if not exists idx_serial_sales_invoice
  on public.serial_sales (sales_invoice_id);

alter table public.serial_sales enable row level security;

drop policy if exists "ss_read" on public.serial_sales;
create policy "ss_read" on public.serial_sales
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('serials.verify') or
    public.has_permission('users.manage')));
drop policy if exists "ss_insert" on public.serial_sales;
create policy "ss_insert" on public.serial_sales
  for insert to authenticated
  with check (
    public.has_permission('sales.create') or
    public.has_permission('sales.edit'));
drop policy if exists "ss_delete" on public.serial_sales;
create policy "ss_delete" on public.serial_sales
  for delete to authenticated
  using (public.has_permission('users.manage'));

-- ---------- 3) تسجيل بيع سيريال ----------
-- ياخد سطر فاتورة مبيعات معتمدة + السيريال، ويملأ العميل
-- والسعر والتكلفة تلقائيا، ويشيل السيريال من مخزون السيريالات
-- لو موجود (اتباع = خرج من المخزن).
create or replace function public.register_serial_sale(
  p_item_id uuid, p_serial text, p_notes text default null)
returns uuid language plpgsql security definer
set search_path = public as $$
declare v_uid uuid := auth.uid();
  it record; inv record; v_serial text; v_id uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('sales.create')
       or public.has_permission('sales.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  v_serial := trim(coalesce(p_serial, ''));
  if v_serial = '' then raise exception 'SERIAL_REQUIRED'; end if;
  select * into it from public.sales_invoice_items
    where id = p_item_id;
  if not found then raise exception 'ITEM_NOT_FOUND'; end if;
  select * into inv from public.sales_invoices
    where id = it.sales_invoice_id;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  if inv.status != 'APPROVED' then
    raise exception 'INVOICE_NOT_APPROVED: سجل السيريالات بعد اعتماد الفاتورة';
  end if;
  if exists (select 1 from public.serial_sales
      where serial = v_serial) then
    raise exception 'SERIAL_ALREADY_SOLD: السيريال ده متسجل بيع قبل كده';
  end if;
  insert into public.serial_sales
    (serial, product_id, product_name_snapshot,
     customer_id, customer_name_snapshot, customer_phone_snapshot,
     sales_invoice_id, sales_invoice_item_id,
     unit_price, unit_cost, notes, created_by)
    values
    (v_serial, it.product_id, it.item_name,
     inv.customer_id, inv.customer_name_snapshot,
     inv.customer_phone_snapshot,
     inv.id, it.id,
     it.unit_price, coalesce(it.unit_cost, 0), p_notes, v_uid)
    returning id into v_id;
  -- شيله من مخزون السيريالات لو موجود (اتباع وخرج).
  delete from public.product_serials
    where product_id = it.product_id and serial = v_serial;
  perform public.write_audit_log('CREATE', 'SERIAL_SALE',
    v_id::text, null,
    jsonb_build_object('serial', v_serial, 'invoice', inv.invoice_number));
  return v_id;
end $$;

-- ---------- 4) التحقق من السيريال: الملف الكامل ----------
-- (صلاحية serials.verify — المدير والمبيعات فقط).
create or replace function public.verify_serial(p_serial text)
returns table (
  serial text, product_id uuid, product_name text,
  brand text, model text,
  customer_id uuid, customer_name text, customer_phone text,
  sales_invoice_id uuid, invoice_number text, sold_at timestamptz,
  unit_price numeric, unit_cost numeric, profit numeric
)
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('serials.verify')
       or public.has_permission('users.manage')) then
    raise exception 'NO_PERMISSION: serials.verify required';
  end if;
  return query
    select s.serial, s.product_id,
           coalesce(s.product_name_snapshot, p.name) as product_name,
           p.brand, p.model,
           s.customer_id,
           coalesce(s.customer_name_snapshot, c.name) as customer_name,
           coalesce(s.customer_phone_snapshot, c.phone) as customer_phone,
           s.sales_invoice_id, si.invoice_number, s.sold_at,
           s.unit_price, s.unit_cost,
           (s.unit_price - s.unit_cost) as profit
      from public.serial_sales s
      left join public.products p on p.id = s.product_id
      left join public.customers c on c.id = s.customer_id
      left join public.sales_invoices si on si.id = s.sales_invoice_id
     where s.serial = trim(p_serial)
     order by s.sold_at desc
     limit 1;
end $$;
