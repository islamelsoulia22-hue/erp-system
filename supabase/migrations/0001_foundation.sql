-- ============================================================
-- ERP Foundation Migration 0001
-- Profiles + Roles + Permissions + Audit + RLS + Seed
-- Run in Supabase SQL Editor. Idempotent where possible.
-- ============================================================

-- Extensions
create extension if not exists "pgcrypto";

-- ---------- Helper: updated_at ----------
create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------- Tables ----------
create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name_ar text not null,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name_ar text not null,
  module text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  email text,
  avatar_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  assigned_by uuid references public.profiles(id),
  assigned_at timestamptz not null default now(),
  primary key (user_id, role_id)
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id),
  action text not null,
  entity_type text not null,
  entity_id text,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

-- ---------- Indexes ----------
create index if not exists idx_profiles_email on public.profiles(email);
create index if not exists idx_profiles_is_active on public.profiles(is_active);
create index if not exists idx_user_roles_user on public.user_roles(user_id);
create index if not exists idx_user_roles_role on public.user_roles(role_id);
create index if not exists idx_role_permissions_role on public.role_permissions(role_id);
create index if not exists idx_audit_entity on public.audit_logs(entity_type, entity_id);
create index if not exists idx_audit_created on public.audit_logs(created_at desc);
create index if not exists idx_audit_user on public.audit_logs(user_id);

-- ---------- Triggers ----------
drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.handle_updated_at();

-- Auto-create profile on signup (SECURITY DEFINER, bypasses RLS safely)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Auth helpers (used by RLS + RPC) ----------
create or replace function public.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true
  );
$$;

create or replace function public.has_role(p_role_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    join public.profiles p on p.id = ur.user_id
    where ur.user_id = auth.uid()
      and r.key = p_role_key
      and p.is_active = true
  );
$$;

create or replace function public.has_permission(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions pm on pm.id = rp.permission_id
    join public.profiles p on p.id = ur.user_id
    where ur.user_id = auth.uid()
      and pm.key = p_key
      and p.is_active = true
  );
$$;

-- Central audit writer (SECURITY DEFINER, called from RPCs)
create or replace function public.write_audit_log(
  p_action text,
  p_entity_type text,
  p_entity_id text,
  p_old jsonb default null,
  p_new jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  insert into public.audit_logs (user_id, action, entity_type, entity_id, old_data, new_data)
  values (auth.uid(), p_action, p_entity_type, p_entity_id, p_old, p_new)
  returning id into v_id;
  return v_id;
end $$;

-- Convenient view: flat user -> permission keys (for Flutter UX only)
create or replace view public.user_permissions as
select
  ur.user_id,
  pm.key as permission_key,
  r.key as role_key
from public.user_roles ur
join public.roles r on r.id = ur.role_id
join public.role_permissions rp on rp.role_id = r.id
join public.permissions pm on pm.id = rp.permission_id
join public.profiles p on p.id = ur.user_id
where p.is_active = true;

-- ---------- RLS ----------
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.audit_logs enable row level security;

-- Roles / permissions: readable by any active user, writable only by users.manage
drop policy if exists "roles_read" on public.roles;
create policy "roles_read" on public.roles
  for select to authenticated using (public.is_active_user());

drop policy if exists "roles_write" on public.roles;
create policy "roles_write" on public.roles
  for all to authenticated
  using (public.has_permission('users.manage'))
  with check (public.has_permission('users.manage'));

drop policy if exists "permissions_read" on public.permissions;
create policy "permissions_read" on public.permissions
  for select to authenticated using (public.is_active_user());

drop policy if exists "permissions_write" on public.permissions;
create policy "permissions_write" on public.permissions
  for all to authenticated
  using (public.has_permission('users.manage'))
  with check (public.has_permission('users.manage'));

drop policy if exists "role_permissions_read" on public.role_permissions;
create policy "role_permissions_read" on public.role_permissions
  for select to authenticated using (public.is_active_user());

drop policy if exists "role_permissions_write" on public.role_permissions;
create policy "role_permissions_write" on public.role_permissions
  for all to authenticated
  using (public.has_permission('users.manage'))
  with check (public.has_permission('users.manage'));

-- Profiles: user reads/updates own row; manager reads all + manages
drop policy if exists "profiles_read_own" on public.profiles;
create policy "profiles_read_own" on public.profiles
  for select to authenticated using (id = auth.uid() or public.has_permission('users.manage'));

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.has_permission('users.manage'))
  with check (id = auth.uid() or public.has_permission('users.manage'));

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (id = auth.uid());

-- user_roles: readable by self or manager; writable only by manager
drop policy if exists "user_roles_read" on public.user_roles;
create policy "user_roles_read" on public.user_roles
  for select to authenticated
  using (user_id = auth.uid() or public.has_permission('users.manage'));

drop policy if exists "user_roles_write" on public.user_roles;
create policy "user_roles_write" on public.user_roles
  for all to authenticated
  using (public.has_permission('users.manage'))
  with check (public.has_permission('users.manage'));

-- audit_logs: insert via RPC (service path uses write_audit_log);
-- allow authenticated insert of own actions, select only for managers/auditors
drop policy if exists "audit_insert" on public.audit_logs;
create policy "audit_insert" on public.audit_logs
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "audit_read" on public.audit_logs;
create policy "audit_read" on public.audit_logs
  for select to authenticated
  using (public.has_permission('users.manage') or public.has_permission('reports.view'));

-- ---------- Seed: roles ----------
insert into public.roles (key, name_ar) values
  ('company_manager', 'مدير الشركة'),
  ('sales_manager', 'مدير المبيعات'),
  ('purchase_manager', 'مدير المشتريات')
on conflict (key) do nothing;

-- ---------- Seed: permissions ----------
insert into public.permissions (key, name_ar, module) values
  ('sales.create', 'إنشاء مبيعات', 'sales'),
  ('sales.edit', 'تعديل مبيعات', 'sales'),
  ('sales.view', 'عرض مبيعات', 'sales'),
  ('sales.approve', 'اعتماد مبيعات', 'sales'),
  ('sales.delete', 'حذف مبيعات', 'sales'),
  ('purchases.create', 'إنشاء مشتريات', 'purchases'),
  ('purchases.edit', 'تعديل مشتريات', 'purchases'),
  ('purchases.view', 'عرض مشتريات', 'purchases'),
  ('purchases.approve', 'اعتماد مشتريات', 'purchases'),
  ('products.create', 'إنشاء منتجات', 'products'),
  ('products.edit', 'تعديل منتجات', 'products'),
  ('products.view', 'عرض منتجات', 'products'),
  ('inventory.view', 'عرض مخزون', 'inventory'),
  ('inventory.adjust', 'تسوية مخزون', 'inventory'),
  ('inventory.transfer', 'تحويل مخزون', 'inventory'),
  ('customers.create', 'إنشاء عملاء', 'customers'),
  ('customers.edit', 'تعديل عملاء', 'customers'),
  ('customers.view', 'عرض عملاء', 'customers'),
  ('suppliers.create', 'إنشاء موردين', 'suppliers'),
  ('suppliers.edit', 'تعديل موردين', 'suppliers'),
  ('suppliers.view', 'عرض موردين', 'suppliers'),
  ('users.manage', 'إدارة المستخدمين', 'users'),
  ('warehouses.manage', 'إدارة المخازن', 'warehouses'),
  ('reports.view', 'عرض التقارير', 'reports')
on conflict (key) do nothing;

-- ---------- Seed: role_permissions ----------
-- Company manager: everything
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.key = 'company_manager'
on conflict do nothing;

-- Sales manager subset
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r join public.permissions p on p.key in (
  'sales.create','sales.edit','sales.view',
  'products.view',
  'inventory.view',
  'customers.create','customers.edit','customers.view'
)
where r.key = 'sales_manager'
on conflict do nothing;

-- Purchase manager subset
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r join public.permissions p on p.key in (
  'purchases.create','purchases.edit','purchases.view',
  'products.view',
  'inventory.view',
  'suppliers.create','suppliers.edit','suppliers.view'
)
where r.key = 'purchase_manager'
on conflict do nothing;
