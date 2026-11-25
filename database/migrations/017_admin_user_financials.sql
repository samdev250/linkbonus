alter type public.transaction_kind add value if not exists 'wallet_credit';

create or replace function public.admin_list_users(
  p_search text default '',
  p_status text default 'All users',
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_total integer;
  v_rows jsonb;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;

  select count(*) into v_total
  from public.profiles p
  join auth.users u on u.id = p.id
  where (coalesce(p_search, '') = ''
      or p.full_name ilike '%' || p_search || '%'
      or u.email ilike '%' || p_search || '%'
      or p.id::text = p_search)
    and (coalesce(p_status, 'All users') in ('All users', '')
      or lower(p.status::text) = lower(p_status)
      or (p_status = 'Verified' and p.verification_status = 'verified')
      or (p_status = 'Pending verification' and p.verification_status <> 'verified'));

  select jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', coalesce(nullif(p.full_name, ''), split_part(p.email, '@', 1), 'Member'),
    'email', p.email,
    'country', p.country,
    'phone', p.phone,
    'status', p.status,
    'verification_status', p.verification_status,
    'referral_code', p.referral_code,
    'role', p.role,
    'created_at', p.created_at,
    'balance_asset_code', amounts.asset_code,
    'balance_minor', amounts.balance_minor,
    'invested_minor', amounts.invested_minor,
    'bonus_minor', amounts.bonus_minor,
    'referral_minor', amounts.referral_minor,
    'portfolio_minor', amounts.balance_minor + amounts.invested_minor
  ) order by p.created_at desc) into v_rows
  from (
    select p.id, p.full_name, p.country, p.phone, p.status, p.verification_status,
           p.referral_code, p.created_at, u.email, ar.role
    from public.profiles p
    join auth.users u on u.id = p.id
    left join public.admin_roles ar on ar.user_id = p.id
    where (coalesce(p_search, '') = ''
        or p.full_name ilike '%' || p_search || '%'
        or u.email ilike '%' || p_search || '%'
        or p.id::text = p_search)
      and (coalesce(p_status, 'All users') in ('All users', '')
        or lower(p.status::text) = lower(p_status)
        or (p_status = 'Verified' and p.verification_status = 'verified')
        or (p_status = 'Pending verification' and p.verification_status <> 'verified'))
    order by p.created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 200))
    offset greatest(0, coalesce(p_offset, 0))
  ) p
  cross join lateral (
    select
      case upper(btrim(coalesce(p.country, '')))
        when 'RW' then 'RWF'
        when 'RWANDA' then 'RWF'
        when 'BI' then 'BIF'
        when 'BURUNDI' then 'BIF'
        else 'USD'
      end as asset_code,
      coalesce((
        select sum(le.amount_minor)
        from public.asset_accounts aa
        join public.ledger_entries le on le.account_id = aa.id
        where aa.owner_id = p.id
          and aa.asset_code = case upper(btrim(coalesce(p.country, '')))
            when 'RW' then 'RWF'
            when 'RWANDA' then 'RWF'
            when 'BI' then 'BIF'
            when 'BURUNDI' then 'BIF'
            else 'USD'
          end
      ), 0) as balance_minor,
      coalesce((
        select sum(i.principal_minor)
        from public.investments i
        where i.owner_id = p.id
          and i.asset_code = case upper(btrim(coalesce(p.country, '')))
            when 'RW' then 'RWF'
            when 'RWANDA' then 'RWF'
            when 'BI' then 'BIF'
            when 'BURUNDI' then 'BIF'
            else 'USD'
          end
          and i.status in ('active', 'pending')
      ), 0) as invested_minor,
      coalesce((
        select sum(t.amount_minor)
        from public.ledger_transactions t
        where t.owner_id = p.id
          and t.asset_code = case upper(btrim(coalesce(p.country, '')))
            when 'RW' then 'RWF'
            when 'RWANDA' then 'RWF'
            when 'BI' then 'BIF'
            when 'BURUNDI' then 'BIF'
            else 'USD'
          end
          and t.kind::text = 'bonus_credit'
          and t.status = 'completed'
      ), 0) as bonus_minor,
      coalesce((
        select sum(c.amount_minor)
        from public.referral_commissions c
        join public.ledger_transactions t on t.id = c.qualifying_transaction_id
        where c.referrer_id = p.id
          and c.status = 'credited'
          and t.asset_code = case upper(btrim(coalesce(p.country, '')))
            when 'RW' then 'RWF'
            when 'RWANDA' then 'RWF'
            when 'BI' then 'BIF'
            when 'BURUNDI' then 'BIF'
            else 'USD'
          end
      ), 0) as referral_minor
  ) amounts;

  return jsonb_build_object('total', v_total, 'rows', coalesce(v_rows, '[]'::jsonb));
end;
$$;

create or replace function public.admin_credit_wallet(
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
    raise exception 'Credit amount must be greater than zero';
  end if;
  if p_asset_code is null or p_asset_code not in ('USD','RWF','BIF','BTC','ETH','USDT','USDC') then
    raise exception 'Unsupported account currency';
  end if;
  if v_reason is null or length(v_reason) > 500 then
    raise exception 'A reason of up to 500 characters is required';
  end if;
  if p_idempotency_key is null or p_idempotency_key !~ '^admin-wallet:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'Invalid wallet credit request key';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key, 0));
  select * into v_existing
  from public.ledger_transactions
  where idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_existing.owner_id <> p_user_id
      or v_existing.kind::text <> 'wallet_credit'
      or v_existing.asset_code <> p_asset_code
      or v_existing.amount_minor <> p_amount_minor
      or v_existing.status <> 'completed' then
      raise exception 'Wallet credit request key was already used for a different credit';
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
    'wallet_credit',
    p_asset_code,
    p_amount_minor,
    'Administrator wallet credit: ' || v_reason,
    p_idempotency_key
  );
  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    'admin_wallet_credited',
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

revoke all on function public.admin_list_users(text,text,integer,integer) from public;
grant execute on function public.admin_list_users(text,text,integer,integer) to authenticated;
revoke all on function public.admin_credit_wallet(uuid,bigint,text,text,text) from public;
grant execute on function public.admin_credit_wallet(uuid,bigint,text,text,text) to authenticated;
