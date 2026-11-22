alter table public.investment_plans add column if not exists country_code text;

update public.investment_plans
set country_code = case upper(btrim(coalesce(settlement_asset_code, '')))
  when 'RWF' then 'RW'
  when 'BIF' then 'BI'
  else null
end,
updated_at = now()
where country_code is null;

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
      'country_code', country_code,
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

drop function if exists public.admin_upsert_plan(uuid,text,bigint,bigint,integer,integer,integer,integer,text,text,text,boolean);

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
  p_country_code text default null,
  p_performance_methodology text default '',
  p_risk_disclosure text default '',
  p_active boolean default false
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_asset text := upper(btrim(coalesce(p_settlement_asset_code, 'USD')));
  v_country text := nullif(upper(btrim(coalesce(p_country_code, ''))), '');
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
  if v_country is not null and v_country !~ '^[A-Z]{2}$' then
    raise exception 'Choose a valid two-letter country code';
  end if;
  if p_id is null then
    if exists (select 1 from public.investment_plans where lower(name) = lower(v_name)) then
      raise exception 'A plan with this name already exists';
    end if;
    insert into public.investment_plans (
      name, minimum_minor, maximum_minor, duration_days, fee_bps,
      roi_rate_bps, roi_interval_hours, settlement_asset_code, country_code,
      performance_methodology, risk_disclosure, active, updated_at
    ) values (
      v_name, p_minimum_minor, p_maximum_minor, p_duration_days, coalesce(p_fee_bps, 0),
      coalesce(p_roi_rate_bps, 0), coalesce(p_roi_interval_hours, 24), v_asset, v_country,
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
        country_code = v_country,
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
    'country_code', v_country,
    'status', case when coalesce(p_active, false) then 'active' else 'hidden' end
  );
end;
$$;

create or replace function public.submit_payment_proof(
  p_amount_minor bigint,
  p_asset_code text,
  p_screenshot_path text,
  p_phone text,
  p_full_name text,
  p_payer_name text,
  p_idempotency_key text,
  p_plan_id uuid default null,
  p_provider_reference text default null,
  p_note text default null,
  p_payee_name text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_investment_id uuid;
  v_plan public.investment_plans;
  v_country text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if coalesce(p_amount_minor, 0) <= 0 then
    raise exception 'Enter a deposit amount';
  end if;
  if split_part(coalesce(p_screenshot_path, ''), '/', 1) <> auth.uid()::text then
    raise exception 'Invalid screenshot path';
  end if;
  if nullif(trim(coalesce(p_phone, '')), '') is null or nullif(trim(coalesce(p_payer_name, '')), '') is null then
    raise exception 'Phone number and payer name are required';
  end if;
  if p_plan_id is not null then
    select * into v_plan from public.investment_plans where id = p_plan_id and active = true;
    if not found then
      raise exception 'Plan is not available';
    end if;
    select upper(btrim(coalesce(country, ''))) into v_country from public.profiles where id = auth.uid();
    if v_plan.country_code is not null and upper(btrim(v_plan.country_code)) <> coalesce(v_country, '') then
      raise exception 'Plan is not available for your country';
    end if;
    if p_amount_minor < v_plan.minimum_minor or (v_plan.maximum_minor is not null and p_amount_minor > v_plan.maximum_minor) then
      raise exception 'Amount is outside the plan limits';
    end if;
    insert into public.investments (owner_id, plan_id, principal_minor, asset_code, status)
    values (auth.uid(), p_plan_id, p_amount_minor, p_asset_code, 'pending')
    returning id into v_investment_id;
  end if;
  insert into public.payment_proofs (
    owner_id, idempotency_key, amount_minor, asset_code, phone, full_name, payer_name,
    payee_name, screenshot_path, provider_reference, note, plan_id, investment_id
  ) values (
    auth.uid(), p_idempotency_key, p_amount_minor, p_asset_code, trim(p_phone), trim(p_full_name),
    trim(p_payer_name), nullif(trim(coalesce(p_payee_name, '')), ''), p_screenshot_path,
    nullif(trim(coalesce(p_provider_reference, '')), ''), nullif(trim(coalesce(p_note, '')), ''),
    p_plan_id, v_investment_id
  ) returning id into v_id;
  return jsonb_build_object('id', v_id, 'investment_id', v_investment_id, 'status', 'pending');
end;
$$;

revoke all on function public.admin_upsert_plan(uuid,text,bigint,bigint,integer,integer,integer,integer,text,text,text,text,boolean) from public;
grant execute on function public.admin_upsert_plan(uuid,text,bigint,bigint,integer,integer,integer,integer,text,text,text,text,boolean) to authenticated;
