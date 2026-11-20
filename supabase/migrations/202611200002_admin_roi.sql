alter table public.investment_plans
  add column roi_rate_bps integer not null default 0 check (roi_rate_bps between 0 and 100000),
  add column roi_interval_hours integer not null default 24 check (roi_interval_hours between 1 and 8760),
  add column settlement_asset_code text not null default 'USD',
  add column updated_at timestamptz not null default now();
alter table public.investments
  add column roi_rate_bps integer not null default 0,
  add column roi_interval_hours integer not null default 24,
  add column activated_at timestamptz,
  add column last_roi_at timestamptz,
  add column next_roi_at timestamptz,
  add column total_roi_paid_minor bigint not null default 0,
  add column updated_at timestamptz not null default now(),
  add constraint investments_status_check check (status in ('pending','active','completed','cancelled'));
alter table public.admin_roles
  add column created_at timestamptz not null default now(),
  add column created_by uuid references public.profiles(id) on delete set null;
create table public.roi_credits (
  id uuid primary key default gen_random_uuid(),
  investment_id uuid not null references public.investments(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  transaction_id uuid not null unique references public.ledger_transactions(id) on delete cascade,
  period_start timestamptz not null,
  period_end timestamptz not null,
  rate_bps integer not null check (rate_bps >= 0),
  base_minor bigint not null check (base_minor > 0),
  amount_minor bigint not null check (amount_minor > 0),
  idempotency_key text not null unique,
  created_at timestamptz not null default now(),
  unique (investment_id, period_start)
);
create index roi_credits_owner_created on public.roi_credits(owner_id, created_at desc);
create index investments_due_roi on public.investments(next_roi_at) where status = 'active';
alter table public.roi_credits enable row level security;
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admin_roles ar where ar.user_id = auth.uid());
$$;
create or replace function public.current_admin_role()
returns text language sql stable security definer set search_path = '' as $$
  select ar.role from public.admin_roles ar where ar.user_id = auth.uid() limit 1;
$$;
create or replace function public.has_admin_role(p_roles text[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.admin_roles ar
    where ar.user_id = auth.uid() and ar.role = any(p_roles)
  );
$$;
revoke all on function public.is_admin() from public;
revoke all on function public.current_admin_role() from public;
revoke all on function public.has_admin_role(text[]) from public;
grant execute on function public.is_admin() to authenticated, service_role;
grant execute on function public.current_admin_role() to authenticated, service_role;
grant execute on function public.has_admin_role(text[]) to authenticated, service_role;
create or replace function public.post_ledger(
  p_owner_id uuid,
  p_kind text,
  p_asset_code text,
  p_signed_minor bigint,
  p_description text,
  p_idempotency_key text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_account_id uuid;
  v_balance bigint;
  v_transaction_id uuid;
begin
  select a.id into v_account_id
  from public.asset_accounts a
  where a.owner_id = p_owner_id and a.asset_code = p_asset_code;
  if v_account_id is null then
    raise exception 'No asset account for member and asset %', p_asset_code;
  end if;
  select coalesce(sum(le.amount_minor), 0) into v_balance
  from public.ledger_entries le
  where le.account_id = v_account_id;
  if p_signed_minor < 0 and v_balance < abs(p_signed_minor) then
    raise exception 'Insufficient balance';
  end if;
  insert into public.ledger_transactions(
    idempotency_key, kind, status, owner_id, amount_minor, asset_code, description, completed_at
  ) values (
    p_idempotency_key, p_kind::public.transaction_kind, 'completed', p_owner_id,
    abs(p_signed_minor), p_asset_code, p_description, now()
  ) on conflict (idempotency_key) do nothing;
  select id into v_transaction_id
  from public.ledger_transactions
  where idempotency_key = p_idempotency_key;
  if not exists (select 1 from public.ledger_entries le where le.transaction_id = v_transaction_id) then
    insert into public.ledger_entries(transaction_id, account_id, amount_minor)
    values (v_transaction_id, v_account_id, p_signed_minor);
  end if;
  return v_transaction_id;
end;
$$;
create or replace function public.activate_investment(p_investment_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_investment record;
  v_transaction_id uuid;
  v_interval integer;
begin
  select i.*, p.name as plan_name, p.roi_rate_bps as plan_roi_rate_bps,
         p.roi_interval_hours as plan_roi_interval_hours
  into v_investment
  from public.investments i
  join public.investment_plans p on p.id = i.plan_id
  where i.id = p_investment_id;
  if not found then
    raise exception 'Investment not found';
  end if;
  if v_investment.status = 'active' then
    return p_investment_id;
  end if;
  if v_investment.status <> 'pending' then
    raise exception 'Investment cannot be activated from % status', v_investment.status;
  end if;
  v_interval := coalesce(v_investment.plan_roi_interval_hours, 24);
  v_transaction_id := public.post_ledger(
    v_investment.owner_id,
    'investment',
    v_investment.asset_code,
    -v_investment.principal_minor,
    'Investment in ' || v_investment.plan_name,
    'investment:' || p_investment_id::text
  );
  update public.investments
  set status = 'active',
      roi_rate_bps = v_investment.plan_roi_rate_bps,
      roi_interval_hours = v_interval,
      activated_at = now(),
      last_roi_at = now(),
      next_roi_at = now() + make_interval(hours => v_interval),
      updated_at = now()
  where id = p_investment_id;
  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (auth.uid(), 'investment_activated', 'investment', p_investment_id,
          jsonb_build_object('transaction_id', v_transaction_id, 'principal_minor', v_investment.principal_minor));
  return p_investment_id;
end;
$$;
create or replace function public.process_due_roi(p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_investment record;
  v_now timestamptz := now();
  v_amount bigint;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_key text;
  v_transaction_id uuid;
  v_credit_id uuid;
  v_processed integer := 0;
  v_errors integer := 0;
begin
  for v_investment in
    select i.id, i.owner_id, i.asset_code, i.principal_minor, i.roi_rate_bps,
           i.roi_interval_hours, i.next_roi_at
    from public.investments i
    where i.status = 'active' and i.next_roi_at <= v_now and i.roi_rate_bps > 0
    order by i.next_roi_at
    limit greatest(1, least(coalesce(p_limit, 100), 1000))
    for update skip locked
  loop
    begin
      v_amount := (v_investment.principal_minor * v_investment.roi_rate_bps + 5000) / 10000;
      v_period_start := v_investment.next_roi_at;
      v_period_end := v_period_start + make_interval(hours => v_investment.roi_interval_hours);
      v_key := 'roi:' || v_investment.id::text || ':' || to_char(v_period_start at time zone 'UTC', 'YYYYMMDDHH24MISSUS');
      v_transaction_id := public.post_ledger(
        v_investment.owner_id,
        'roi_credit',
        v_investment.asset_code,
        v_amount,
        'Automated investment return',
        v_key
      );
      insert into public.roi_credits(
        investment_id, owner_id, transaction_id, period_start, period_end,
        rate_bps, base_minor, amount_minor, idempotency_key
      ) values (
        v_investment.id, v_investment.owner_id, v_transaction_id, v_period_start, v_period_end,
        v_investment.roi_rate_bps, v_investment.principal_minor, v_amount, v_key
      ) on conflict (investment_id, period_start) do nothing returning id into v_credit_id;
      if v_credit_id is not null then
        update public.investments
        set last_roi_at = v_period_start,
            next_roi_at = v_period_end,
            total_roi_paid_minor = total_roi_paid_minor + v_amount,
            updated_at = now()
        where id = v_investment.id;
        insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
        values (auth.uid(), 'roi_credited', 'investment', v_investment.id,
                jsonb_build_object('transaction_id', v_transaction_id, 'amount_minor', v_amount, 'period_end', v_period_end));
      else
        update public.investments
        set next_roi_at = v_period_end, updated_at = now()
        where id = v_investment.id;
      end if;
      v_processed := v_processed + 1;
    exception when others then
      v_errors := v_errors + 1;
      begin
        update public.investments
        set next_roi_at = now() + make_interval(hours => v_investment.roi_interval_hours),
            updated_at = now()
        where id = v_investment.id;
      exception when others then null;
      end;
      begin
        insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
        values (auth.uid(), 'roi_failed', 'investment', v_investment.id,
                jsonb_build_object('error', sqlerrm));
      exception when others then null;
      end;
    end;
  end loop;
  return jsonb_build_object('processed', v_processed, 'errors', v_errors, 'executed_at', v_now);
end;
$$;
revoke all on function public.post_ledger(uuid, text, text, bigint, text, text) from public;
revoke all on function public.activate_investment(uuid) from public;
revoke all on function public.process_due_roi(integer) from public;
grant execute on function public.post_ledger(uuid, text, text, bigint, text, text) to service_role;
grant execute on function public.activate_investment(uuid) to service_role;
grant execute on function public.process_due_roi(integer) to service_role;
drop policy if exists "profiles admin read" on public.profiles;
create policy "profiles admin read" on public.profiles for select to authenticated using (public.is_admin());
drop policy if exists "plans admin read" on public.investment_plans;
create policy "plans admin read" on public.investment_plans for select to authenticated using (public.is_admin());
drop policy if exists "transactions admin read" on public.ledger_transactions;
create policy "transactions admin read" on public.ledger_transactions for select to authenticated using (public.is_admin());
drop policy if exists "ledger entries admin read" on public.ledger_entries;
create policy "ledger entries admin read" on public.ledger_entries for select to authenticated using (
  public.is_admin() or exists (
    select 1 from public.asset_accounts a
    where a.id = account_id and a.owner_id = auth.uid()
  )
);
drop policy if exists "investments admin read" on public.investments;
create policy "investments admin read" on public.investments for select to authenticated using (public.is_admin() or owner_id = auth.uid());
drop policy if exists "roi credits own read" on public.roi_credits;
create policy "roi credits own read" on public.roi_credits for select to authenticated using (public.is_admin() or owner_id = auth.uid());
drop policy if exists "audit admin read" on public.audit_log;
create policy "audit admin read" on public.audit_log for select to authenticated using (
  public.has_admin_role(array['super_admin','finance','compliance'])
);
