alter table public.investments
  add column admin_funding_method text,
  add constraint investments_admin_funding_method_check
    check (admin_funding_method is null or admin_funding_method in ('wallet_debit', 'no_wallet_debit'));

update public.investments
set admin_funding_method = 'wallet_debit'
where creation_source = 'admin';

create or replace function public.admin_create_investment(
  p_user_id uuid,
  p_plan_id uuid,
  p_principal_minor bigint,
  p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.profiles;
  v_plan public.investment_plans;
  v_existing public.investments;
  v_investment_id uuid;
  v_transaction_id uuid;
  v_now timestamptz := now();
begin
  if not public.has_admin_role(array['super_admin','finance']) then
    raise exception 'Finance administrator access required';
  end if;
  if p_user_id is null or p_plan_id is null or p_request_id is null then
    raise exception 'Invalid admin investment request';
  end if;
  if p_principal_minor is null or p_principal_minor <= 0 then
    raise exception 'Investment amount must be greater than zero';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('admin-investment:' || p_request_id::text, 0));
  select * into v_existing
  from public.investments
  where admin_request_id = p_request_id
  for update;
  if found then
    if v_existing.created_by is distinct from auth.uid()
      or v_existing.owner_id is distinct from p_user_id
      or v_existing.plan_id is distinct from p_plan_id
      or v_existing.principal_minor is distinct from p_principal_minor then
      raise exception 'Investment request key was already used for a different request';
    end if;
    select t.id into v_transaction_id
    from public.ledger_transactions t
    where t.idempotency_key = 'investment:' || v_existing.id::text;
    return jsonb_build_object(
      'investment_id', v_existing.id,
      'principal_minor', v_existing.principal_minor,
      'asset_code', v_existing.asset_code,
      'status', v_existing.status,
      'creation_source', v_existing.creation_source,
      'funding_method', v_existing.admin_funding_method,
      'wallet_debited', v_existing.admin_funding_method = 'wallet_debit',
      'transaction_id', v_transaction_id
    );
  end if;

  select * into v_profile
  from public.profiles
  where id = p_user_id
  for update;
  if not found then
    raise exception 'User not found';
  end if;

  select * into v_plan
  from public.investment_plans
  where id = p_plan_id and active = true
  for share;
  if not found then
    raise exception 'Plan is not available';
  end if;
  if v_plan.country_code is not null
    and v_plan.country_code <> upper(btrim(coalesce(v_profile.country, ''))) then
    raise exception 'Plan is not available for this user''s country';
  end if;
  if p_principal_minor < v_plan.minimum_minor
    or (v_plan.maximum_minor is not null and p_principal_minor > v_plan.maximum_minor) then
    raise exception 'Amount is outside the plan limits';
  end if;

  insert into public.investments (
    owner_id, plan_id, principal_minor, asset_code, status, roi_rate_bps,
    roi_interval_hours, activated_at, last_roi_at, next_roi_at, updated_at,
    creation_source, created_by, admin_request_id, admin_funding_method
  ) values (
    p_user_id, p_plan_id, p_principal_minor, v_plan.settlement_asset_code, 'active',
    v_plan.roi_rate_bps, v_plan.roi_interval_hours, v_now, v_now,
    v_now + make_interval(hours => v_plan.roi_interval_hours), v_now,
    'admin', auth.uid(), p_request_id, 'no_wallet_debit'
  ) returning id into v_investment_id;

  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    'admin_investment_created',
    'investment',
    v_investment_id,
    jsonb_build_object(
      'user_id', p_user_id,
      'plan_id', p_plan_id,
      'principal_minor', p_principal_minor,
      'asset_code', v_plan.settlement_asset_code,
      'transaction_id', null,
      'creation_source', 'admin',
      'funding_method', 'no_wallet_debit',
      'wallet_debited', false
    )
  );

  return jsonb_build_object(
    'investment_id', v_investment_id,
    'principal_minor', p_principal_minor,
    'asset_code', v_plan.settlement_asset_code,
    'status', 'active',
    'creation_source', 'admin',
    'funding_method', 'no_wallet_debit',
    'wallet_debited', false,
    'transaction_id', null
  );
end;
$$;

revoke all on function public.admin_create_investment(uuid, uuid, bigint, uuid) from public, anon;
grant execute on function public.admin_create_investment(uuid, uuid, bigint, uuid) to authenticated;
