-- Resolve both shared referral codes and private invitation tokens at signup.
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
    select p.id into referrer from public.profiles p
    where p.referral_code = v_code and p.id <> new.id limit 1;
  end if;

  insert into public.profiles(id,full_name,country,phone,referred_by)
  values(
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(coalesce(new.email,''),'@',1)),
    nullif(trim(new.raw_user_meta_data->>'country'),''),
    nullif(trim(new.raw_user_meta_data->>'phone'),''),
    referrer
  );

  v_invite := nullif(trim(coalesce(new.raw_user_meta_data->>'invite_token','')),'');
  if v_invite is not null then
    select * into v_invitation from public.invitations where token = v_invite for update;
    if found and v_invitation.status = 'pending' and v_invitation.inviter_id <> new.id then
      update public.profiles set referred_by = v_invitation.inviter_id, updated_at = now()
      where id = new.id;
      update public.invitations set status = 'accepted', invitee_id = new.id, accepted_at = now()
      where id = v_invitation.id;
    end if;
  end if;

  insert into public.asset_accounts(owner_id,asset_code)
  values(new.id,'USD'),(new.id,'RWF'),(new.id,'BIF'),(new.id,'BTC'),(new.id,'ETH'),(new.id,'USDT'),(new.id,'USDC');
  return new;
end;
$$;

-- Credit one 50% referral commission on an invitee's first activated investment.
create or replace function public.credit_referral_commission(p_investment_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_investment public.investments;
  v_referrer uuid;
  v_amount bigint;
  v_credit_tx uuid;
  v_qualifying_tx uuid;
begin
  select * into v_investment from public.investments where id = p_investment_id and status = 'active';
  if not found then
    return jsonb_build_object('credited', false, 'reason', 'investment_not_active');
  end if;

  select p.referred_by into v_referrer from public.profiles p where p.id = v_investment.owner_id;
  if v_referrer is null or v_referrer = v_investment.owner_id then
    return jsonb_build_object('credited', false, 'reason', 'no_referrer');
  end if;
  if exists (select 1 from public.referral_commissions c where c.invitee_id = v_investment.owner_id) then
    return jsonb_build_object('credited', false, 'reason', 'already_credited');
  end if;

  v_amount := (v_investment.principal_minor * 5000) / 10000;
  if v_amount <= 0 then
    return jsonb_build_object('credited', false, 'reason', 'amount_too_small');
  end if;

  select id into v_qualifying_tx from public.ledger_transactions
  where idempotency_key = 'investment:' || p_investment_id::text limit 1;
  v_credit_tx := public.post_ledger(
    v_referrer, 'referral_commission', v_investment.asset_code, v_amount,
    'Referral commission from ' || v_investment.owner_id::text,
    'referral:' || v_investment.owner_id::text
  );
  insert into public.referral_commissions(
    referrer_id, invitee_id, qualifying_transaction_id, rate_bps, amount_minor, status, credited_at
  ) values (
    v_referrer, v_investment.owner_id, coalesce(v_qualifying_tx, v_credit_tx), 5000, v_amount, 'credited', now()
  );
  return jsonb_build_object('credited', true, 'amount_minor', v_amount, 'referrer_id', v_referrer);
exception
  when unique_violation then
    return jsonb_build_object('credited', false, 'reason', 'already_credited');
end;
$$;
revoke all on function public.credit_referral_commission(uuid) from public;
grant execute on function public.credit_referral_commission(uuid) to service_role;

create or replace function public.activate_investment(p_investment_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_investment record;
  v_transaction_id uuid;
  v_interval integer;
begin
  select i.*, p.name as plan_name, p.roi_rate_bps as plan_roi_rate_bps,
         p.roi_interval_hours as plan_roi_interval_hours
  into v_investment
  from public.investments i
  join public.investment_plans p on p.id = i.plan_id
  where i.id = p_investment_id;
  if not found then
    raise exception 'Investment not found';
  end if;
  if v_investment.status = 'active' then
    return p_investment_id;
  end if;
  if v_investment.status <> 'pending' then
    raise exception 'Investment cannot be activated from % status', v_investment.status;
  end if;
  v_interval := coalesce(v_investment.plan_roi_interval_hours, 24);
  v_transaction_id := public.post_ledger(
    v_investment.owner_id,
    'investment',
    v_investment.asset_code,
    -v_investment.principal_minor,
    'Investment in ' || v_investment.plan_name,
    'investment:' || p_investment_id::text
  );
  update public.investments
  set status = 'active',
      roi_rate_bps = v_investment.plan_roi_rate_bps,
      roi_interval_hours = v_interval,
      activated_at = now(),
      last_roi_at = now(),
      next_roi_at = now() + make_interval(hours => v_interval),
      updated_at = now()
  where id = p_investment_id;
  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (auth.uid(), 'investment_activated', 'investment', p_investment_id,
          jsonb_build_object('transaction_id', v_transaction_id, 'principal_minor', v_investment.principal_minor));
  perform public.credit_referral_commission(p_investment_id);
  return p_investment_id;
end;
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
    'status', c.status,
    'created_at', c.created_at,
    'credited_at', c.credited_at
  ) order by c.created_at desc) into v_rows
  from (select * from public.referral_commissions order by created_at desc limit 200) c
  left join public.profiles pr on pr.id = c.referrer_id
  left join auth.users u on u.id = c.referrer_id
  left join public.profiles pi on pi.id = c.invitee_id
  left join auth.users ui on ui.id = c.invitee_id;
  return jsonb_build_object('total', v_total, 'rows', coalesce(v_rows, '[]'::jsonb));
end;
$$;
revoke all on function public.admin_referral_list() from public;
grant execute on function public.admin_referral_list() to authenticated;
