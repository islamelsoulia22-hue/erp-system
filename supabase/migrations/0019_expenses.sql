-- ============================================================
-- ERP Migration 0019: Expenses (المصروفات) phase 1
-- ============================================================
-- 1) صلاحيات المصروفات + منحها للأدوار.
-- 2) جدول تصنيفات المصروفات + البذرة الافتراضية.
-- 3) جدول المصروفات: دورة (مسودة → اعتماد → دفع) +
--    حقول المتكرر والأقساط (تستخدمها المرحلة 2).
-- 4) RPCs: submit / approve / reject / pay.
--
-- طريقة التطبيق: نفّذ الملف ده في Supabase Dashboard > SQL Editor.

-- ---------- 1) الصلاحيات ----------
insert into public.permissions (key, name_ar, module) values
  ('expenses.view', 'عرض مصروفات', 'expenses'),
  ('expenses.create', 'إنشاء مصروفات', 'expenses'),
  ('expenses.edit', 'تعديل مصروفات', 'expenses'),
  ('expenses.approve', 'اعتماد مصروفات', 'expenses')
on conflict (key) do nothing;

-- مدير الشركة: كل الصلاحيات الجديدة تلقائيا.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r
join public.permissions p on p.key in (
  'expenses.view','expenses.create','expenses.edit','expenses.approve')
where r.key = 'company_manager'
on conflict do nothing;

-- مديرو المبيعات والمشتريات: عرض وإنشاء وتعديل (بدون اعتماد).
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r
join public.permissions p on p.key in (
  'expenses.view','expenses.create','expenses.edit')
where r.key in ('sales_manager','purchase_manager')
on conflict do nothing;

-- ---------- 2) التصنيفات ----------
create table if not exists public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  name_ar text,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.expense_categories (code, name, name_ar) values
  ('ELEC', 'Electricity', 'كهرباء'),
  ('WATER', 'Water', 'مياه'),
  ('GAS', 'Gas', 'غاز'),
  ('NET', 'Internet', 'إنترنت'),
  ('PHONE', 'Phone', 'تليفون'),
  ('RENT', 'Rent', 'إيجار'),
  ('SAL', 'Salaries', 'رواتب'),
  ('INST', 'Installments', 'أقساط'),
  ('MAINT', 'Maintenance', 'صيانة'),
  ('FUEL', 'Fuel', 'وقود'),
  ('TRANS', 'Transport', 'نقل ومواصلات'),
  ('SHIP', 'Shipping', 'شحن'),
  ('OFFICE', 'Office supplies', 'أدوات مكتبية'),
  ('MKT', 'Marketing', 'تسويق وإعلانات'),
  ('SOFT', 'Software subscriptions', 'اشتراكات برامج'),
  ('HOST', 'Hosting', 'استضافة وسيرفرات'),
  ('TAX', 'Taxes and fees', 'ضرائب ورسوم'),
  ('INS', 'Insurance', 'تأمين'),
  ('BANK', 'Bank charges', 'مصروفات بنكية'),
  ('HOSP', 'Hospitality', 'ضيافة'),
  ('OPS', 'Operating purchases', 'مشتريات تشغيلية'),
  ('OTHER', 'Other', 'مصروفات أخرى')
on conflict (code) do nothing;

-- ---------- 3) المصروفات ----------
create sequence if not exists expense_seq start 1;

create or replace function public.generate_expense_number()
returns text language plpgsql as $$
declare n bigint; y text;
begin
  n := nextval('expense_seq');
  y := to_char(now(), 'YYYY');
  return 'EXP-' || y || '-' || lpad(n::text, 6, '0');
end $$;

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  expense_number text not null unique
    default public.generate_expense_number(),
  category_id uuid references public.expense_categories(id)
    on delete set null,
  title text not null,
  amount numeric(14,2) not null check (amount > 0),
  expense_date date not null default current_date,
  payment_method_id uuid references public.payment_methods(id),
  party_name text,
  reference_number text,
  warehouse_id uuid references public.warehouses(id) on delete set null,
  notes text,
  status text not null default 'DRAFT'
    check (status in ('DRAFT','PENDING_APPROVAL','APPROVED',
      'REJECTED','CANCELLED')),
  payment_status text not null default 'UNPAID'
    check (payment_status in ('UNPAID','PARTIAL','PAID')),
  paid_at timestamptz,
  paid_by uuid references public.profiles(id),
  -- متكرر (المرحلة 2): قالب يولد مستحقات.
  is_recurring boolean not null default false,
  frequency text
    check (frequency is null or frequency in
      ('WEEKLY','MONTHLY','QUARTERLY','YEARLY')),
  day_of_due int check (day_of_due is null or day_of_due between 1 and 31),
  start_date date,
  end_date date,
  parent_id uuid references public.expenses(id) on delete set null,
  next_due_date date,
  -- أقساط (المرحلة 2): مجموعة أقساط لالتزام واحد.
  group_id uuid,
  installment_no int,
  total_installments int,
  created_by uuid references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  rejected_by uuid references public.profiles(id),
  rejected_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_exp_status on public.expenses (status);
create index if not exists idx_exp_date on public.expenses (expense_date desc);
create index if not exists idx_exp_category on public.expenses (category_id);
create index if not exists idx_exp_created on public.expenses (created_at desc);
create index if not exists idx_exp_parent on public.expenses (parent_id);
create index if not exists idx_exp_group on public.expenses (group_id);

drop trigger if exists trg_exp_updated on public.expenses;
create trigger trg_exp_updated before update on public.expenses
  for each row execute function public.handle_updated_at();

drop trigger if exists trg_expcat_updated on public.expense_categories;
create trigger trg_expcat_updated before update on public.expense_categories
  for each row execute function public.handle_updated_at();

-- ---------- 4) RLS ----------
alter table public.expense_categories enable row level security;
alter table public.expenses enable row level security;

drop policy if exists "expcat_read" on public.expense_categories;
create policy "expcat_read" on public.expense_categories
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('expenses.view')
    or public.has_permission('expenses.create')
    or public.has_permission('expenses.edit')
    or public.has_permission('expenses.approve')));

-- إضافة تصنيف: المدير فقط (users.manage).
drop policy if exists "expcat_write" on public.expense_categories;
create policy "expcat_write" on public.expense_categories
  for all to authenticated
  using (public.has_permission('users.manage'))
  with check (public.has_permission('users.manage'));

drop policy if exists "exp_read" on public.expenses;
create policy "exp_read" on public.expenses
  for select to authenticated using (public.is_active_user() and (
    public.has_permission('expenses.view')
    or public.has_permission('expenses.create')
    or public.has_permission('expenses.edit')
    or public.has_permission('expenses.approve')));

drop policy if exists "exp_insert" on public.expenses;
create policy "exp_insert" on public.expenses
  for insert to authenticated
  with check (public.has_permission('expenses.create'));

drop policy if exists "exp_update" on public.expenses;
create policy "exp_update" on public.expenses
  for update to authenticated
  using (public.has_permission('expenses.create')
    or public.has_permission('expenses.edit'))
  with check (public.has_permission('expenses.create')
    or public.has_permission('expenses.edit'));

drop policy if exists "exp_delete" on public.expenses;
create policy "exp_delete" on public.expenses
  for delete to authenticated
  using (status = 'DRAFT' and (created_by = auth.uid()
    or public.has_permission('users.manage')));

-- ============================================================
-- RPCs: دورة المصروف (اعتماد ≠ دفع)
-- ============================================================
create or replace function public.submit_expense(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('expenses.create')
       or public.has_permission('expenses.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into v from public.expenses where id = p_id;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status not in ('DRAFT','REJECTED') then
    raise exception 'INVALID_STATUS';
  end if;
  if v.amount is null or v.amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  update public.expenses set status = 'PENDING_APPROVAL',
    rejected_by = null, rejected_at = null, rejection_reason = null
    where id = p_id;
  perform public.write_audit_log('STATUS_CHANGE', 'EXPENSE',
    p_id::text, jsonb_build_object('from', v.status),
    jsonb_build_object('to', 'PENDING_APPROVAL'));
end $$;

create or replace function public.approve_expense(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('expenses.approve') then
    raise exception 'NO_PERMISSION: expenses.approve required';
  end if;
  select * into v from public.expenses where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذا المصروف';
  end if;
  update public.expenses set status = 'APPROVED',
    approved_by = v_uid, approved_at = now() where id = p_id;
  perform public.write_audit_log('APPROVE', 'EXPENSE',
    p_id::text, jsonb_build_object('from', 'PENDING_APPROVAL'),
    jsonb_build_object('to', 'APPROVED'));
end $$;

create or replace function public.reject_expense(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not public.has_permission('expenses.approve') then
    raise exception 'NO_PERMISSION: expenses.approve required';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'REASON_REQUIRED';
  end if;
  select * into v from public.expenses where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status != 'PENDING_APPROVAL' then raise exception 'INVALID_STATUS'; end if;
  if v.created_by = v_uid then
    raise exception 'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذا المصروف';
  end if;
  update public.expenses set status = 'REJECTED',
    rejected_by = v_uid, rejected_at = now(),
    rejection_reason = p_reason where id = p_id;
  perform public.write_audit_log('REJECT', 'EXPENSE',
    p_id::text, jsonb_build_object('from', 'PENDING_APPROVAL'),
    jsonb_build_object('to', 'REJECTED', 'reason', p_reason));
end $$;

-- تسجيل الدفع (بعد الاعتماد): الاعتماد ≠ الدفع.
create or replace function public.pay_expense(
  p_id uuid, p_method_id uuid default null, p_reference text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v record;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_active_user() then raise exception 'INACTIVE_USER'; end if;
  if not (public.has_permission('expenses.create')
       or public.has_permission('expenses.edit')) then
    raise exception 'NO_PERMISSION';
  end if;
  select * into v from public.expenses where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status != 'APPROVED' then raise exception 'INVALID_STATUS'; end if;
  if v.payment_status = 'PAID' then raise exception 'ALREADY_PAID'; end if;
  update public.expenses set payment_status = 'PAID',
    paid_at = now(), paid_by = v_uid,
    payment_method_id = coalesce(p_method_id, payment_method_id),
    reference_number = coalesce(
      nullif(trim(p_reference), ''), reference_number)
    where id = p_id;
  perform public.write_audit_log('PAY', 'EXPENSE',
    p_id::text, jsonb_build_object('from', 'UNPAID'),
    jsonb_build_object('to', 'PAID', 'amount', v.amount));
end $$;
