-- ============================================================
-- ERP Migration 0034: stock alerts (minimum + out of stock).
-- أول ما الصنف يوصل للحد الأدنى: تنبيه تلقائي للمدير (طلب
-- بضاعة) + إشعار، والمدير يقول "عارف تمام" (إقرار).
-- لو الصنف نفذ (صفر): يتسجل تلقائيا في النواقص + إشعار برضو.
-- الفحص شغال على أي حركة مخزون (ترigger) بدون spam:
-- تنبيه واحد NEW لكل (صنف+مخزن+مستوى)، ويتقفل تلقائيا
-- لما الرصيد يرجع فوق الحد (RESOLVED).
-- ============================================================

create table if not exists public.stock_alerts (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete cascade,
  warehouse_id uuid references public.warehouses(id) on delete cascade,
  level text not null check (level in ('MINIMUM','OUT_OF_STOCK')),
  status text not null default 'NEW'
    check (status in ('NEW','ACK','RESOLVED')),
  available_qty numeric(14,3),
  created_at timestamptz not null default now(),
  ack_by uuid references public.profiles(id),
  ack_at timestamptz
);

create index if not exists idx_stock_alerts_status
  on public.stock_alerts (status, created_at desc);
create index if not exists idx_stock_alerts_product
  on public.stock_alerts (product_id, warehouse_id);

-- تنبيه NEW واحد فقط لكل (صنف+مخزن+مستوى).
create unique index if not exists uq_stock_alerts_new
  on public.stock_alerts (product_id, warehouse_id, level)
  where status = 'NEW';

alter table public.stock_alerts enable row level security;

drop policy if exists "salert_read" on public.stock_alerts;
create policy "salert_read" on public.stock_alerts
  for select to authenticated
  using (public.is_active_user() and (
    public.has_permission('inventory.view') or
    public.has_permission('purchases.view') or
    public.has_permission('purchases.approve') or
    public.has_permission('users.manage')));
drop policy if exists "salert_ack" on public.stock_alerts;
create policy "salert_ack" on public.stock_alerts
  for update to authenticated
  using (public.has_permission('purchases.approve') or
         public.has_permission('users.manage'))
  with check (public.has_permission('purchases.approve') or
              public.has_permission('users.manage'));

-- ---------- فحص المستويات بعد أي حركة ----------
create or replace function public.check_stock_levels(
  p_warehouse uuid, p_product uuid)
returns void language plpgsql security definer
set search_path = public as $$
declare v_avail numeric; v_min numeric;
  v_pname text; v_wname text; v_sup uuid;
  v_need numeric; v_aid uuid; v_sh uuid;
begin
  select ws.quantity - ws.reserved_quantity into v_avail
    from public.warehouse_stock ws
   where ws.warehouse_id = p_warehouse
     and ws.product_id = p_product;
  if not found then return; end if;
  select coalesce(p.minimum_stock, 0), p.name, p.supplier_id
    into v_min, v_pname, v_sup
    from public.products p where p.id = p_product;
  if not found then return; end if;
  select w.name into v_wname
    from public.warehouses w where w.id = p_warehouse;

  -- قفل القديم اللي اتحل.
  if v_avail > 0 then
    update public.stock_alerts set status = 'RESOLVED'
     where product_id = p_product and warehouse_id = p_warehouse
       and level = 'OUT_OF_STOCK' and status = 'NEW';
  end if;
  if v_min <= 0 or v_avail > v_min then
    update public.stock_alerts set status = 'RESOLVED'
     where product_id = p_product and warehouse_id = p_warehouse
       and level = 'MINIMUM' and status = 'NEW';
  end if;

  -- نفذ (صفر): تنبيه + نواقص تلقائي + إشعار.
  if v_avail <= 0 then
    if not exists (select 1 from public.stock_alerts
        where product_id = p_product and warehouse_id = p_warehouse
          and level = 'OUT_OF_STOCK' and status = 'NEW') then
      insert into public.stock_alerts
        (product_id, warehouse_id, level, available_qty)
        values (p_product, p_warehouse, 'OUT_OF_STOCK', v_avail)
        returning id into v_aid;
      -- نواقص تلقائي (كمية = الحد الأدنى، أو 1 لو بدون حد).
      v_need := greatest(v_min, 1);
      select id into v_sh from public.shortages
       where product_id = p_product and warehouse_id = p_warehouse
         and status = 'PENDING' limit 1;
      if found then
        update public.shortages
           set required_qty = required_qty + v_need,
               updated_at = now()
         where id = v_sh;
      else
        insert into public.shortages
          (product_id, warehouse_id, supplier_id, required_qty,
           status, source_type, source_id)
          values (p_product, p_warehouse, v_sup, v_need,
            'PENDING', 'STOCK_ALERT', v_aid::text);
      end if;
      perform public.notify_by_permission(
        'purchases.approve', 'STOCK_ALERT',
        'صنف نفذ من المخزون',
        coalesce(v_pname, 'صنف') || ' — مخزن ' ||
          coalesce(v_wname, '') ||
          ' (واتسجل في النواقص تلقائيا)',
        'STOCK_ALERT', v_aid::text);
    end if;
    return;
  end if;

  -- وصل الحد الأدنى: تنبيه + إشعار (طلب بضاعة للمدير).
  if v_min > 0 and v_avail <= v_min then
    if not exists (select 1 from public.stock_alerts
        where product_id = p_product and warehouse_id = p_warehouse
          and level = 'MINIMUM' and status = 'NEW') then
      insert into public.stock_alerts
        (product_id, warehouse_id, level, available_qty)
        values (p_product, p_warehouse, 'MINIMUM', v_avail)
        returning id into v_aid;
      perform public.notify_by_permission(
        'purchases.approve', 'STOCK_ALERT',
        'صنف وصل للحد الأدنى',
        coalesce(v_pname, 'صنف') || ' — مخزن ' ||
          coalesce(v_wname, '') ||
          ' (المتاح ' || v_avail::text || ')',
        'STOCK_ALERT', v_aid::text);
    end if;
  end if;
end $$;

-- ---------- trigger على أي حركة مخزون ----------
create or replace function public.trg_check_stock_levels()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if NEW.quantity is distinct from OLD.quantity
     or NEW.reserved_quantity is distinct from OLD.reserved_quantity then
    perform public.check_stock_levels(
      NEW.warehouse_id, NEW.product_id);
  end if;
  return NEW;
end $$;

drop trigger if exists trg_stock_levels on public.warehouse_stock;
create trigger trg_stock_levels
  after update of quantity, reserved_quantity on public.warehouse_stock
  for each row execute function public.trg_check_stock_levels();
