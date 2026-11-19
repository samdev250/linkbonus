-- Persist the signup form's country and phone fields in the member profile.
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare referrer uuid;
begin
 select p.id into referrer from public.profiles p
 where p.referral_code=upper(trim(coalesce(new.raw_user_meta_data->>'referral_code','')))
 and p.id<>new.id limit 1;
 insert into public.profiles(id,full_name,country,phone,referred_by)
 values(
  new.id,
  coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(coalesce(new.email,''),'@',1)),
  nullif(trim(new.raw_user_meta_data->>'country'),''),
  nullif(trim(new.raw_user_meta_data->>'phone'),''),
  referrer
 );
 insert into public.asset_accounts(owner_id,asset_code)
 values(new.id,'USD'),(new.id,'RWF'),(new.id,'BIF'),(new.id,'BTC'),(new.id,'ETH'),(new.id,'USDT'),(new.id,'USDC');
 return new;
end;
$$;
