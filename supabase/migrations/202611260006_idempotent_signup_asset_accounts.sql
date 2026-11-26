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
         (new.id, 'ETH'), (new.id, 'USDT'), (new.id, 'USDC')
  on conflict (owner_id, asset_code) do nothing;
  return new;
end;
$$;
