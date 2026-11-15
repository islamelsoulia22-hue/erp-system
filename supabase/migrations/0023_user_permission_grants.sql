-- ============================================================
-- ERP Migration 0023: Per-user permission grants (منح فردي)
-- ============================================================
-- المشكلة: شيت "الصفحات الظاهرة" كان إخفاء فقط (UX).
-- تشغيل سويتش ON لمستخدم دوره مفهوش الصلاحية لم يكن يظهر الصفحة.
-- الحل: جدول منح فردي + has_permission يشوفه + view يجمعه.
-- الفعال بعد التطبيق = (صلاحية الدور OR منح فردي) AND NOT مخفي.
--
-- طريقة التطبيق: نفّذ الملف ده في Supabase Dashboard > SQL Editor.

create table if not exists public.user_permission_grants (
  user_id uuid not null references public.profiles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  granted_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (user_id, permission_id)
);

create index if not exists idx_upg_user
  on public.user_permission_grants (user_id);

alter table public.user_permission_grants enable row level security;

-- قراءة: المستخدم نفسه أو المدير.
drop policy if exists "upg_read" on public.user_permission_grants;
create policy "upg_read" on public.user_permission_grants
  for select to authenticated
  using (user_id = auth.uid()
    or public.has_permission('users.manage'));

-- كتابة: المدير فقط.
drop policy if exists "upg_write" on public.user_permission_grants;
create policy "upg_write" on public.user_permission_grants
  for all to authenticated
  using (public.has_permission('users.manage'))
  with check (public.has_permission('users.manage'));

-- ---------- has_permission يشمل المنح الفردي ----------
-- السبب: RLS/RPC هو الحماية الحقيقية، لازم يشوف المنح الفردي
-- وإلا الصفحة هتظهر في القائمة بس الداتا هتترفض.
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
  ) or exists (
    select 1
    from public.user_permission_grants g
    join public.permissions pm on pm.id = g.permission_id
    join public.profiles p on p.id = g.user_id
    where g.user_id = auth.uid()
      and pm.key = p_key
      and p.is_active = true
  );
$$;

-- ---------- view يجمع دور + فردي ----------
-- role_key = null يعني منح فردي (loadMyRoles يتجاهله).
drop view if exists public.user_permissions;
create view public.user_permissions as
select
  ur.user_id,
  pm.key as permission_key,
  r.key as role_key
from public.user_roles ur
join public.roles r on r.id = ur.role_id
join public.role_permissions rp on rp.role_id = r.id
join public.permissions pm on pm.id = rp.permission_id
join public.profiles p on p.id = ur.user_id
where p.is_active = true
union
select
  g.user_id,
  pm.key as permission_key,
  null::text as role_key
from public.user_permission_grants g
join public.permissions pm on pm.id = g.permission_id
join public.profiles p on p.id = g.user_id
where p.is_active = true;
