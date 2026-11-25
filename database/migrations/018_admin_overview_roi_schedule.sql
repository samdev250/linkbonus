create extension if not exists pg_cron with schema pg_catalog;

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
    'bonus_credits_sent', (select count(*) from public.ledger_transactions where kind::text = 'bonus_credit' and status = 'completed'),
    'bonus_credits_sent_minor', coalesce((select sum(amount_minor) from public.ledger_transactions where kind::text = 'bonus_credit' and status = 'completed'), 0),
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

create or replace function public.member_roi_summary()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'paid_minor', coalesce((select sum(i.total_roi_paid_minor) from public.investments i where i.owner_id = auth.uid()), 0),
    'accrued_minor', coalesce((
      select sum(round(
        (i.principal_minor::numeric * i.roi_rate_bps *
         greatest(extract(epoch from (now() - case
           when i.total_roi_paid_minor > 0
             then coalesce(i.last_roi_at, i.activated_at) + make_interval(hours => i.roi_interval_hours)
           else coalesce(i.activated_at, i.last_roi_at)
         end)) / 3600, 0) /
         nullif(i.roi_interval_hours, 0)) / 10000
      ))
      from public.investments i
      where i.owner_id = auth.uid() and i.status = 'active' and i.roi_rate_bps > 0
    ), 0),
    'daily_minor', coalesce((
      select sum(round(i.principal_minor::numeric * i.roi_rate_bps / 10000))
      from public.investments i
      where i.owner_id = auth.uid() and i.status = 'active' and i.roi_rate_bps > 0
    ), 0),
    'next_credit_at', (
      select min(i.next_roi_at) from public.investments i
      where i.owner_id = auth.uid() and i.status = 'active' and i.roi_rate_bps > 0
    ),
    'investments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'plan', pl.name, 'principal_minor', i.principal_minor,
        'status', i.status, 'rate_bps', i.roi_rate_bps,
        'daily_minor', round(i.principal_minor::numeric * i.roi_rate_bps / 10000),
        'paid_minor', i.total_roi_paid_minor, 'next_roi_at', i.next_roi_at,
        'activated_at', i.activated_at
      ) order by i.created_at desc)
      from public.investments i join public.investment_plans pl on pl.id = i.plan_id
      where i.owner_id = auth.uid()
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.member_roi_summary() from public;
grant execute on function public.member_roi_summary() to authenticated;

do $$
declare
  v_job_id bigint;
begin
  select jobid into v_job_id
  from cron.job
  where jobname = 'linkbonus-process-due-roi';
  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;
  perform cron.schedule(
    'linkbonus-process-due-roi',
    '* * * * *',
    'select public.process_due_roi(100);'
  );
end;
$$;
