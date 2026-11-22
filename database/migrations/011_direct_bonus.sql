-- Retire the shared legacy catalogue and publish the Rwandan plan tiers.
update public.investment_plans
set active = false, updated_at = now()
where active = true;

insert into public.investment_plans (name, minimum_minor, maximum_minor, roi_rate_bps, roi_interval_hours, duration_days, active, settlement_asset_code, performance_methodology, risk_disclosure, updated_at)
values
  ('RWF 10,000',      1000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 15,000',      1500000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 20,000',      2000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 25,000',      2500000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 30,000',      3000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 40,000',      4000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 50,000',      5000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 75,000',      7500000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 100,000',    10000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 150,000',    15000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 200,000',    20000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 250,000',    25000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 300,000',    30000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 400,000',    40000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 500,000',    50000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 600,000',    60000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 700,000',    70000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 800,000',    80000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 900,000',    90000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('RWF 1,000,000', 100000000,   null, 500, 24, 30, true, 'RWF', '5% daily income calculated from your active principal every 24 hours.', '', now())
on conflict (name) do update set
  minimum_minor = excluded.minimum_minor,
  maximum_minor = excluded.maximum_minor,
  roi_rate_bps = excluded.roi_rate_bps,
  roi_interval_hours = excluded.roi_interval_hours,
  duration_days = excluded.duration_days,
  active = true,
  settlement_asset_code = 'RWF',
  performance_methodology = excluded.performance_methodology,
  risk_disclosure = excluded.risk_disclosure,
  updated_at = now();

-- Staking is replaced by Direct Bonus. Remove its records, policies and ledger kind.
update public.ledger_transactions set kind = 'exchange' where kind::text = 'staking';

alter type public.transaction_kind rename to transaction_kind_legacy;
create type public.transaction_kind as enum ('deposit', 'withdrawal', 'investment', 'exchange', 'referral_commission', 'roi_credit');
alter table public.ledger_transactions
  alter column kind type public.transaction_kind using kind::text::public.transaction_kind;
drop type public.transaction_kind_legacy;

drop policy if exists "staking admin read" on public.staking_positions;
drop policy if exists "staking own read" on public.staking_positions;
drop table if exists public.staking_positions;

-- Refresh the admin overview without the removed staking metric.
create or replace function public.admin_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  select jsonb_build_object(
    'registered_users', (select count(*) from public.profiles),
    'verified_users', (select count(*) from public.profiles where verification_status = 'verified'),
    'active_investments', (select count(*) from public.investments where status = 'active'),
    'total_deposits_minor', coalesce((select sum(amount_minor) from public.ledger_transactions where kind = 'deposit' and status = 'completed'), 0),
    'total_withdrawals_minor', coalesce((select sum(amount_minor) from public.ledger_transactions where kind = 'withdrawal' and status = 'completed'), 0),
    'pending_transactions', (select count(*) from public.ledger_transactions where status in ('pending','processing')),
    'referral_commissions_minor', coalesce((select sum(amount_minor) from public.referral_commissions where status = 'credited'), 0),
    'recent_activity', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'kind', t.kind, 'status', t.status, 'amount_minor', t.amount_minor,
        'asset_code', t.asset_code, 'created_at', t.created_at,
        'name', coalesce(nullif(p.full_name, ''), split_part(u.email, '@', 1), 'Member')
      ) order by t.created_at desc)
      from (select * from public.ledger_transactions order by created_at desc limit 6) t
      left join public.profiles p on p.id = t.owner_id
      left join auth.users u on u.id = t.owner_id
    ), '[]'::jsonb),
    'recent_users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', coalesce(nullif(p.full_name, ''), split_part(u.email, '@', 1), 'Member'),
        'email', u.email, 'created_at', p.created_at
      ) order by p.created_at desc)
      from (select * from public.profiles order by created_at desc limit 6) p
      left join auth.users u on u.id = p.id
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.admin_overview() from public;
grant execute on function public.admin_overview() to authenticated;
