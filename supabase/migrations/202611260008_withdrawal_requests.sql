create table public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  amount_minor bigint not null check (amount_minor > 0),
  asset_code text not null,
  payout_method text not null check (payout_method in ('mobile_money', 'bank')),
  payout_provider text not null,
  payout_account_name text not null,
  payout_account_number text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  admin_note text,
  transaction_id uuid references public.ledger_transactions(id),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index withdrawal_requests_owner_created
  on public.withdrawal_requests(owner_id, created_at desc);
create index withdrawal_requests_status_created
  on public.withdrawal_requests(status, created_at desc);

alter table public.withdrawal_requests enable row level security;
revoke all on public.withdrawal_requests from public, anon, authenticated;

create or replace function public.member_create_withdrawal_request(
  p_request_id uuid,
  p_amount_minor bigint,
  p_asset_code text,
  p_payout_method text,
  p_payout_provider text,
  p_payout_account_name text,
  p_payout_account_number text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_owner_id uuid := auth.uid();
  v_country text;
  v_currency text;
  v_minimum jsonb;
  v_minimum_minor bigint;
  v_existing public.withdrawal_requests;
  v_account_id uuid;
  v_balance bigint;
  v_reserved bigint;
  v_request public.withdrawal_requests;
begin
  if v_owner_id is null then
    raise exception 'Authentication required';
  end if;
  if p_request_id is null then
    raise exception 'Invalid withdrawal request';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Withdrawal amount must be greater than zero';
  end if;
  if p_payout_method not in ('mobile_money', 'bank') then
    raise exception 'Choose mobile money or bank payout';
  end if;
  if nullif(btrim(coalesce(p_payout_provider, '')), '') is null
    or nullif(btrim(coalesce(p_payout_account_name, '')), '') is null
    or nullif(btrim(coalesce(p_payout_account_number, '')), '') is null then
    raise exception 'Complete the payout provider, account name, and account number';
  end if;

  v_minimum := public.member_get_withdrawal_minimum();
  if coalesce((v_minimum->>'configured')::boolean, false) is not true then
    raise exception 'A minimum withdrawal amount has not been configured for your country';
  end if;
  v_minimum_minor := (v_minimum->>'minimum_minor')::bigint;
  if p_amount_minor < v_minimum_minor then
    raise exception 'Withdrawal amount is below the country minimum';
  end if;

  select upper(trim(coalesce(p.country, ''))) into v_country
  from public.profiles p where p.id = v_owner_id;
  v_country := case v_country
    when 'RWANDA' then 'RW'
    when 'BURUNDI' then 'BI'
    when 'ZAMBIA' then 'ZM'
    when 'UGANDA' then 'UG'
    when 'TANZANIA' then 'TZ'
    when 'KENYA' then 'KE'
    else v_country
  end;
  v_currency := public.currency_for_country(v_country);
  if upper(trim(coalesce(p_asset_code, ''))) <> v_currency then
    raise exception 'Withdrawals must use your account currency';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('withdrawal-request:' || p_request_id::text, 0));
  select * into v_existing
  from public.withdrawal_requests r
  where r.request_id = p_request_id
  for update;
  if found then
    if v_existing.owner_id <> v_owner_id
      or v_existing.amount_minor <> p_amount_minor
      or v_existing.asset_code <> v_currency
      or v_existing.payout_method <> p_payout_method
      or v_existing.payout_provider <> btrim(p_payout_provider)
      or v_existing.payout_account_name <> btrim(p_payout_account_name)
      or v_existing.payout_account_number <> btrim(p_payout_account_number) then
      raise exception 'Withdrawal request key was already used for a different request';
    end if;
    return jsonb_build_object(
      'id', v_existing.id,
      'request_id', v_existing.request_id,
      'amount_minor', v_existing.amount_minor,
      'asset_code', v_existing.asset_code,
      'status', v_existing.status
    );
  end if;

  select a.id into v_account_id
  from public.asset_accounts a
  where a.owner_id = v_owner_id and a.asset_code = v_currency
  for update;
  if v_account_id is null then
    raise exception 'No wallet exists for your account currency';
  end if;
  select coalesce(sum(le.amount_minor), 0) into v_balance
  from public.ledger_entries le
  where le.account_id = v_account_id;
  select coalesce(sum(r.amount_minor), 0) into v_reserved
  from public.withdrawal_requests r
  where r.owner_id = v_owner_id
    and r.asset_code = v_currency
    and r.status = 'pending';
  if v_balance - v_reserved < p_amount_minor then
    raise exception 'Insufficient available balance for this withdrawal request';
  end if;

  insert into public.withdrawal_requests(
    request_id, owner_id, amount_minor, asset_code, payout_method,
    payout_provider, payout_account_name, payout_account_number
  ) values (
    p_request_id, v_owner_id, p_amount_minor, v_currency, p_payout_method,
    btrim(p_payout_provider), btrim(p_payout_account_name), btrim(p_payout_account_number)
  ) returning * into v_request;

  return jsonb_build_object(
    'id', v_request.id,
    'request_id', v_request.request_id,
    'amount_minor', v_request.amount_minor,
    'asset_code', v_request.asset_code,
    'status', v_request.status
  );
end;
$$;

create or replace function public.member_list_withdrawal_requests()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select jsonb_agg(jsonb_build_object(
    'id', r.id,
    'amount_minor', r.amount_minor::text,
    'asset_code', r.asset_code,
    'payout_method', r.payout_method,
    'payout_provider', r.payout_provider,
    'payout_account_name', r.payout_account_name,
    'payout_account_number', r.payout_account_number,
    'status', r.status,
    'admin_note', r.admin_note,
    'transaction_id', r.transaction_id,
    'created_at', r.created_at,
    'reviewed_at', r.reviewed_at
  ) order by r.created_at desc) into v_rows
  from public.withdrawal_requests r
  where r.owner_id = auth.uid();

  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

create or replace function public.admin_list_withdrawal_requests(p_status text default 'pending')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if coalesce(p_status, 'pending') not in ('pending', 'approved', 'rejected', 'all') then
    raise exception 'Unsupported withdrawal request status';
  end if;

  select jsonb_agg(jsonb_build_object(
    'id', r.id,
    'owner_id', r.owner_id,
    'member_name', coalesce(nullif(p.full_name, ''), split_part(u.email, '@', 1), 'Member'),
    'email', u.email,
    'amount_minor', r.amount_minor::text,
    'asset_code', r.asset_code,
    'payout_method', r.payout_method,
    'payout_provider', r.payout_provider,
    'payout_account_name', r.payout_account_name,
    'payout_account_number', r.payout_account_number,
    'status', r.status,
    'admin_note', r.admin_note,
    'transaction_id', r.transaction_id,
    'created_at', r.created_at,
    'reviewed_at', r.reviewed_at
  ) order by case when r.status = 'pending' then 0 else 1 end, r.created_at desc) into v_rows
  from public.withdrawal_requests r
  join public.profiles p on p.id = r.owner_id
  join auth.users u on u.id = r.owner_id
  where coalesce(p_status, 'pending') = 'all'
    or r.status = coalesce(p_status, 'pending');

  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

create or replace function public.admin_review_withdrawal_request(
  p_id uuid,
  p_action text,
  p_note text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_request public.withdrawal_requests;
  v_transaction_id uuid;
  v_status text;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if p_action is null or p_action not in ('approve', 'reject') then
    raise exception 'Unsupported withdrawal review action';
  end if;
  if p_action = 'reject' and v_note is null then
    raise exception 'A reason is required when rejecting a withdrawal';
  end if;

  select * into v_request
  from public.withdrawal_requests r
  where r.id = p_id
  for update;
  if not found then
    raise exception 'Withdrawal request not found';
  end if;
  if v_request.status <> 'pending' then
    if v_request.status = case when p_action = 'approve' then 'approved' else 'rejected' end then
      return jsonb_build_object(
        'id', v_request.id,
        'status', v_request.status,
        'transaction_id', v_request.transaction_id
      );
    end if;
    raise exception 'Withdrawal request has already been reviewed';
  end if;

  if p_action = 'approve' then
    v_transaction_id := public.post_ledger(
      v_request.owner_id,
      'withdrawal',
      v_request.asset_code,
      -v_request.amount_minor,
      'Approved withdrawal request ' || v_request.id::text,
      'withdrawal-request:' || v_request.id::text
    );
    v_status := 'approved';
  else
    v_status := 'rejected';
  end if;

  update public.withdrawal_requests
  set status = v_status,
      admin_note = v_note,
      transaction_id = v_transaction_id,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      updated_at = now()
  where id = p_id
  returning * into v_request;

  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    'withdrawal_request_' || v_status,
    'withdrawal_request',
    v_request.id,
    jsonb_build_object(
      'owner_id', v_request.owner_id,
      'amount_minor', v_request.amount_minor,
      'asset_code', v_request.asset_code,
      'payout_method', v_request.payout_method,
      'payout_provider', v_request.payout_provider,
      'payout_account_name', v_request.payout_account_name,
      'payout_account_number', v_request.payout_account_number,
      'transaction_id', v_transaction_id,
      'note', v_note
    )
  );

  return jsonb_build_object(
    'id', v_request.id,
    'status', v_request.status,
    'transaction_id', v_request.transaction_id
  );
end;
$$;

revoke all on function public.member_create_withdrawal_request(uuid, bigint, text, text, text, text, text) from public, anon;
revoke all on function public.member_list_withdrawal_requests() from public, anon;
revoke all on function public.admin_list_withdrawal_requests(text) from public, anon;
revoke all on function public.admin_review_withdrawal_request(uuid, text, text) from public, anon;
grant execute on function public.member_create_withdrawal_request(uuid, bigint, text, text, text, text, text) to authenticated;
grant execute on function public.member_list_withdrawal_requests() to authenticated;
grant execute on function public.admin_list_withdrawal_requests(text) to authenticated;
grant execute on function public.admin_review_withdrawal_request(uuid, text, text) to authenticated;
