-- ============================================================
-- ERP Migration 0031: case-insensitive serial verify.
-- البحث عن السيريال يتجاهل حالة الحروف والمسافات الزيادة،
-- عشان "ABC123" تلاقي "abc123" بدل "غير موجود".
-- ============================================================

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
     where lower(s.serial) = lower(trim(p_serial))
     order by s.sold_at desc
     limit 1;
end $$;
