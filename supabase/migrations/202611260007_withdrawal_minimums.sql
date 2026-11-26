create table public.withdrawal_minimums (
  country_code text primary key check (country_code ~ '^[A-Z]{2}$'),
  minimum_minor bigint not null check (minimum_minor > 0),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.withdrawal_minimums(country_code, minimum_minor)
values
  ('RW', 2000000),
  ('BI', 10000000),
  ('ZM', 60000),
  ('UG', 10000000),
  ('TZ', 15000000),
  ('KE', 150000)
on conflict (country_code) do nothing;

alter table public.withdrawal_minimums enable row level security;
revoke all on public.withdrawal_minimums from public, anon, authenticated;

create or replace function public.member_get_withdrawal_minimum()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_country text;
  v_minimum bigint;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select upper(trim(coalesce(p.country, ''))) into v_country
  from public.profiles p
  where p.id = auth.uid();
  if not found then
    raise exception 'Member profile not found';
  end if;

  v_country := case v_country
    when 'RWANDA' then 'RW'
    when 'BURUNDI' then 'BI'
    when 'ZAMBIA' then 'ZM'
    when 'UGANDA' then 'UG'
    when 'TANZANIA' then 'TZ'
    when 'KENYA' then 'KE'
    else v_country
  end;

  select m.minimum_minor into v_minimum
  from public.withdrawal_minimums m
  where m.country_code = v_country;

  if not found then
    return jsonb_build_object(
      'configured', false,
      'country_code', v_country,
      'currency_code', public.currency_for_country(v_country)
    );
  end if;

  return jsonb_build_object(
    'configured', true,
    'country_code', v_country,
    'currency_code', public.currency_for_country(v_country),
    'minimum_minor', v_minimum::text
  );
end;
$$;

create or replace function public.admin_list_withdrawal_minimums()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;

  select jsonb_agg(jsonb_build_object(
    'country_code', m.country_code,
    'currency_code', public.currency_for_country(m.country_code),
    'minimum_minor', m.minimum_minor::text,
    'updated_at', m.updated_at
  ) order by m.country_code) into v_rows
  from public.withdrawal_minimums m;

  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

create or replace function public.admin_set_withdrawal_minimum(
  p_country_code text,
  p_minimum_minor bigint
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_country text := upper(trim(coalesce(p_country_code, '')));
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if v_country !~ '^[A-Z]{2}$' then
    raise exception 'Choose a valid two-letter country code';
  end if;
  if p_minimum_minor is null or p_minimum_minor <= 0 then
    raise exception 'Minimum withdrawal amount must be greater than zero';
  end if;

  insert into public.withdrawal_minimums(country_code, minimum_minor, updated_by, updated_at)
  values (v_country, p_minimum_minor, auth.uid(), now())
  on conflict (country_code) do update
  set minimum_minor = excluded.minimum_minor,
      updated_by = excluded.updated_by,
      updated_at = excluded.updated_at;

  return jsonb_build_object(
    'country_code', v_country,
    'currency_code', public.currency_for_country(v_country),
    'minimum_minor', p_minimum_minor::text,
    'status', 'saved'
  );
end;
$$;

revoke all on function public.member_get_withdrawal_minimum() from public, anon;
revoke all on function public.admin_list_withdrawal_minimums() from public, anon;
revoke all on function public.admin_set_withdrawal_minimum(text, bigint) from public, anon;
grant execute on function public.member_get_withdrawal_minimum() to authenticated;
grant execute on function public.admin_list_withdrawal_minimums() to authenticated;
grant execute on function public.admin_set_withdrawal_minimum(text, bigint) to authenticated;
