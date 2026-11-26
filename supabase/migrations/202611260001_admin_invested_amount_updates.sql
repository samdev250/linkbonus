create table public.admin_invested_adjustments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  asset_code text not null references public.supported_currencies(code),
  delta_minor bigint not null,
  target_minor bigint not null check (target_minor >= 0),
  request_id uuid not null unique,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

alter table public.admin_invested_adjustments enable row level security;
create policy "users and admins can read invested adjustments"
  on public.admin_invested_adjustments for select to authenticated
  using (owner_id = auth.uid() or public.is_admin());
revoke all on public.admin_invested_adjustments from public, anon, authenticated;
grant select on public.admin_invested_adjustments to authenticated;

create or replace function public.admin_user_invested_adjustment_totals(p_user_ids uuid[])
returns table(owner_id uuid, asset_code text, delta_minor bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  return query
  select a.owner_id, a.asset_code, sum(a.delta_minor)::bigint
  from public.admin_invested_adjustments a
  where a.owner_id = any(coalesce(p_user_ids, array[]::uuid[]))
  group by a.owner_id, a.asset_code;
end;
$$;

revoke all on function public.admin_user_invested_adjustment_totals(uuid[]) from public, anon;
grant execute on function public.admin_user_invested_adjustment_totals(uuid[]) to authenticated;

create or replace function public.admin_set_user_invested_total(
  p_user_id uuid,
  p_target_minor bigint,
  p_asset_code text,
  p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.profiles;
  v_existing public.admin_invested_adjustments;
  v_invested_before bigint;
  v_delta bigint;
begin
  if not public.has_admin_role(array['super_admin','finance']) then
    raise exception 'Finance administrator access required';
  end if;
  if p_user_id is null or p_request_id is null then
    raise exception 'Invalid invested total update request';
  end if;
  if p_target_minor is null or p_target_minor < 0 then
    raise exception 'Invested total must be zero or greater';
  end if;
  if p_asset_code is null or not exists (
    select 1 from public.supported_currencies c where c.code = p_asset_code
  ) then
    raise exception 'Unsupported account currency';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('admin-invested-total:' || p_request_id::text, 0));
  select * into v_existing
  from public.admin_invested_adjustments
  where request_id = p_request_id
  for update;
  if found then
    if v_existing.actor_id <> auth.uid()
      or v_existing.owner_id <> p_user_id
      or v_existing.asset_code <> p_asset_code
      or v_existing.target_minor <> p_target_minor then
      raise exception 'Invested total request key was already used for a different update';
    end if;
    return jsonb_build_object(
      'user_id', p_user_id,
      'asset_code', p_asset_code,
      'target_minor', v_existing.target_minor,
      'delta_minor', v_existing.delta_minor
    );
  end if;

  select * into v_profile
  from public.profiles
  where id = p_user_id
  for update;
  if not found then
    raise exception 'User not found';
  end if;
  if public.currency_for_country(v_profile.country) <> p_asset_code then
    raise exception 'Invested total must use the user''s account currency';
  end if;

  select
    coalesce((
      select sum(i.principal_minor)
      from public.investments i
      where i.owner_id = p_user_id
        and i.asset_code = p_asset_code
        and i.status in ('active', 'pending')
    ), 0)
    + coalesce((
      select sum(a.delta_minor)
      from public.admin_invested_adjustments a
      where a.owner_id = p_user_id
        and a.asset_code = p_asset_code
    ), 0)
  into v_invested_before;

  v_delta := p_target_minor - v_invested_before;
  insert into public.admin_invested_adjustments(
    owner_id, asset_code, delta_minor, target_minor, request_id, actor_id
  ) values (
    p_user_id, p_asset_code, v_delta, p_target_minor, p_request_id, auth.uid()
  );

  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    'admin_invested_total_updated',
    'profile',
    p_user_id,
    jsonb_build_object(
      'asset_code', p_asset_code,
      'invested_before_minor', v_invested_before,
      'invested_target_minor', p_target_minor,
      'adjustment_delta_minor', v_delta,
      'request_id', p_request_id
    )
  );

  return jsonb_build_object(
    'user_id', p_user_id,
    'asset_code', p_asset_code,
    'invested_before_minor', v_invested_before,
    'target_minor', p_target_minor,
    'delta_minor', v_delta
  );
end;
$$;

revoke all on function public.admin_set_user_invested_total(uuid,bigint,text,uuid) from public, anon;
grant execute on function public.admin_set_user_invested_total(uuid,bigint,text,uuid) to authenticated;
