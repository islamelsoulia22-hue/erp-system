-- ============================================================
-- ERP Migration 0008: Procurement + Approvals engine + Notifications
-- ============================================================

create sequence if not exists procurement_seq start 1;

create or replace function public.generate_procurement_number()
returns text language plpgsql as $$
declare n bigint; y text;
begin
  n := nextval('procurement_seq');
  y := to_char(now(), 'YYYY');
  return 'PR-' || y || '-' || lpad(n::text, 6, '0');
end $$;

-- ---------- Generic approvals engine (spec 32) ----------
create table if not exists public.approvals (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null
    check (entity_type in ('SALES_INVOICE','PURCHASE_INVOICE',
      'CUSTOMIZED_ITEM','MANUFACTURING_ORDER','PROCUREMENT_REQUEST',
      'CREDIT_SALE','STOCK_ADJUSTMENT')),
  entity_id text not null,
  requested_by uuid references public.profiles(id),
  approved_by uuid references public.profiles(id),
  status text not null default 'PENDING'
    check (status in ('PENDING','APPROVED','REJECTED','CANCELLED')),
  comment text,
  created_at timestamptz not null default now(),
  approved_at timestamptz
);
create index if not exists idx_approvals_entity
  on public.approvals (entity_type, entity_id);
create index if not exists idx_approvals_status
  on public.approvals (status);

-- ---------- Procurement requests ----------
create table if not exists public.procurement_requests (
  id uuid primary key default gen_random_uuid(),
  request_number text not null unique
    default public.generate_procurement_number(),
  supplier_id uuid references public.suppliers(id) on delete set null,
  sales_order_id uuid references public.sales_orders(id) on delete set null,
  warehouse_id uuid references public.warehouses(id) on delete restrict,
  status text not null default 'DRAFT'
    check (status in ('DRAFT','PENDING_APPROVAL','APPROVED',
      'PARTIALLY_RECEIVED','RECEIVED','REJECTED','CANCELLED')),
  reason text,
  requested_by uuid references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.procurement_items (
  id uuid primary key default gen_random_uuid(),
  procurement_id uuid not null references public.procurement_requests(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  requested_quantity numeric(14,3) not null check (requested_quantity > 0),
  available_quantity numeric(14,3) not null default 0,
  missing_quantity numeric(14,3) not null default 0,
  received_quantity numeric(14,3) not null default 0 check (received_quantity >= 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_pr_status on public.procurement_requests (status);
create index if not exists idx_pr_created on public.procurement_requests (created_at desc);
create index if not exists idx_pri_proc on public.procurement_items (procurement_id);

drop trigger if exists trg_pr_updated on public.procurement_requests;
create trigger trg_pr_updated before update on public.procurement_requests
  for each row execute function public.handle_updated_at();

-- ---------- Notifications ----------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  message text,
  entity_type text,
  entity_id text,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists idx_notif_user on public.notifications (user_id, is_read, created_at desc);

-- ---------- RLS ----------
alter table public.approvals enable row level security;
alter table public.procurement_requests enable row level security;
alter table public.procurement_items enable row level security;
alter table public.notifications enable row level security;

drop policy if exists "appr_read" on public.approvals;
create policy "appr_read" on public.approvals
  for select to authenticated using (public.is_active_user() and (
    requested_by = auth.uid()
    or public.has_permission('purchases.approve')
    or public.has_permission('sales.approve')
    or public.has_permission('users.manage')));

drop policy if exists "pr_read" on public.procurement_requests;
create policy "pr_read" on public.procurement_requests
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('purchases.view') or public.has_permission('purchases.create')
    or public.has_permission('purchases.edit') or public.has_permission('purchases.approve')
    or public.has_permission('sales.view') or public.has_permission('inventory.view')));
drop policy if exists "pr_insert" on public.procurement_requests;
create policy "pr_insert" on public.procurement_requests
  for insert to authenticated
  with check (public.has_permission('purchases.create') or public.has_permission('sales.create'));
drop policy if exists "pr_update" on public.procurement_requests;
create policy "pr_update" on public.procurement_requests
  for update to authenticated
  using (public.has_permission('purchases.create') or public.has_permission('purchases.edit'))
  with check (public.has_permission('purchases.create') or public.has_permission('purchases.edit'));
drop policy if exists "pr_delete" on public.procurement_requests;
create policy "pr_delete" on public.procurement_requests
  for delete to authenticated
  using (status = 'DRAFT' and (requested_by = auth.uid()
    or public.has_permission('purchases.create')));

drop policy if exists "pri_rw" on public.procurement_items;
create policy "pri_rw" on public.procurement_items
  for all to authenticated
  using (public.has_permission('purchases.create') or public.has_permission('purchases.edit')
    or public.has_permission('purchases.view') or public.has_permission('sales.create'))
  with check (public.has_permission('purchases.create') or public.has_permission('purchases.edit')
    or public.has_permission('sales.create'));

-- Notifications: users read/update own; managers read all; inserts via RPC (owner bypass) + allow self-notify
drop policy if exists "notif_read" on public.notifications;
create policy "notif_read" on public.notifications
  for select to authenticated
  using (user_id = auth.uid() or public.has_permission('users.manage'));
drop policy if exists "notif_insert" on public.notifications;
create policy "notif_insert" on public.notifications
  for insert to authenticated with check (public.is_active_user());
drop policy if exists "notif_update_own" on public.notifications;
create policy "notif_update_own" on public.notifications
  for update to authenticated
  using (user_id = auth.uid() or public.has_permission('users.manage'))
  with check (user_id = auth.uid() or public.has_permission('users.manage'));

-- ============================================================
-- Helpers
-- ============================================================
create or replace function public.create_notification(
  p_user_id uuid, p_type text, p_title text,
  p_message text default null,
  p_entity_type text default null, p_entity_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  insert into public.notifications
    (user_id, type, title, message, entity_type, entity_id)
    values (p_user_id, p_type, p_title, p_message, p_entity_type, p_entity_id)
    returning id into v_id;
  return v_id;
end $$;

-- Notify every active user holding a permission (e.g. approvers)
create or replace function public.notify_by_permission(
  p_permission text, p_type text, p_title text,
  p_message text default null,
  p_entity_type text default null, p_entity_id text default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_n int := 0; r record;
begin
  for r in
    select distinct ur.user_id from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions pm on pm.id = rp.permission_id
    join public.profiles p on p.id = ur.user_id
    where pm.key = p_permission and p.is_active = true
  loop
    -- skip notifying the actor themselves
    if r.user_id != auth.uid() then
      perform public.create_notification(r.user_id, p_type, p_title,
        p_message, p_entity_type, p_entity_id);
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $$;

-- Snapshot available/missing for one procurement in a warehouse
create or replace function public.refresh_procurement_availability(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_wh uuid; it record; av numeric(14,3);
begin
  select warehouse_id into v_wh from public.procurement_requests
    where id = p_id;
  if v_wh is null then return; end if;
  for it in select * from public.procurement_items
    where procurement_id = p_id loop
    av := 0;
    if it.product_id is not null then
      select coalesce(quantity - reserved_quantity, 0) into av
        from public.warehouse_stock
        where warehouse_id = v_wh and product_id = it.product_id;
      if not found then av := 0; end if;
    end if;
    update public.procurement_items set
      available_quantity = av,
      missing_quantity = greatest(0, it.requested_quantity - av)
      where id = it.id;
  end loop;
end $$;

-- ============================================================
-- RPCs
-- ============================================================
create or replace function public.submit_procurement(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('purchases.create')
       or public.has_permission('sales.create')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into v from public.procurement_requests where id = p_id;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status not in ('DRAFT','REJECTED') then raise exception 'INVALID_STATUS'; end if;
  if v.warehouse_id is null then raise exception 'WAREHOUSE_REQUIRED'; end if;
  if not exists (select 1 from public.procurement_items
      where procurement_id = p_id) then
    raise exception 'EMPTY_REQUEST';
  end if;
  perform public.refresh_procurement_availability(p_id);
  update public.procurement_requests set status='PENDING_APPROVAL'
    where id = p_id;
  insert into public.approvals
    (entity_type, entity_id, requested_by, status)
    values ('PROCUREMENT_REQUEST', p_id::text, v_uid, 'PENDING');
  perform public.write_audit_log('STATUS_CHANGE','PROCUREMENT_REQUEST',
    p_id::text, jsonb_build_object('from', v.status),
    jsonb_build_object('to','PENDING_APPROVAL'));
  perform public.notify_by_permission('purchases.approve', 'APPROVAL',
    'طلب توريد يحتاج اعتماد',
    'طلب ' || (select request_number from public.procurement_requests where id = p_id) || ' بانتظار الاعتماد.',
    'PROCUREMENT_REQUEST', p_id::text);
end $$;

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
  if v.requested_by = v_uid then
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
  if v.requested_by = v_uid then
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
  if v.requested_by is not null then
    perform public.create_notification(v.requested_by, 'APPROVAL',
      'تم رفض طلب التوريد',
      'طلب ' || v.request_number || ': ' || p_reason,
      'PROCUREMENT_REQUEST', p_id::text);
  end if;
end $$;

-- Receive against procurement (partial supported; PURCHASE movement)
create or replace function public.receive_procurement(
  p_id uuid, p_lines jsonb, p_notes text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
  ln jsonb; it record; v_take numeric;
  v_before numeric(14,3); v_after numeric(14,3);
  v_done boolean := true;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('purchases.create')
       or public.has_permission('purchases.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into v from public.procurement_requests
    where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status not in ('APPROVED','PARTIALLY_RECEIVED') then
    raise exception 'INVALID_STATUS';
  end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'EMPTY_LINES';
  end if;

  for ln in select * from jsonb_array_elements(p_lines) loop
    select * into it from public.procurement_items
      where id = (ln->>'item_id')::uuid
        and procurement_id = p_id for update;
    if not found then raise exception 'ITEM_NOT_FOUND'; end if;
    v_take := coalesce((ln->>'qty')::numeric, 0);
    if v_take <= 0 then raise exception 'INVALID_QTY'; end if;
    if it.received_quantity + v_take >
       it.requested_quantity then
      raise exception 'OVER_RECEIVE';
    end if;
    update public.procurement_items
      set received_quantity = received_quantity + v_take
      where id = it.id;
    if it.product_id is not null then
      insert into public.warehouse_stock (warehouse_id, product_id, quantity)
        values (v.warehouse_id, it.product_id, 0)
        on conflict (warehouse_id, product_id) do nothing;
      select quantity into v_before from public.warehouse_stock
        where warehouse_id = v.warehouse_id
          and product_id = it.product_id for update;
      update public.warehouse_stock
        set quantity = quantity + v_take
        where warehouse_id = v.warehouse_id
          and product_id = it.product_id
        returning quantity into v_after;
      insert into public.stock_movements
        (warehouse_id, product_id, movement_type, quantity,
         before_quantity, after_quantity, reference_type, reference_id,
         created_by, notes)
        values (v.warehouse_id, it.product_id, 'PURCHASE', v_take,
          v_before, v_after, 'PROCUREMENT_REQUEST', p_id::text,
          v_uid, p_notes);
    end if;
  end loop;

  if exists (select 1 from public.procurement_items
      where procurement_id = p_id
        and received_quantity < requested_quantity) then
    v_done := false;
  end if;
  update public.procurement_requests
    set status = case when v_done then 'RECEIVED'::text
                      else 'PARTIALLY_RECEIVED'::text end
    where id = p_id;
  perform public.write_audit_log('RECEIVE','PROCUREMENT_REQUEST',
    p_id::text, null,
    jsonb_build_object('lines', p_lines,
      'status', case when v_done then 'RECEIVED'
                     else 'PARTIALLY_RECEIVED' end));
  if v.requested_by is not null then
    perform public.create_notification(v.requested_by, 'RECEIVE',
      'تم استلام طلب توريد',
      'طلب ' || v.request_number || ' وصل ' ||
        case when v_done then 'بالكامل.' else 'جزئيا.' end,
      'PROCUREMENT_REQUEST', p_id::text);
  end if;
end $$;
