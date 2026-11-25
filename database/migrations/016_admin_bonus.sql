alter type public.transaction_kind add value if not exists 'bonus_credit';

create or replace function public.admin_credit_bonus(
  p_user_id uuid,
  p_amount_minor bigint,
  p_asset_code text,
  p_reason text,
  p_idempotency_key text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_transaction_id uuid;
  v_existing public.ledger_transactions;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.has_admin_role(array['super_admin','finance']) then
    raise exception 'Finance administrator access required';
  end if;
  if p_user_id is null or not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'User not found';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Bonus amount must be greater than zero';
  end if;
  if p_asset_code not in ('USD','RWF','BIF','BTC','ETH','USDT','USDC') then
    raise exception 'Unsupported account currency';
  end if;
  if v_reason is null or length(v_reason) > 500 then
    raise exception 'A reason of up to 500 characters is required';
  end if;
  if p_idempotency_key is null or p_idempotency_key !~ '^admin-bonus:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'Invalid bonus request key';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key, 0));
  select * into v_existing
  from public.ledger_transactions
  where idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_existing.owner_id <> p_user_id
      or v_existing.kind::text <> 'bonus_credit'
      or v_existing.asset_code <> p_asset_code
      or v_existing.amount_minor <> p_amount_minor
      or v_existing.status <> 'completed' then
      raise exception 'Bonus request key was already used for a different credit';
    end if;
    return jsonb_build_object(
      'transaction_id', v_existing.id,
      'user_id', p_user_id,
      'amount_minor', p_amount_minor,
      'asset_code', p_asset_code
    );
  end if;

  v_transaction_id := public.post_ledger(
    p_user_id,
    'bonus_credit',
    p_asset_code,
    p_amount_minor,
    'Administrator bonus: ' || v_reason,
    p_idempotency_key
  );
  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    'admin_bonus_credited',
    'profile',
    p_user_id,
    jsonb_build_object(
      'transaction_id', v_transaction_id,
      'amount_minor', p_amount_minor,
      'asset_code', p_asset_code,
      'reason', v_reason
    )
  );
  return jsonb_build_object(
    'transaction_id', v_transaction_id,
    'user_id', p_user_id,
    'amount_minor', p_amount_minor,
    'asset_code', p_asset_code
  );
end;
$$;

revoke all on function public.admin_credit_bonus(uuid,bigint,text,text,text) from public;
grant execute on function public.admin_credit_bonus(uuid,bigint,text,text,text) to authenticated;
revoke all on function public.post_ledger(uuid,text,text,bigint,text,text) from public, anon, authenticated;
grant execute on function public.post_ledger(uuid,text,text,bigint,text,text) to service_role;
