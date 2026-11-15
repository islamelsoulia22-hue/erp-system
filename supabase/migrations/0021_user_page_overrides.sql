-- ============================================================
-- ERP Migration 0021: Per-user page visibility (إظهار/إخفاء الصفحات)
-- ============================================================
-- المدير يخفي صفحات/أقسام عن مستخدم معين من شاشة المستخدمين.
-- ملاحظة أمان: الإخفاء للعرض فقط (UX) — الصلاحيات الحقيقية
-- للأدوار عبر RLS/RPC كما هي. لا يمكن إظهار صفحة تتجاوز
-- صلاحيات دور المستخدم (الفاعل = صلاحية الدور AND NOT مخفي).
--
-- طريقة التطبيق: نفّذ الملف ده في Supabase Dashboard > SQL Editor.

create table if not exists public.user_page_overrides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  route text not null,
  visible boolean not null default true,
  created_at timestamptz not null default now(),
  unique (user_id, route)
);

create index if not exists idx_upo_user
  on public.user_page_overrides (user_id);

alter table public.user_page_overrides enable row level security;

-- قراءة: المستخدم نفسه أو المدير.
drop policy if exists "upo_read" on public.user_page_overrides;
create policy "upo_read" on public.user_page_overrides
  for select to authenticated
  using (user_id = auth.uid()
    or public.has_permission('users.manage'));

-- كتابة: المدير فقط.
drop policy if exists "upo_write" on public.user_page_overrides;
create policy "upo_write" on public.user_page_overrides
  for all to authenticated
  using (public.has_permission('users.manage'))
  with check (public.has_permission('users.manage'));
