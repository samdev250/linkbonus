create or replace function public.admin_list_plans()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id,
      'name', name,
      'minimum_minor', minimum_minor,
      'maximum_minor', maximum_minor,
      'duration_days', duration_days,
      'fee_bps', fee_bps,
      'roi_rate_bps', roi_rate_bps,
      'roi_interval_hours', roi_interval_hours,
      'settlement_asset_code', settlement_asset_code,
      'performance_methodology', performance_methodology,
      'risk_disclosure', risk_disclosure,
      'active', active,
      'created_at', created_at,
      'updated_at', updated_at
    ) order by minimum_minor, name)
    from public.investment_plans
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_upsert_plan(
  p_id uuid default null,
  p_name text default null,
  p_minimum_minor bigint default null,
  p_maximum_minor bigint default null,
  p_duration_days integer default null,
  p_fee_bps integer default 0,
  p_roi_rate_bps integer default 0,
  p_roi_interval_hours integer default 24,
  p_settlement_asset_code text default 'USD',
  p_performance_methodology text default '',
  p_risk_disclosure text default '',
  p_active boolean default false
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_asset text := upper(btrim(coalesce(p_settlement_asset_code, 'USD')));
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if v_name is null then
    raise exception 'Plan name is required';
  end if;
  if p_minimum_minor is null or p_minimum_minor <= 0 then
    raise exception 'Minimum amount must be greater than zero';
  end if;
  if p_maximum_minor is not null and p_maximum_minor < p_minimum_minor then
    raise exception 'Maximum amount cannot be below the minimum';
  end if;
  if p_duration_days is not null and p_duration_days <= 0 then
    raise exception 'Duration must be greater than zero';
  end if;
  if p_fee_bps is null or p_fee_bps < 0 or p_fee_bps > 10000 then
    raise exception 'Fee must be between 0%% and 100%%';
  end if;
  if p_roi_rate_bps is null or p_roi_rate_bps < 0 or p_roi_rate_bps > 100000 then
    raise exception 'Daily income rate is outside the allowed range';
  end if;
  if p_roi_interval_hours is null or p_roi_interval_hours < 1 or p_roi_interval_hours > 8760 then
    raise exception 'Credit interval must be between 1 and 8760 hours';
  end if;
  if v_asset not in ('RWF','BIF','USD','BTC','ETH','USDT','USDC') then
    raise exception 'Choose a supported settlement asset';
  end if;
  if p_id is null then
    if exists (select 1 from public.investment_plans where lower(name) = lower(v_name)) then
      raise exception 'A plan with this name already exists';
    end if;
    insert into public.investment_plans (
      name, minimum_minor, maximum_minor, duration_days, fee_bps,
      roi_rate_bps, roi_interval_hours, settlement_asset_code,
      performance_methodology, risk_disclosure, active, updated_at
    ) values (
      v_name, p_minimum_minor, p_maximum_minor, p_duration_days, coalesce(p_fee_bps, 0),
      coalesce(p_roi_rate_bps, 0), coalesce(p_roi_interval_hours, 24), v_asset,
      coalesce(p_performance_methodology, ''), coalesce(p_risk_disclosure, ''),
      coalesce(p_active, false), now()
    ) returning id into v_id;
  else
    if not exists (select 1 from public.investment_plans where id = p_id) then
      raise exception 'Plan not found';
    end if;
    if exists (select 1 from public.investment_plans where lower(name) = lower(v_name) and id <> p_id) then
      raise exception 'A plan with this name already exists';
    end if;
    update public.investment_plans
    set name = v_name,
        minimum_minor = p_minimum_minor,
        maximum_minor = p_maximum_minor,
        duration_days = p_duration_days,
        fee_bps = coalesce(p_fee_bps, 0),
        roi_rate_bps = coalesce(p_roi_rate_bps, 0),
        roi_interval_hours = coalesce(p_roi_interval_hours, 24),
        settlement_asset_code = v_asset,
        performance_methodology = coalesce(p_performance_methodology, ''),
        risk_disclosure = coalesce(p_risk_disclosure, ''),
        active = coalesce(p_active, false),
        updated_at = now()
    where id = p_id
    returning id into v_id;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'name', v_name,
    'status', case when coalesce(p_active, false) then 'active' else 'hidden' end
  );
end;
$$;

drop policy if exists "plans admin write" on public.investment_plans;
create policy "plans admin write" on public.investment_plans for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

revoke all on function public.admin_list_plans() from public;
revoke all on function public.admin_upsert_plan(uuid, text, bigint, bigint, integer, integer, integer, integer, text, text, text, boolean) from public;
grant execute on function public.admin_list_plans() to authenticated;
grant execute on function public.admin_upsert_plan(uuid, text, bigint, bigint, integer, integer, integer, integer, text, text, text, boolean) to authenticated;
