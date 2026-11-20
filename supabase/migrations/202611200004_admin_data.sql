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
    'active_staking', (select count(*) from public.staking_positions where status = 'active'),
    'referral_commissions_minor', coalesce((select sum(amount_minor) from public.referral_commissions where status = 'credited'), 0),
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

create or replace function public.admin_list_users(p_search text default '', p_status text default 'All users', p_limit integer default 50, p_offset integer default 0)
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
      or p.status::text = p_status
      or (p_status = 'Verified' and p.verification_status = 'verified')
      or (p_status = 'Pending verification' and p.verification_status <> 'verified'));
  select jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', coalesce(nullif(p.full_name, ''), split_part(u.email, '@', 1), 'Member'),
    'email', u.email,
    'country', p.country,
    'phone', p.phone,
    'status', p.status,
    'verification_status', p.verification_status,
    'referral_code', p.referral_code,
    'role', ar.role,
    'created_at', p.created_at
  ) order by p.created_at desc) into v_rows
  from (
    select * from public.profiles
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(0, coalesce(p_offset, 0))
  ) p
  join auth.users u on u.id = p.id
  left join public.admin_roles ar on ar.user_id = p.id
  where (coalesce(p_search, '') = ''
      or p.full_name ilike '%' || p_search || '%'
      or u.email ilike '%' || p_search || '%'
      or p.id::text = p_search)
    and (coalesce(p_status, 'All users') in ('All users', '')
      or p.status::text = p_status
      or (p_status = 'Verified' and p.verification_status = 'verified')
      or (p_status = 'Pending verification' and p.verification_status <> 'verified'));
  return jsonb_build_object('total', v_total, 'rows', coalesce(v_rows, '[]'::jsonb));
end;
$$;

create or replace function public.admin_update_user(p_id uuid, p_full_name text, p_country text, p_phone text, p_status text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_row jsonb;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if p_id = auth.uid() and p_status = 'suspended' then
    raise exception 'You cannot suspend your own account';
  end if;
  update public.profiles
  set full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
      country = nullif(trim(p_country), ''),
      phone = nullif(trim(p_phone), ''),
      status = case when p_status in ('active','suspended') then p_status::public.account_status else status end,
      updated_at = now()
  where id = p_id;
  if not found then
    raise exception 'User not found';
  end if;
  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (auth.uid(), 'admin_user_updated', 'profile', p_id, jsonb_build_object('status', p_status));
  select jsonb_build_object(
    'id', p.id, 'name', p.full_name, 'country', p.country, 'phone', p.phone,
    'status', p.status, 'email', u.email
  ) into v_row
  from public.profiles p join auth.users u on u.id = p.id where p.id = p_id;
  return v_row;
end;
$$;

create or replace function public.admin_set_user_status(p_id uuid, p_status text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_status public.account_status;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if p_status not in ('active','suspended') then
    raise exception 'Unsupported account status';
  end if;
  if p_id = auth.uid() and p_status = 'suspended' then
    raise exception 'You cannot suspend your own account';
  end if;
  v_status := p_status::public.account_status;
  update public.profiles set status = v_status, updated_at = now() where id = p_id;
  if not found then
    raise exception 'User not found';
  end if;
  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (auth.uid(), 'admin_user_status_changed', 'profile', p_id, jsonb_build_object('status', p_status));
  return jsonb_build_object('id', p_id, 'status', v_status);
end;
$$;

drop policy if exists "staking admin read" on public.staking_positions;
create policy "staking admin read" on public.staking_positions for select to authenticated using (public.is_admin());
drop policy if exists "commissions admin read" on public.referral_commissions;
create policy "commissions admin read" on public.referral_commissions for select to authenticated using (public.is_admin());
drop policy if exists "assets admin read" on public.asset_accounts;
create policy "assets admin read" on public.asset_accounts for select to authenticated using (public.is_admin());

revoke all on function public.admin_overview() from public;
revoke all on function public.admin_list_users(text, text, integer, integer) from public;
revoke all on function public.admin_update_user(uuid, text, text, text, text) from public;
revoke all on function public.admin_set_user_status(uuid, text) from public;
grant execute on function public.admin_overview() to authenticated;
grant execute on function public.admin_list_users(text, text, integer, integer) to authenticated;
grant execute on function public.admin_update_user(uuid, text, text, text, text) to authenticated;
grant execute on function public.admin_set_user_status(uuid, text) to authenticated;
