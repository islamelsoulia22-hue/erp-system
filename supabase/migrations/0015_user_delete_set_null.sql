-- ============================================================
-- ERP Migration 0015: allow deleting users with history.
-- All "actor" references to profiles (created_by, approved_by,
-- rejected_by, requested_by, assigned_by, uploaded_by, audit user_id)
-- become ON DELETE SET NULL instead of blocking the delete.
-- History rows stay; only the actor link is cleared.
-- (user_roles.user_id, warehouse_users, notifications already cascade.)
-- ============================================================

do $$
declare
  r record;
begin
  for r in
    select con.conname as cname,
           tbl.relname as tname,
           col.attname as ccol
      from pg_constraint con
      join pg_class tbl on tbl.oid = con.conrelid
      join pg_attribute col
        on col.attrelid = con.conrelid
       and col.attnum = con.conkey[1]
      join pg_class ref on ref.oid = con.confrelid
     where con.contype = 'f'
       and tbl.relnamespace = 'public'::regnamespace
       and ref.relname = 'profiles'
       and con.confdeltype <> 'n'  -- not already SET NULL
       and not (tbl.relname in ('user_roles', 'warehouse_users',
                                'notifications')
                and col.attname = 'user_id')
  loop
    execute format(
      'alter table public.%I drop constraint if exists %I',
      r.tname, r.cname);
    execute format(
      'alter table public.%I add constraint %I '
      'foreign key (%I) references public.profiles(id) '
      'on delete set null',
      r.tname, r.cname, r.ccol);
  end loop;
end $$;
