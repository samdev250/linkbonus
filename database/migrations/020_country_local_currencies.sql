create table public.country_currency_map (
  country_code text primary key,
  currency_code text not null
);

insert into public.country_currency_map(country_code, currency_code)
select split_part(pair, '=', 1), split_part(pair, '=', 2)
from unnest(string_to_array(
  'AD=EUR,AE=AED,AF=AFN,AG=XCD,AI=XCD,AL=ALL,AM=AMD,AN=ANG,AO=AOA,AQ=USD,AR=ARS,AS=USD,AT=EUR,AU=AUD,AW=AWG,AX=EUR,AZ=AZN,BA=BAM,BB=BBD,BD=BDT,BE=EUR,BF=XOF,BG=EUR,BH=BHD,BI=BIF,BJ=XOF,BL=EUR,BM=BMD,BN=BND,BO=BOB,BQ=USD,BR=BRL,BS=BSD,BT=BTN,BV=NOK,BW=BWP,BY=BYN,BZ=BZD,CA=CAD,CC=AUD,CD=CDF,CF=XAF,CG=XAF,CH=CHF,CI=XOF,CK=NZD,CL=CLP,CM=XAF,CN=CNY,CO=COP,CR=CRC,CU=CUP,CV=CVE,CW=XCG,CX=AUD,CY=EUR,CZ=CZK,DE=EUR,DJ=DJF,DK=DKK,DM=XCD,DO=DOP,DZ=DZD,EC=USD,EE=EUR,EG=EGP,EH=MAD,ER=ERN,ES=EUR,ET=ETB,FI=EUR,FJ=FJD,FK=FKP,FM=USD,FO=DKK,FR=EUR,GA=XAF,GB=GBP,GD=XCD,GE=GEL,GF=EUR,GG=GBP,GH=GHS,GI=GIP,GL=DKK,GM=GMD,GN=GNF,GP=EUR,GQ=XAF,GR=EUR,GS=FKP,GT=GTQ,GU=USD,GW=XOF,GY=GYD,HK=HKD,HM=AUD,HN=HNL,HR=EUR,HT=HTG,HU=HUF,ID=IDR,IE=EUR,IL=ILS,IM=GBP,IN=INR,IO=USD,IQ=IQD,IR=IRR,IS=ISK,IT=EUR,JE=GBP,JM=JMD,JO=JOD,JP=JPY,KE=KES,KG=KGS,KH=KHR,KI=AUD,KM=KMF,KN=XCD,KP=KPW,KR=KRW,KW=KWD,KY=KYD,KZ=KZT,LA=LAK,LB=LBP,LC=XCD,LI=CHF,LK=LKR,LR=LRD,LS=LSL,LT=EUR,LU=EUR,LV=EUR,LY=LYD,MA=MAD,MC=EUR,MD=MDL,ME=EUR,MF=EUR,MG=MGA,MH=USD,MK=MKD,ML=XOF,MM=MMK,MN=MNT,MO=MOP,MP=USD,MQ=EUR,MR=MRU,MS=XCD,MT=EUR,MU=MUR,MV=MVR,MW=MWK,MX=MXN,MY=MYR,MZ=MZN,NA=NAD,NC=XPF,NE=XOF,NF=AUD,NG=NGN,NI=NIO,NL=EUR,NO=NOK,NP=NPR,NR=AUD,NU=NZD,NZ=NZD,OM=OMR,PA=PAB,PE=PEN,PF=XPF,PG=PGK,PH=PHP,PK=PKR,PL=PLN,PM=EUR,PN=NZD,PR=USD,PS=ILS,PT=EUR,PW=USD,PY=PYG,QA=QAR,RE=EUR,RO=RON,RS=RSD,RU=RUB,RW=RWF,SA=SAR,SB=SBD,SC=SCR,SD=SDG,SE=SEK,SG=SGD,SH=SHP,SI=EUR,SJ=NOK,SK=EUR,SL=SLE,SM=EUR,SN=XOF,SO=SOS,SR=SRD,SS=SSP,ST=STN,SV=USD,SX=XCG,SY=SYP,SZ=SZL,TC=USD,TD=XAF,TF=EUR,TG=XOF,TH=THB,TJ=TJS,TK=NZD,TL=USD,TM=TMT,TN=TND,TO=TOP,TR=TRY,TT=TTD,TV=AUD,TW=TWD,TZ=TZS,UA=UAH,UG=UGX,UM=USD,US=USD,UY=UYU,UZ=UZS,VA=EUR,VC=XCD,VE=VES,VG=USD,VI=USD,VN=VND,VU=VUV,WF=XPF,WS=WST,XK=EUR,YE=YER,YT=EUR,ZA=ZAR,ZM=ZMW,ZW=ZWG',
  ','
)) as mappings(pair);

create table public.supported_currencies (
  code text primary key
);

insert into public.supported_currencies(code)
select distinct currency_code from public.country_currency_map
union
select unnest(array['BTC','ETH','USDT','USDC']::text[]);

alter table public.country_currency_map
  add constraint country_currency_map_currency_code_fkey
  foreign key (currency_code) references public.supported_currencies(code);

alter table public.supported_currencies enable row level security;
alter table public.country_currency_map enable row level security;
revoke all on public.supported_currencies, public.country_currency_map from public, anon, authenticated;

alter table public.asset_accounts drop constraint if exists asset_accounts_asset_code_check;
alter table public.asset_accounts
  add constraint asset_accounts_asset_code_fkey
  foreign key (asset_code) references public.supported_currencies(code);

alter table public.investments drop constraint if exists investments_asset_code_check;
alter table public.investments
  add constraint investments_asset_code_fkey
  foreign key (asset_code) references public.supported_currencies(code);

alter table public.investment_plans
  add constraint investment_plans_settlement_asset_code_fkey
  foreign key (settlement_asset_code) references public.supported_currencies(code);

create or replace function public.currency_for_country(p_country text)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((
    select c.currency_code
    from public.country_currency_map c
    where c.country_code = case upper(btrim(coalesce(p_country, '')))
      when 'RWANDA' then 'RW'
      when 'BURUNDI' then 'BI'
      else upper(btrim(coalesce(p_country, '')))
    end
  ), 'USD');
$$;

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
  if not exists (
    select 1 from public.supported_currencies c where c.code = p_asset_code
  ) then
    raise exception 'Unsupported account currency';
  end if;
  insert into public.asset_accounts(owner_id, asset_code)
  values (p_owner_id, p_asset_code)
  on conflict (owner_id, asset_code) do nothing;
  select a.id into v_account_id
  from public.asset_accounts a
  where a.owner_id = p_owner_id and a.asset_code = p_asset_code
  for update;
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

create or replace function public.provision_profile_currency_account()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.asset_accounts(owner_id, asset_code)
  values (new.id, public.currency_for_country(new.country))
  on conflict (owner_id, asset_code) do nothing;
  return new;
end;
$$;

create trigger profiles_provision_currency_account_insert
after insert on public.profiles
for each row execute function public.provision_profile_currency_account();

create trigger profiles_provision_currency_account_update
after update of country on public.profiles
for each row execute function public.provision_profile_currency_account();

insert into public.asset_accounts(owner_id, asset_code)
select p.id, public.currency_for_country(p.country)
from public.profiles p
where p.country is not null
on conflict (owner_id, asset_code) do nothing;

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
  v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Admin user update');
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
  if p_asset_code is null or not exists (
    select 1 from public.supported_currencies c where c.code = p_asset_code
  ) then
    raise exception 'Unsupported account currency';
  end if;
  if nullif(btrim(coalesce(p_full_name, '')), '') is null then
    raise exception 'Full name is required';
  end if;
  if p_wallet_target_minor is null or p_wallet_target_minor < 0
    or p_bonus_target_minor is null or p_bonus_target_minor < 0 then
    raise exception 'Wallet and bonus totals must be zero or greater';
  end if;
  if length(v_reason) > 500 then
    raise exception 'Update description must be 500 characters or fewer';
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
  insert into public.asset_accounts(owner_id, asset_code)
  values (p_id, p_asset_code)
  on conflict (owner_id, asset_code) do nothing;
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
    select public.currency_for_country(p.country) as asset_code
  ) preferred
  cross join lateral (
    select
      preferred.asset_code,
      coalesce((
        select sum(le.amount_minor)
        from public.asset_accounts aa
        join public.ledger_entries le on le.account_id = aa.id
        where aa.owner_id = p.id and aa.asset_code = preferred.asset_code
      ), 0) as balance_minor,
      coalesce((
        select sum(i.principal_minor)
        from public.investments i
        where i.owner_id = p.id
          and i.asset_code = preferred.asset_code
          and i.status in ('active', 'pending')
      ), 0) as invested_minor,
      coalesce((
        select sum(le.amount_minor)
        from public.asset_accounts aa
        join public.ledger_entries le on le.account_id = aa.id
        join public.ledger_transactions t on t.id = le.transaction_id
        where aa.owner_id = p.id
          and aa.asset_code = preferred.asset_code
          and t.status = 'completed'
          and t.kind::text in ('bonus_credit','bonus_debit')
      ), 0) as bonus_minor,
      coalesce((
        select sum(c.amount_minor)
        from public.referral_commissions c
        join public.ledger_transactions t on t.id = c.qualifying_transaction_id
        where c.referrer_id = p.id
          and c.status = 'credited'
          and t.asset_code = preferred.asset_code
      ), 0) as referral_minor
  ) amounts;

  return jsonb_build_object('total', v_total, 'rows', coalesce(v_rows, '[]'::jsonb));
end;
$$;

revoke all on function public.currency_for_country(text) from public;
grant execute on function public.currency_for_country(text) to authenticated;
revoke all on function public.post_ledger(uuid,text,text,bigint,text,text) from public, anon, authenticated;
grant execute on function public.post_ledger(uuid,text,text,bigint,text,text) to service_role;
revoke all on function public.admin_update_user_account(uuid,text,text,text,text,text,text,bigint,bigint,text,uuid) from public;
grant execute on function public.admin_update_user_account(uuid,text,text,text,text,text,text,bigint,bigint,text,uuid) to authenticated;
revoke all on function public.admin_list_users(text,text,integer,integer) from public;
grant execute on function public.admin_list_users(text,text,integer,integer) to authenticated;

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
  if p_asset_code is null or not exists (
    select 1 from public.supported_currencies c where c.code = p_asset_code
  ) then
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
  if p_asset_code is null or not exists (
    select 1 from public.supported_currencies c where c.code = p_asset_code
  ) then
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
  if not exists (select 1 from public.supported_currencies c where c.code = v_asset) then
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

create or replace function public.member_referral_summary()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'direct_referrals', (select count(*) from public.profiles p where p.referred_by = auth.uid()),
    'qualifying_referrals', (select count(*) from public.referral_commissions c where c.referrer_id = auth.uid() and c.status in ('credited','pending')),
    'credited_minor', coalesce((
      select sum(c.amount_minor)
      from public.referral_commissions c
      join public.ledger_transactions t on t.id = c.qualifying_transaction_id
      where c.referrer_id = auth.uid() and c.status = 'credited'
        and t.asset_code = public.currency_for_country((select p.country from public.profiles p where p.id = auth.uid()))
    ), 0),
    'pending_minor', coalesce((
      select sum(c.amount_minor)
      from public.referral_commissions c
      join public.ledger_transactions t on t.id = c.qualifying_transaction_id
      where c.referrer_id = auth.uid() and c.status = 'pending'
        and t.asset_code = public.currency_for_country((select p.country from public.profiles p where p.id = auth.uid()))
    ), 0),
    'credited_by_asset', coalesce((
      select jsonb_object_agg(totals.asset_code, totals.amount_minor::text)
      from (
        select tx.asset_code, sum(c.amount_minor) as amount_minor
        from public.referral_commissions c
        join public.ledger_transactions tx on tx.id = c.qualifying_transaction_id
        where c.referrer_id = auth.uid() and c.status = 'credited'
        group by tx.asset_code
      ) totals
    ), '{}'::jsonb),
    'pending_by_asset', coalesce((
      select jsonb_object_agg(totals.asset_code, totals.amount_minor::text)
      from (
        select tx.asset_code, sum(c.amount_minor) as amount_minor
        from public.referral_commissions c
        join public.ledger_transactions tx on tx.id = c.qualifying_transaction_id
        where c.referrer_id = auth.uid() and c.status = 'pending'
        group by tx.asset_code
      ) totals
    ), '{}'::jsonb),
    'commission_rows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'amount_minor', c.amount_minor::text,
        'asset_code', t.asset_code,
        'status', c.status,
        'created_at', c.created_at
      ) order by c.created_at desc)
      from public.referral_commissions c
      join public.ledger_transactions t on t.id = c.qualifying_transaction_id
      where c.referrer_id = auth.uid()
    ), '[]'::jsonb)
  );
$$;

create or replace function public.admin_referral_list()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rows jsonb;
  v_total bigint;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  select count(*) into v_total from public.referral_commissions;
  select jsonb_agg(jsonb_build_object(
    'id', c.id,
    'referrer', coalesce(nullif(pr.full_name, ''), split_part(u.email, '@', 1), 'Member'),
    'invitee', coalesce(nullif(pi.full_name, ''), split_part(ui.email, '@', 1), 'Member'),
    'amount_minor', c.amount_minor,
    'asset_code', t.asset_code,
    'status', c.status,
    'created_at', c.created_at,
    'credited_at', c.credited_at
  ) order by c.created_at desc) into v_rows
  from (select * from public.referral_commissions order by created_at desc limit 200) c
  left join public.ledger_transactions t on t.id = c.qualifying_transaction_id
  left join public.profiles pr on pr.id = c.referrer_id
  left join auth.users u on u.id = c.referrer_id
  left join public.profiles pi on pi.id = c.invitee_id
  left join auth.users ui on ui.id = c.invitee_id;
  return jsonb_build_object('total', v_total, 'rows', coalesce(v_rows, '[]'::jsonb));
end;
$$;

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
    'deposits_by_asset', coalesce((
      select jsonb_object_agg(asset_code, amount_minor::text)
      from (select asset_code, sum(amount_minor) as amount_minor from public.ledger_transactions where kind = 'deposit' and status = 'completed' group by asset_code) totals
    ), '{}'::jsonb),
    'withdrawals_by_asset', coalesce((
      select jsonb_object_agg(asset_code, amount_minor::text)
      from (select asset_code, sum(amount_minor) as amount_minor from public.ledger_transactions where kind = 'withdrawal' and status = 'completed' group by asset_code) totals
    ), '{}'::jsonb),
    'bonuses_by_asset', coalesce((
      select jsonb_object_agg(asset_code, amount_minor::text)
      from (select asset_code, sum(amount_minor) as amount_minor from public.ledger_transactions where kind::text = 'bonus_credit' and status = 'completed' group by asset_code) totals
    ), '{}'::jsonb),
    'referrals_by_asset', coalesce((
      select jsonb_object_agg(asset_code, amount_minor::text)
      from (
        select t.asset_code, sum(c.amount_minor) as amount_minor
        from public.referral_commissions c
        join public.ledger_transactions t on t.id = c.qualifying_transaction_id
        where c.status = 'credited'
        group by t.asset_code
      ) totals
    ), '{}'::jsonb),
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

revoke all on function public.member_referral_summary() from public;
grant execute on function public.member_referral_summary() to authenticated;
revoke all on function public.admin_referral_list() from public;
grant execute on function public.admin_referral_list() to authenticated;
revoke all on function public.admin_overview() from public;
grant execute on function public.admin_overview() to authenticated;

create or replace function public.member_roi_summary()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'paid_minor', coalesce((
      select sum(i.total_roi_paid_minor)
      from public.investments i
      where i.owner_id = auth.uid()
        and i.asset_code = public.currency_for_country((select p.country from public.profiles p where p.id = auth.uid()))
    ), 0),
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
        and i.asset_code = public.currency_for_country((select p.country from public.profiles p where p.id = auth.uid()))
    ), 0),
    'daily_minor', coalesce((
      select sum(round(i.principal_minor::numeric * i.roi_rate_bps / 10000))
      from public.investments i
      where i.owner_id = auth.uid() and i.status = 'active' and i.roi_rate_bps > 0
        and i.asset_code = public.currency_for_country((select p.country from public.profiles p where p.id = auth.uid()))
    ), 0),
    'next_credit_at', (
      select min(i.next_roi_at) from public.investments i
      where i.owner_id = auth.uid() and i.status = 'active' and i.roi_rate_bps > 0
        and i.asset_code = public.currency_for_country((select p.country from public.profiles p where p.id = auth.uid()))
    ),
    'investments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'plan', pl.name, 'principal_minor', i.principal_minor,
        'asset_code', i.asset_code, 'status', i.status, 'rate_bps', i.roi_rate_bps,
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
