alter table public.referral_commissions
  add column source text not null default 'automatic'
    check (source in ('automatic', 'admin_manual')),
  add column credit_transaction_id uuid references public.ledger_transactions(id),
  add column admin_request_id uuid unique,
  add column admin_actor_id uuid references public.profiles(id),
  add column admin_reason text;

update public.referral_commissions c
set credit_transaction_id = t.id
from public.ledger_transactions t
where t.idempotency_key = 'referral:' || c.invitee_id::text;

create unique index referral_commissions_credit_transaction
  on public.referral_commissions(credit_transaction_id)
  where credit_transaction_id is not null;

alter table public.referral_commissions
  drop constraint if exists referral_commissions_rate_bps_check,
  add constraint referral_commissions_source_rate_check
    check (
      (source = 'automatic' and rate_bps = 5000
        and admin_request_id is null and admin_actor_id is null and admin_reason is null)
      or
      (source = 'admin_manual' and rate_bps = 0
        and admin_request_id is not null and admin_actor_id is not null
        and nullif(btrim(admin_reason), '') is not null)
    );

create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  referrer uuid;
  v_code text;
  v_invite text;
  v_invitation public.invitations;
begin
  v_code := upper(trim(coalesce(new.raw_user_meta_data->>'referral_code','')));
  if v_code <> '' then
    select p.id into referrer
    from public.profiles p
    where p.referral_code = v_code and p.id <> new.id
    limit 1;
  end if;

  insert into public.profiles(id, full_name, country, phone, referred_by)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), split_part(coalesce(new.email, ''), '@', 1)),
    nullif(trim(new.raw_user_meta_data->>'country'), ''),
    nullif(trim(new.raw_user_meta_data->>'phone'), ''),
    referrer
  );

  v_invite := nullif(trim(coalesce(new.raw_user_meta_data->>'invite_token', '')), '');
  if v_invite is not null then
    select * into v_invitation
    from public.invitations i
    where i.token = v_invite
    for update;
    if found
      and v_invitation.status = 'pending'
      and v_invitation.inviter_id <> new.id
      and lower(v_invitation.email) = lower(coalesce(new.email, '')) then
      update public.profiles
      set referred_by = v_invitation.inviter_id, updated_at = now()
      where id = new.id;
      update public.invitations
      set status = 'accepted', invitee_id = new.id, accepted_at = now()
      where id = v_invitation.id;
    end if;
  end if;

  insert into public.asset_accounts(owner_id, asset_code)
  values (new.id, 'USD'), (new.id, 'RWF'), (new.id, 'BIF'), (new.id, 'BTC'),
         (new.id, 'ETH'), (new.id, 'USDT'), (new.id, 'USDC');
  return new;
end;
$$;

create or replace function public.credit_referral_commission(p_investment_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_investment public.investments;
  v_referrer uuid;
  v_amount bigint;
  v_credit_tx uuid;
  v_qualifying_tx uuid;
begin
  select * into v_investment
  from public.investments
  where id = p_investment_id
    and status in ('active','completed')
    and activated_at is not null;
  if not found then
    return jsonb_build_object('credited', false, 'reason', 'investment_not_active');
  end if;

  select p.referred_by into v_referrer
  from public.profiles p
  where p.id = v_investment.owner_id;
  if v_referrer is null or v_referrer = v_investment.owner_id then
    return jsonb_build_object('credited', false, 'reason', 'no_referrer');
  end if;
  if exists (
    select 1 from public.referral_commissions c
    where c.invitee_id = v_investment.owner_id
  ) then
    return jsonb_build_object('credited', false, 'reason', 'already_credited');
  end if;

  v_amount := v_investment.principal_minor / 2;
  if v_amount <= 0 then
    return jsonb_build_object('credited', false, 'reason', 'amount_too_small');
  end if;

  select t.id into v_qualifying_tx
  from public.ledger_transactions t
  where t.idempotency_key = 'investment:' || p_investment_id::text
  limit 1;
  v_credit_tx := public.post_ledger(
    v_referrer,
    'referral_commission',
    v_investment.asset_code,
    v_amount,
    'Referral commission from ' || v_investment.owner_id::text,
    'referral:' || v_investment.owner_id::text
  );
  insert into public.referral_commissions(
    referrer_id, invitee_id, qualifying_transaction_id, rate_bps, amount_minor,
    status, credited_at, credit_transaction_id, source
  ) values (
    v_referrer, v_investment.owner_id, coalesce(v_qualifying_tx, v_credit_tx),
    5000, v_amount, 'credited', now(), v_credit_tx, 'automatic'
  );
  return jsonb_build_object(
    'credited', true,
    'amount_minor', v_amount,
    'referrer_id', v_referrer,
    'credit_transaction_id', v_credit_tx
  );
exception
  when unique_violation then
    return jsonb_build_object('credited', false, 'reason', 'already_credited');
end;
$$;

revoke all on function public.credit_referral_commission(uuid) from public;
grant execute on function public.credit_referral_commission(uuid) to service_role;

create or replace function public.accept_invitation(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_invitation public.invitations;
  v_invitee public.profiles;
  v_email text;
  v_investment_id uuid;
  v_commission jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  select lower(u.email) into v_email
  from auth.users u
  where u.id = auth.uid();
  select * into v_invitation
  from public.invitations i
  where i.token = p_token
  for update;
  if not found then
    raise exception 'Invitation not found';
  end if;
  if v_invitation.inviter_id = auth.uid() then
    raise exception 'You cannot accept your own invitation';
  end if;
  if v_invitation.status = 'accepted'
    and v_invitation.invitee_id is distinct from auth.uid() then
    raise exception 'Invitation was already accepted by another account';
  end if;
  if v_invitation.status not in ('pending','accepted') then
    raise exception 'Invitation is no longer active';
  end if;
  if v_email is null or lower(v_invitation.email) <> v_email then
    raise exception 'This invitation was sent to a different email address';
  end if;

  select * into v_invitee
  from public.profiles p
  where p.id = auth.uid()
  for update;
  if not found then
    raise exception 'Member profile not found';
  end if;
  if v_invitee.referred_by is not null
    and v_invitee.referred_by <> v_invitation.inviter_id then
    raise exception 'This account is already linked to a different referrer';
  end if;
  if v_invitee.referred_by is null then
    update public.profiles
    set referred_by = v_invitation.inviter_id, updated_at = now()
    where id = auth.uid();
  end if;
  if v_invitation.status = 'pending' then
    update public.invitations
    set status = 'accepted', invitee_id = auth.uid(), accepted_at = now()
    where id = v_invitation.id;
  end if;

  select i.id into v_investment_id
  from public.investments i
  where i.owner_id = auth.uid()
    and i.creation_source = 'member'
    and i.activated_at is not null
    and i.status in ('active','completed')
  order by i.activated_at, i.created_at
  limit 1;
  if v_investment_id is not null then
    v_commission := public.credit_referral_commission(v_investment_id);
  end if;

  return jsonb_build_object(
    'status', 'accepted',
    'already_accepted', v_invitation.status = 'accepted',
    'commission', v_commission
  );
end;
$$;

revoke all on function public.accept_invitation(text) from public;
grant execute on function public.accept_invitation(text) to authenticated;

create or replace function public.member_referral_summary()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'direct_referrals', (
      select count(*) from public.profiles p where p.referred_by = auth.uid()
    ),
    'qualifying_referrals', (
      select count(*) from public.referral_commissions c
      where c.referrer_id = auth.uid() and c.status in ('credited','pending')
    ),
    'credited_minor', coalesce((
      select sum(c.amount_minor)
      from public.referral_commissions c
      join public.ledger_transactions t on t.id = c.qualifying_transaction_id
      where c.referrer_id = auth.uid() and c.status = 'credited'
        and t.asset_code = public.currency_for_country((
          select p.country from public.profiles p where p.id = auth.uid()
        ))
    ), 0),
    'pending_minor', coalesce((
      select sum(c.amount_minor)
      from public.referral_commissions c
      join public.ledger_transactions t on t.id = c.qualifying_transaction_id
      where c.referrer_id = auth.uid() and c.status = 'pending'
        and t.asset_code = public.currency_for_country((
          select p.country from public.profiles p where p.id = auth.uid()
        ))
    ), 0),
    'credited_by_asset', coalesce((
      select jsonb_object_agg(totals.asset_code, totals.amount_minor::text)
      from (
        select t.asset_code, sum(c.amount_minor) as amount_minor
        from public.referral_commissions c
        join public.ledger_transactions t on t.id = c.qualifying_transaction_id
        where c.referrer_id = auth.uid() and c.status = 'credited'
        group by t.asset_code
      ) totals
    ), '{}'::jsonb),
    'pending_by_asset', coalesce((
      select jsonb_object_agg(totals.asset_code, totals.amount_minor::text)
      from (
        select t.asset_code, sum(c.amount_minor) as amount_minor
        from public.referral_commissions c
        join public.ledger_transactions t on t.id = c.qualifying_transaction_id
        where c.referrer_id = auth.uid() and c.status = 'pending'
        group by t.asset_code
      ) totals
    ), '{}'::jsonb),
    'commission_rows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'amount_minor', c.amount_minor::text,
        'asset_code', t.asset_code,
        'status', c.status,
        'source', c.source,
        'created_at', c.created_at
      ) order by c.created_at desc)
      from public.referral_commissions c
      join public.ledger_transactions t on t.id = c.qualifying_transaction_id
      where c.referrer_id = auth.uid()
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.member_referral_summary() from public;
grant execute on function public.member_referral_summary() to authenticated;

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
    'source', c.source,
    'admin_reason', c.admin_reason,
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

revoke all on function public.admin_referral_list() from public;
grant execute on function public.admin_referral_list() to authenticated;

create or replace function public.admin_list_referral_candidates(
  p_search text default '',
  p_limit integer default 100
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;

  select jsonb_agg(jsonb_build_object(
    'invitee_id', candidates.id,
    'invitee_name', coalesce(nullif(candidates.full_name, ''), split_part(candidates.email, '@', 1), 'Member'),
    'invitee_email', candidates.email,
    'has_referrer', candidates.referred_by is not null,
    'referrer_name', coalesce(nullif(referrer.full_name, ''), split_part(referrer_user.email, '@', 1)),
    'asset_code', candidates.asset_code
  ) order by candidates.created_at desc) into v_rows
  from (
    select p.id, p.full_name, p.referred_by, p.created_at, u.email, qualifying.asset_code
    from public.profiles p
    join auth.users u on u.id = p.id
    cross join lateral (
      select i.asset_code
      from public.investments i
      where i.owner_id = p.id
        and i.creation_source = 'member'
        and i.activated_at is not null
        and i.status in ('active','completed')
      order by i.activated_at, i.created_at
      limit 1
    ) qualifying
    where not exists (
      select 1 from public.referral_commissions c where c.invitee_id = p.id
    )
      and (
        coalesce(p_search, '') = ''
        or p.full_name ilike '%' || p_search || '%'
        or u.email ilike '%' || p_search || '%'
        or p.id::text = p_search
      )
    order by p.created_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 200))
  ) candidates
  left join public.profiles referrer on referrer.id = candidates.referred_by
  left join auth.users referrer_user on referrer_user.id = candidates.referred_by;
  return jsonb_build_object('rows', coalesce(v_rows, '[]'::jsonb));
end;
$$;

revoke all on function public.admin_list_referral_candidates(text,integer) from public;
grant execute on function public.admin_list_referral_candidates(text,integer) to authenticated;

create or replace function public.admin_grant_referral_commission(
  p_invitee_id uuid,
  p_amount_minor bigint,
  p_referral_code text,
  p_reason text,
  p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_existing public.referral_commissions;
  v_invitee public.profiles;
  v_referrer public.profiles;
  v_investment public.investments;
  v_qualifying_tx uuid;
  v_credit_tx uuid;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.has_admin_role(array['super_admin','finance']) then
    raise exception 'Finance administrator access required';
  end if;
  if p_invitee_id is null or p_request_id is null then
    raise exception 'Invalid manual referral commission request';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Commission amount must be greater than zero';
  end if;
  if v_reason is null or length(v_reason) > 500 then
    raise exception 'A reason of up to 500 characters is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('admin-referral:' || p_request_id::text, 0));
  select * into v_existing
  from public.referral_commissions c
  where c.admin_request_id = p_request_id
  for update;
  if found then
    if v_existing.admin_actor_id <> auth.uid()
      or v_existing.invitee_id <> p_invitee_id
      or v_existing.amount_minor <> p_amount_minor
      or v_existing.admin_reason <> v_reason then
      raise exception 'Manual commission request key was already used for a different payout';
    end if;
    return jsonb_build_object(
      'commission_id', v_existing.id,
      'referrer_id', v_existing.referrer_id,
      'invitee_id', v_existing.invitee_id,
      'amount_minor', v_existing.amount_minor,
      'asset_code', (
        select t.asset_code from public.ledger_transactions t
        where t.id = v_existing.qualifying_transaction_id
      ),
      'status', v_existing.status,
      'source', v_existing.source
    );
  end if;

  select * into v_invitee
  from public.profiles p
  where p.id = p_invitee_id
  for update;
  if not found then
    raise exception 'Invitee not found';
  end if;
  if exists (
    select 1 from public.referral_commissions c where c.invitee_id = p_invitee_id
  ) then
    raise exception 'A referral commission has already been recorded for this invitee';
  end if;

  if v_invitee.referred_by is null then
    if nullif(btrim(coalesce(p_referral_code, '')), '') is null then
      raise exception 'Enter the referrer''s referral code because this invitee is not linked to a referrer';
    end if;
    select * into v_referrer
    from public.profiles p
    where p.referral_code = upper(btrim(p_referral_code))
    for share;
    if not found then
      raise exception 'Referrer referral code was not found';
    end if;
    if v_referrer.id = p_invitee_id then
      raise exception 'An invitee cannot be their own referrer';
    end if;
    update public.profiles
    set referred_by = v_referrer.id, updated_at = now()
    where id = p_invitee_id;
  else
    select * into v_referrer
    from public.profiles p
    where p.id = v_invitee.referred_by;
    if nullif(btrim(coalesce(p_referral_code, '')), '') is not null
      and v_referrer.referral_code <> upper(btrim(p_referral_code)) then
      raise exception 'The referral code does not match the invitee''s existing referrer';
    end if;
  end if;

  select * into v_investment
  from public.investments i
  where i.owner_id = p_invitee_id
    and i.creation_source = 'member'
    and i.activated_at is not null
    and i.status in ('active','completed')
  order by i.activated_at, i.created_at
  limit 1;
  if not found then
    raise exception 'The invitee has no activated member investment eligible for referral commission';
  end if;
  select t.id into v_qualifying_tx
  from public.ledger_transactions t
  where t.idempotency_key = 'investment:' || v_investment.id::text
  limit 1;
  if v_qualifying_tx is null then
    raise exception 'The qualifying investment transaction was not found';
  end if;

  v_credit_tx := public.post_ledger(
    v_referrer.id,
    'referral_commission',
    v_investment.asset_code,
    p_amount_minor,
    'Manual referral commission for ' || p_invitee_id::text,
    'admin-referral:' || p_request_id::text
  );
  insert into public.referral_commissions(
    referrer_id, invitee_id, qualifying_transaction_id, rate_bps, amount_minor,
    status, credited_at, source, credit_transaction_id, admin_request_id,
    admin_actor_id, admin_reason
  ) values (
    v_referrer.id, p_invitee_id, v_qualifying_tx, 0, p_amount_minor,
    'credited', now(), 'admin_manual', v_credit_tx, p_request_id,
    auth.uid(), v_reason
  ) returning * into v_existing;

  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    'admin_referral_commission_granted',
    'referral_commission',
    v_existing.id,
    jsonb_build_object(
      'referrer_id', v_referrer.id,
      'invitee_id', p_invitee_id,
      'amount_minor', p_amount_minor,
      'asset_code', v_investment.asset_code,
      'qualifying_investment_id', v_investment.id,
      'qualifying_transaction_id', v_qualifying_tx,
      'credit_transaction_id', v_credit_tx,
      'source', 'admin_manual',
      'request_id', p_request_id,
      'attribution_repaired', v_invitee.referred_by is null,
      'reason', v_reason
    )
  );

  return jsonb_build_object(
    'commission_id', v_existing.id,
    'referrer_id', v_referrer.id,
    'invitee_id', p_invitee_id,
    'amount_minor', p_amount_minor,
    'asset_code', v_investment.asset_code,
    'status', 'credited',
    'source', 'admin_manual'
  );
end;
$$;

revoke all on function public.admin_grant_referral_commission(uuid,bigint,text,text,uuid) from public, anon;
grant execute on function public.admin_grant_referral_commission(uuid,bigint,text,text,uuid) to authenticated;
