create table public.admin_investment_change_requests (
  request_id uuid primary key,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  investment_id uuid not null references public.investments(id) on delete restrict,
  action text not null check (action in ('amount_updated', 'cancelled')),
  reason text not null,
  old_principal_minor bigint not null check (old_principal_minor > 0),
  new_principal_minor bigint not null check (new_principal_minor > 0),
  wallet_adjustment_minor bigint not null default 0,
  transaction_id uuid references public.ledger_transactions(id) on delete restrict,
  result jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.admin_investment_change_requests enable row level security;
revoke all on public.admin_investment_change_requests from public, anon, authenticated;

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
  if funded_principal_minor <= 0 or funded_principal_minor <> v_investment.principal_minor then
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
  v_delta bigint;
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
  if p_target_minor < v_plan.minimum_minor
    or (v_plan.maximum_minor is not null and p_target_minor > v_plan.maximum_minor) then
    raise exception 'Amount is outside the plan limits';
  end if;

  v_wallet_debited := v_investment.creation_source = 'member'
    or (v_investment.creation_source = 'admin'
      and v_investment.admin_funding_method = 'wallet_debit');
  v_delta := p_target_minor - v_investment.principal_minor;

  if v_wallet_debited then
    select f.initial_transaction_id, f.funded_principal_minor
    into v_initial_debit, v_funded_minor
    from public.admin_verified_investment_funding(v_investment.id) f;

    if v_delta > 0 then
      v_wallet_adjustment := -v_delta;
      v_adjustment_tx := public.post_ledger(
        v_investment.owner_id,
        'wallet_debit',
        v_investment.asset_code,
        v_wallet_adjustment,
        'Admin investment amount increase ' || v_investment.id::text,
        'admin-investment-change:' || p_request_id::text
      );
    else
      v_wallet_adjustment := -v_delta;
      v_adjustment_tx := public.post_ledger(
        v_investment.owner_id,
        'wallet_credit',
        v_investment.asset_code,
        v_wallet_adjustment,
        'Admin investment amount decrease ' || v_investment.id::text,
        'admin-investment-change:' || p_request_id::text
      );
    end if;
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
      'original_investment_transaction_id', v_initial_debit,
      'adjustment_transaction_id', v_adjustment_tx,
      'request_id', p_request_id,
      'reason', v_reason
    )
  );
  return v_result;
end;
$$;

revoke all on function public.admin_update_investment_amount(uuid,bigint,text,uuid) from public, anon;
grant execute on function public.admin_update_investment_amount(uuid,bigint,text,uuid) to authenticated;

create or replace function public.admin_cancel_investment(
  p_investment_id uuid,
  p_reason text,
  p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_existing public.admin_investment_change_requests;
  v_investment public.investments;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_wallet_debited boolean := false;
  v_initial_debit uuid;
  v_funded_minor bigint;
  v_refund_tx uuid;
  v_refund_minor bigint := 0;
  v_cancelled_proofs integer := 0;
  v_result jsonb;
begin
  if not public.has_admin_role(array['super_admin','finance']) then
    raise exception 'Finance administrator access required';
  end if;
  if p_investment_id is null or p_request_id is null then
    raise exception 'Invalid investment cancellation request';
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
      or v_existing.action <> 'cancelled'
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
  if v_investment.status = 'cancelled' then
    raise exception 'Investment has already been cancelled';
  end if;
  if v_investment.status not in ('pending','active','completed') then
    raise exception 'Investment cannot be cancelled from its current status';
  end if;

  if v_investment.status in ('active','completed') then
    v_wallet_debited := v_investment.creation_source = 'member'
      or (v_investment.creation_source = 'admin'
        and v_investment.admin_funding_method = 'wallet_debit');
    if v_wallet_debited then
      select f.initial_transaction_id, f.funded_principal_minor
      into v_initial_debit, v_funded_minor
      from public.admin_verified_investment_funding(v_investment.id) f;

      v_refund_minor := v_funded_minor;
      v_refund_tx := public.post_ledger(
        v_investment.owner_id,
        'wallet_credit',
        v_investment.asset_code,
        v_refund_minor,
        'Admin investment cancellation refund ' || v_investment.id::text,
        'investment-refund:' || v_investment.id::text
      );
    end if;
  elsif v_investment.status = 'pending' then
    update public.payment_proofs
    set status = 'cancelled',
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        rejection_reason = v_reason,
        updated_at = now()
    where investment_id = v_investment.id
      and status = 'pending';
    get diagnostics v_cancelled_proofs = row_count;
  end if;

  update public.investments
  set status = 'cancelled',
      next_roi_at = null,
      updated_at = now()
  where id = v_investment.id;

  v_result := jsonb_build_object(
    'investment_id', v_investment.id,
    'status', 'cancelled',
    'previous_status', v_investment.status,
    'principal_minor', v_investment.principal_minor::text,
    'asset_code', v_investment.asset_code,
    'wallet_refunded', v_refund_minor > 0,
    'refund_minor', v_refund_minor::text,
    'refund_transaction_id', v_refund_tx,
    'pending_proofs_cancelled', v_cancelled_proofs
  );
  insert into public.admin_investment_change_requests(
    request_id, actor_id, investment_id, action, reason, old_principal_minor,
    new_principal_minor, wallet_adjustment_minor, transaction_id, result
  ) values (
    p_request_id, auth.uid(), v_investment.id, 'cancelled', v_reason,
    v_investment.principal_minor, v_investment.principal_minor, v_refund_minor,
    v_refund_tx, v_result
  );
  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    'admin_investment_cancelled',
    'investment',
    v_investment.id,
    jsonb_build_object(
      'owner_id', v_investment.owner_id,
      'previous_status', v_investment.status,
      'principal_minor', v_investment.principal_minor,
      'asset_code', v_investment.asset_code,
      'wallet_debited', v_wallet_debited,
      'original_investment_transaction_id', v_initial_debit,
      'refund_minor', v_refund_minor,
      'refund_transaction_id', v_refund_tx,
      'pending_proofs_cancelled', v_cancelled_proofs,
      'request_id', p_request_id,
      'reason', v_reason
    )
  );
  return v_result;
end;
$$;

revoke all on function public.admin_cancel_investment(uuid,text,uuid) from public, anon;
grant execute on function public.admin_cancel_investment(uuid,text,uuid) to authenticated;
