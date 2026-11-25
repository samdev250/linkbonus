alter type public.transaction_kind add value if not exists 'wallet_debit';
alter type public.transaction_kind add value if not exists 'bonus_debit';

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
  where a.owner_id = p_owner_id and a.asset_code = p_asset_code
  for update;
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

create table public.admin_user_update_requests (
  request_id uuid primary key,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  request_payload jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.admin_user_update_requests enable row level security;
revoke all on public.admin_user_update_requests from public, anon, authenticated;

create or replace function public.admin_update_user_account(
  p_id uuid,
  p_full_name text,
  p_country text,
  p_phone text,
  p_status text,
  p_verification_status text,
  p_asset_code text,
  p_wallet_target_minor bigint,
  p_bonus_target_minor bigint,
  p_reason text,
  p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.profiles;
  v_request public.admin_user_update_requests;
  v_request_payload jsonb;
  v_result jsonb;
  v_account_id uuid;
  v_wallet_before bigint;
  v_bonus_before bigint;
  v_wallet_delta bigint;
  v_bonus_delta bigint;
  v_wallet_after_bonus bigint;
  v_buffer_delta bigint := 0;
  v_final_wallet_delta bigint;
  v_buffer_transaction_id uuid;
  v_bonus_transaction_id uuid;
  v_wallet_transaction_id uuid;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if p_id is null or p_request_id is null then
    raise exception 'Invalid user update request';
  end if;
  if p_status is null or p_status not in ('active','suspended') then
    raise exception 'Unsupported account status';
  end if;
  if p_verification_status is null or p_verification_status not in ('unverified','pending','verified','rejected') then
    raise exception 'Unsupported verification status';
  end if;
  if p_asset_code is null or p_asset_code not in ('USD','RWF','BIF','BTC','ETH','USDT','USDC') then
    raise exception 'Unsupported account currency';
  end if;
  if nullif(btrim(coalesce(p_full_name, '')), '') is null then
    raise exception 'Full name is required';
  end if;
  if p_wallet_target_minor is null or p_wallet_target_minor < 0
    or p_bonus_target_minor is null or p_bonus_target_minor < 0 then
    raise exception 'Wallet and bonus totals must be zero or greater';
  end if;
  if v_reason is null or length(v_reason) > 500 then
    raise exception 'A reason of up to 500 characters is required';
  end if;
  if p_id = auth.uid() and p_status = 'suspended' then
    raise exception 'You cannot suspend your own account';
  end if;

  v_request_payload := jsonb_build_object(
    'user_id', p_id,
    'full_name', btrim(coalesce(p_full_name, '')),
    'country', nullif(btrim(coalesce(p_country, '')), ''),
    'phone', nullif(btrim(coalesce(p_phone, '')), ''),
    'status', p_status,
    'verification_status', p_verification_status,
    'asset_code', p_asset_code,
    'wallet_target_minor', p_wallet_target_minor,
    'bonus_target_minor', p_bonus_target_minor,
    'reason', v_reason
  );
  perform pg_advisory_xact_lock(hashtextextended('admin-user-update:' || p_request_id::text, 0));
  select * into v_request from public.admin_user_update_requests
  where request_id = p_request_id for update;
  if found then
    if v_request.actor_id <> auth.uid() or v_request_payload <> v_request.request_payload then
      raise exception 'Update request key was already used for a different change';
    end if;
    return v_request.result;
  end if;

  select * into v_profile from public.profiles where id = p_id for update;
  if not found then
    raise exception 'User not found';
  end if;
  select a.id into v_account_id
  from public.asset_accounts a
  where a.owner_id = p_id and a.asset_code = p_asset_code
  for update;
  if v_account_id is null then
    raise exception 'No account exists for the selected currency';
  end if;

  select coalesce(sum(le.amount_minor), 0) into v_wallet_before
  from public.ledger_entries le
  where le.account_id = v_account_id;
  select coalesce(sum(le.amount_minor), 0) into v_bonus_before
  from public.ledger_entries le
  join public.ledger_transactions t on t.id = le.transaction_id
  where le.account_id = v_account_id
    and t.owner_id = p_id
    and t.status = 'completed'
    and t.kind::text in ('bonus_credit','bonus_debit');

  v_wallet_delta := p_wallet_target_minor - v_wallet_before;
  v_bonus_delta := p_bonus_target_minor - v_bonus_before;
  if (v_wallet_delta <> 0 or v_bonus_delta <> 0)
    and not public.has_admin_role(array['super_admin','finance']) then
    raise exception 'Finance administrator access required to change wallet or bonus totals';
  end if;

  update public.profiles
  set full_name = coalesce(nullif(btrim(coalesce(p_full_name, '')), ''), full_name),
      country = nullif(btrim(coalesce(p_country, '')), ''),
      phone = nullif(btrim(coalesce(p_phone, '')), ''),
      status = p_status::public.account_status,
      verification_status = p_verification_status,
      updated_at = now()
  where id = p_id;

  v_wallet_after_bonus := v_wallet_before;
  if v_bonus_delta < 0 and v_wallet_after_bonus < abs(v_bonus_delta) then
    v_buffer_delta := abs(v_bonus_delta) - v_wallet_after_bonus;
    v_buffer_transaction_id := public.post_ledger(
      p_id, 'wallet_credit', p_asset_code, v_buffer_delta,
      'Administrative balance adjustment buffer: ' || v_reason,
      'admin-user-update:' || p_request_id::text || ':buffer'
    );
    v_wallet_after_bonus := v_wallet_after_bonus + v_buffer_delta;
  end if;
  if v_bonus_delta <> 0 then
    v_bonus_transaction_id := public.post_ledger(
      p_id,
      case when v_bonus_delta > 0 then 'bonus_credit' else 'bonus_debit' end,
      p_asset_code,
      v_bonus_delta,
      'Administrative bonus total adjustment: ' || v_reason,
      'admin-user-update:' || p_request_id::text || ':bonus'
    );
    v_wallet_after_bonus := v_wallet_after_bonus + v_bonus_delta;
  end if;
  v_final_wallet_delta := p_wallet_target_minor - v_wallet_after_bonus;
  if v_final_wallet_delta <> 0 then
    v_wallet_transaction_id := public.post_ledger(
      p_id,
      case when v_final_wallet_delta > 0 then 'wallet_credit' else 'wallet_debit' end,
      p_asset_code,
      v_final_wallet_delta,
      'Administrative wallet balance adjustment: ' || v_reason,
      'admin-user-update:' || p_request_id::text || ':wallet'
    );
  end if;

  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    'admin_user_account_updated',
    'profile',
    p_id,
    jsonb_build_object(
      'request_id', p_request_id,
      'asset_code', p_asset_code,
      'wallet_before_minor', v_wallet_before,
      'wallet_target_minor', p_wallet_target_minor,
      'bonus_before_minor', v_bonus_before,
      'bonus_target_minor', p_bonus_target_minor,
      'bonus_delta_minor', v_bonus_delta,
      'buffer_transaction_id', v_buffer_transaction_id,
      'bonus_transaction_id', v_bonus_transaction_id,
      'wallet_transaction_id', v_wallet_transaction_id,
      'verification_status', p_verification_status,
      'account_status', p_status,
      'reason', v_reason
    )
  );

  v_result := jsonb_build_object(
    'user_id', p_id,
    'asset_code', p_asset_code,
    'wallet_before_minor', v_wallet_before,
    'wallet_target_minor', p_wallet_target_minor,
    'bonus_before_minor', v_bonus_before,
    'bonus_target_minor', p_bonus_target_minor,
    'status', p_status,
    'verification_status', p_verification_status
  );
  insert into public.admin_user_update_requests(
    request_id, actor_id, user_id, request_payload, result
  ) values (p_request_id, auth.uid(), p_id, v_request_payload, v_result);
  return v_result;
end;
$$;

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
    'balance_minor', amounts.balance_minor::text,
    'invested_minor', amounts.invested_minor::text,
    'bonus_minor', amounts.bonus_minor::text,
    'referral_minor', amounts.referral_minor::text,
    'portfolio_minor', (amounts.balance_minor + amounts.invested_minor)::text
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
        select sum(le.amount_minor)
        from public.asset_accounts aa
        join public.ledger_entries le on le.account_id = aa.id
        join public.ledger_transactions t on t.id = le.transaction_id
        where aa.owner_id = p.id
          and aa.asset_code = case upper(btrim(coalesce(p.country, '')))
            when 'RW' then 'RWF'
            when 'RWANDA' then 'RWF'
            when 'BI' then 'BIF'
            when 'BURUNDI' then 'BIF'
            else 'USD'
          end
          and t.status = 'completed'
          and t.kind::text in ('bonus_credit','bonus_debit')
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

revoke all on function public.admin_update_user_account(uuid,text,text,text,text,text,text,bigint,bigint,text,uuid) from public;
grant execute on function public.admin_update_user_account(uuid,text,text,text,text,text,text,bigint,bigint,text,uuid) to authenticated;
