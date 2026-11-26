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

create or replace function public.admin_verified_investment_funding(p_investment_id uuid)
returns table(initial_transaction_id uuid, funded_principal_minor bigint)
language plpgsql security definer set search_path = '' as $$
declare
  v_investment public.investments;
  v_initial_transaction_id uuid;
  v_initial_minor bigint;
  v_adjustments bigint;
begin
  select * into v_investment
  from public.investments i
  where i.id = p_investment_id;
  if not found then
    raise exception 'Investment not found';
  end if;

  select t.id, t.amount_minor into v_initial_transaction_id, v_initial_minor
  from public.ledger_transactions t
  where t.idempotency_key = 'investment:' || v_investment.id::text
    and t.owner_id = v_investment.owner_id
    and t.kind::text = 'investment'
    and t.status::text = 'completed'
    and t.asset_code = v_investment.asset_code
    and exists (
      select 1
      from public.ledger_entries le
      join public.asset_accounts a on a.id = le.account_id
      where le.transaction_id = t.id
        and a.owner_id = v_investment.owner_id
        and a.asset_code = v_investment.asset_code
        and le.amount_minor = -t.amount_minor
    )
  limit 1;
  if v_initial_transaction_id is null then
    raise exception 'Original investment wallet debit could not be verified';
  end if;

  if exists (
    select 1
    from public.admin_investment_change_requests r
    where r.investment_id = v_investment.id
      and r.action = 'amount_updated'
      and (
        (r.wallet_adjustment_minor = 0 and r.transaction_id is not null)
        or (
          r.wallet_adjustment_minor <> 0
          and (
            r.transaction_id is null
            or not exists (
              select 1
              from public.ledger_transactions t
              where t.id = r.transaction_id
                and t.owner_id = v_investment.owner_id
                and t.status::text = 'completed'
                and t.asset_code = v_investment.asset_code
                and t.amount_minor = abs(r.wallet_adjustment_minor)
                and t.kind::text = case
                  when r.wallet_adjustment_minor < 0 then 'wallet_debit'
                  else 'wallet_credit'
                end
                and exists (
                  select 1
                  from public.ledger_entries le
                  join public.asset_accounts a on a.id = le.account_id
                  where le.transaction_id = t.id
                    and a.owner_id = v_investment.owner_id
                    and a.asset_code = v_investment.asset_code
                    and le.amount_minor = r.wallet_adjustment_minor
                )
            )
          )
        )
      )
  ) then
    raise exception 'A prior investment wallet adjustment could not be verified';
  end if;

  select coalesce(sum(r.wallet_adjustment_minor), 0) into v_adjustments
  from public.admin_investment_change_requests r
  where r.investment_id = v_investment.id
    and r.action = 'amount_updated';
  funded_principal_minor := v_initial_minor - v_adjustments;
  if funded_principal_minor <= 0 or funded_principal_minor > v_investment.principal_minor then
    raise exception 'Investment amount does not match its verified wallet funding history';
  end if;
  initial_transaction_id := v_initial_transaction_id;
  return next;
end;
$$;

revoke all on function public.admin_verified_investment_funding(uuid) from public, anon, authenticated;

create or replace function public.admin_update_investment_amount(
  p_investment_id uuid,
  p_target_minor bigint,
  p_reason text,
  p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_existing public.admin_investment_change_requests;
  v_investment public.investments;
  v_plan public.investment_plans;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_wallet_debited boolean;
  v_initial_debit uuid;
  v_funded_minor bigint;
  v_adjustment_tx uuid;
  v_wallet_adjustment bigint := 0;
  v_admin_grant_minor bigint := 0;
  v_result jsonb;
begin
  if not public.has_admin_role(array['super_admin','finance']) then
    raise exception 'Finance administrator access required';
  end if;
  if p_investment_id is null or p_request_id is null then
    raise exception 'Invalid investment update request';
  end if;
  if p_target_minor is null or p_target_minor <= 0 then
    raise exception 'Investment amount must be greater than zero';
  end if;
  if v_reason is null or length(v_reason) > 500 then
    raise exception 'A reason of up to 500 characters is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('admin-investment-change:' || p_request_id::text, 0));
  select * into v_existing
  from public.admin_investment_change_requests r
  where r.request_id = p_request_id
  for update;
  if found then
    if v_existing.actor_id <> auth.uid()
      or v_existing.investment_id <> p_investment_id
      or v_existing.action <> 'amount_updated'
      or v_existing.new_principal_minor <> p_target_minor
      or v_existing.reason <> v_reason then
      raise exception 'Investment change request key was already used for a different request';
    end if;
    return v_existing.result;
  end if;

  select * into v_investment
  from public.investments i
  where i.id = p_investment_id
  for update;
  if not found then
    raise exception 'Investment not found';
  end if;
  if v_investment.status not in ('active','completed') then
    raise exception 'Only active or completed investments can be edited';
  end if;
  if p_target_minor = v_investment.principal_minor then
    raise exception 'The new amount matches the current amount';
  end if;

  select * into v_plan
  from public.investment_plans p
  where p.id = v_investment.plan_id
  for share;
  if not found then
    raise exception 'Investment plan not found';
  end if;

  v_wallet_debited := v_investment.creation_source = 'member'
    or (v_investment.creation_source = 'admin'
      and v_investment.admin_funding_method = 'wallet_debit');
  if v_wallet_debited then
    select f.initial_transaction_id, f.funded_principal_minor
    into v_initial_debit, v_funded_minor
    from public.admin_verified_investment_funding(v_investment.id) f;

    if p_target_minor < v_funded_minor then
      v_wallet_adjustment := v_funded_minor - p_target_minor;
      v_adjustment_tx := public.post_ledger(
        v_investment.owner_id,
        'wallet_credit',
        v_investment.asset_code,
        v_wallet_adjustment,
        'Admin investment amount decrease ' || v_investment.id::text,
        'admin-investment-change:' || p_request_id::text
      );
    end if;
    v_admin_grant_minor := greatest(
      p_target_minor - (v_funded_minor - v_wallet_adjustment),
      0
    );
  else
    v_admin_grant_minor := p_target_minor;
  end if;

  update public.investments
  set principal_minor = p_target_minor, updated_at = now()
  where id = v_investment.id;

  v_result := jsonb_build_object(
    'investment_id', v_investment.id,
    'status', v_investment.status,
    'old_principal_minor', v_investment.principal_minor::text,
    'principal_minor', p_target_minor::text,
    'asset_code', v_investment.asset_code,
    'wallet_adjustment_minor', v_wallet_adjustment::text,
    'admin_grant_minor', v_admin_grant_minor::text,
    'transaction_id', v_adjustment_tx
  );
  insert into public.admin_investment_change_requests(
    request_id, actor_id, investment_id, action, reason, old_principal_minor,
    new_principal_minor, wallet_adjustment_minor, transaction_id, result
  ) values (
    p_request_id, auth.uid(), v_investment.id, 'amount_updated', v_reason,
    v_investment.principal_minor, p_target_minor, v_wallet_adjustment,
    v_adjustment_tx, v_result
  );
  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    'admin_investment_amount_updated',
    'investment',
    v_investment.id,
    jsonb_build_object(
      'owner_id', v_investment.owner_id,
      'old_principal_minor', v_investment.principal_minor,
      'new_principal_minor', p_target_minor,
      'asset_code', v_investment.asset_code,
      'wallet_debited', v_wallet_debited,
      'wallet_adjustment_minor', v_wallet_adjustment,
      'admin_grant_minor', v_admin_grant_minor,
      'original_investment_transaction_id', v_initial_debit,
      'adjustment_transaction_id', v_adjustment_tx,
      'request_id', p_request_id,
      'reason', v_reason
    )
  );
  return v_result;
end;
$$;

revoke all on function public.admin_update_investment_amount(uuid, bigint, text, uuid) from public, anon;
grant execute on function public.admin_update_investment_amount(uuid, bigint, text, uuid) to authenticated;
