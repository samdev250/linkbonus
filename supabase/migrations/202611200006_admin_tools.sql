create table if not exists public.payment_instructions (
  country_code text primary key,
  bank_name text,
  account_name text not null,
  account_number text not null,
  instructions text not null default '',
  active boolean not null default true,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  audience text not null check (audience in ('all','country','user')),
  country_code text,
  user_id uuid references public.profiles(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.notification_reads (
  notification_id uuid not null references public.notifications(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (notification_id, user_id)
);

create table if not exists public.support_settings (
  id boolean primary key default true check (id),
  support_email text not null default 'infolinkbonusinvest@gmail.com',
  whatsapp_url text,
  telegram_url text,
  updated_at timestamptz not null default now()
);

insert into public.support_settings (id, support_email)
values (true, 'infolinkbonusinvest@gmail.com')
on conflict (id) do nothing;

alter table public.payment_instructions enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_reads enable row level security;
alter table public.support_settings enable row level security;

drop policy if exists "payment instructions member read" on public.payment_instructions;
create policy "payment instructions member read" on public.payment_instructions for select to authenticated using (active = true);
drop policy if exists "payment instructions admin read" on public.payment_instructions;
create policy "payment instructions admin read" on public.payment_instructions for select to authenticated using (public.is_admin());
drop policy if exists "notifications recipient read" on public.notifications;
create policy "notifications recipient read" on public.notifications for select to authenticated using (
  audience = 'all'
  or (audience = 'country' and country_code = (select country from public.profiles where id = auth.uid()))
  or (audience = 'user' and user_id = auth.uid())
  or public.is_admin()
);
drop policy if exists "notification reads own" on public.notification_reads;
create policy "notification reads own" on public.notification_reads for select to authenticated using (user_id = auth.uid());
drop policy if exists "support settings member read" on public.support_settings;
create policy "support settings member read" on public.support_settings for select to authenticated using (true);

create or replace function public.admin_upsert_payment_instruction(
  p_country_code text, p_bank_name text, p_account_name text, p_account_number text,
  p_instructions text, p_active boolean default true
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_code text := upper(trim(coalesce(p_country_code, '')));
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if v_code !~ '^[A-Z]{2}$' then
    raise exception 'Enter a two-letter country code';
  end if;
  if nullif(trim(coalesce(p_account_name, '')), '') is null or nullif(trim(coalesce(p_account_number, '')), '') is null then
    raise exception 'Account name and number are required';
  end if;
  insert into public.payment_instructions (
    country_code, bank_name, account_name, account_number, instructions, active, updated_by, updated_at
  ) values (
    v_code, nullif(trim(coalesce(p_bank_name, '')), ''), trim(p_account_name), trim(p_account_number),
    coalesce(p_instructions, ''), coalesce(p_active, true), auth.uid(), now()
  )
  on conflict (country_code) do update set
    bank_name = excluded.bank_name,
    account_name = excluded.account_name,
    account_number = excluded.account_number,
    instructions = excluded.instructions,
    active = excluded.active,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;
  return jsonb_build_object('country_code', v_code, 'status', 'saved');
end;
$$;

create or replace function public.admin_list_payment_instructions()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  select jsonb_agg(jsonb_build_object(
    'country_code', p.country_code, 'bank_name', p.bank_name,
    'account_name', p.account_name, 'account_number', p.account_number,
    'instructions', p.instructions, 'active', p.active, 'updated_at', p.updated_at
  ) order by p.country_code) into v_rows
  from public.payment_instructions p;
  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

create or replace function public.member_get_payment_instruction(p_country_code text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_code text;
  v_row public.payment_instructions;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  v_code := upper(trim(coalesce(p_country_code, (select country from public.profiles where id = auth.uid()), '')));
  select * into v_row from public.payment_instructions
  where country_code = v_code and active = true;
  if not found then
    return jsonb_build_object('configured', false, 'country_code', v_code);
  end if;
  return jsonb_build_object(
    'configured', true, 'country_code', v_row.country_code, 'bank_name', v_row.bank_name,
    'account_name', v_row.account_name, 'account_number', v_row.account_number,
    'instructions', v_row.instructions
  );
end;
$$;

create or replace function public.admin_create_notification(
  p_title text, p_body text, p_audience text,
  p_country_code text default null, p_user_email text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_user_id uuid;
  v_code text := upper(trim(coalesce(p_country_code, '')));
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if nullif(trim(coalesce(p_title, '')), '') is null or nullif(trim(coalesce(p_body, '')), '') is null then
    raise exception 'Title and message are required';
  end if;
  if p_audience not in ('all','country','user') then
    raise exception 'Unsupported audience';
  end if;
  if p_audience = 'country' and v_code !~ '^[A-Z]{2}$' then
    raise exception 'Enter a two-letter country code';
  end if;
  if p_audience = 'user' then
    select p.id into v_user_id
    from public.profiles p join auth.users u on u.id = p.id
    where lower(u.email) = lower(trim(coalesce(p_user_email, '')));
    if v_user_id is null then
      raise exception 'No member found with that email';
    end if;
  end if;
  insert into public.notifications (title, body, audience, country_code, user_id, created_by)
  values (trim(p_title), trim(p_body), p_audience,
          case when p_audience = 'country' then v_code else null end,
          case when p_audience = 'user' then v_user_id else null end,
          auth.uid())
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'audience', p_audience, 'status', 'sent');
end;
$$;

create or replace function public.member_list_notifications()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  select jsonb_agg(jsonb_build_object(
    'id', n.id, 'title', n.title, 'body', n.body, 'audience', n.audience,
    'created_at', n.created_at,
    'read', exists(select 1 from public.notification_reads r where r.notification_id = n.id and r.user_id = auth.uid())
  ) order by n.created_at desc) into v_rows
  from public.notifications n
  where n.audience = 'all'
     or (n.audience = 'country' and n.country_code = (select country from public.profiles where id = auth.uid()))
     or (n.audience = 'user' and n.user_id = auth.uid());
  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

create or replace function public.member_mark_notification_read(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not exists (
    select 1 from public.notifications n
    where n.id = p_id
      and (n.audience = 'all'
        or (n.audience = 'country' and n.country_code = (select country from public.profiles where id = auth.uid()))
        or (n.audience = 'user' and n.user_id = auth.uid()))
  ) then
    raise exception 'Notification not found';
  end if;
  insert into public.notification_reads (notification_id, user_id)
  values (p_id, auth.uid())
  on conflict (notification_id, user_id) do nothing;
  return jsonb_build_object('id', p_id, 'read', true);
end;
$$;

create or replace function public.admin_list_notifications()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  select jsonb_agg(jsonb_build_object(
    'id', n.id, 'title', n.title, 'body', n.body, 'audience', n.audience,
    'country_code', n.country_code, 'created_at', n.created_at,
    'sender', coalesce(nullif(p.full_name, ''), split_part(u.email, '@', 1), 'Admin'),
    'reads', (select count(*) from public.notification_reads r where r.notification_id = n.id)
  ) order by n.created_at desc) into v_rows
  from public.notifications n
  left join public.profiles p on p.id = n.created_by
  left join auth.users u on u.id = n.created_by;
  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

create or replace function public.member_support_settings()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_row public.support_settings;
begin
  select * into v_row from public.support_settings where id = true;
  if not found then
    return jsonb_build_object('support_email', 'infolinkbonusinvest@gmail.com', 'whatsapp_url', null, 'telegram_url', null);
  end if;
  return jsonb_build_object(
    'support_email', v_row.support_email,
    'whatsapp_url', v_row.whatsapp_url,
    'telegram_url', v_row.telegram_url,
    'updated_at', v_row.updated_at
  );
end;
$$;

create or replace function public.admin_update_support_settings(p_email text, p_whatsapp text default null, p_telegram text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_whatsapp text := nullif(trim(coalesce(p_whatsapp, '')), '');
  v_telegram text := nullif(trim(coalesce(p_telegram, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Enter a valid support email';
  end if;
  if v_whatsapp is not null and v_whatsapp !~ '^https?://' then
    raise exception 'WhatsApp link must start with http:// or https://';
  end if;
  if v_telegram is not null and v_telegram !~ '^https?://' then
    raise exception 'Telegram link must start with http:// or https://';
  end if;
  update public.support_settings
  set support_email = v_email, whatsapp_url = v_whatsapp, telegram_url = v_telegram, updated_at = now()
  where id = true;
  return jsonb_build_object('status', 'saved', 'support_email', v_email);
end;
$$;

revoke all on function public.admin_upsert_payment_instruction(text, text, text, text, text, boolean) from public;
revoke all on function public.admin_list_payment_instructions() from public;
revoke all on function public.member_get_payment_instruction(text) from public;
revoke all on function public.admin_create_notification(text, text, text, text, text) from public;
revoke all on function public.member_list_notifications() from public;
revoke all on function public.member_mark_notification_read(uuid) from public;
revoke all on function public.admin_list_notifications() from public;
revoke all on function public.member_support_settings() from public;
revoke all on function public.admin_update_support_settings(text, text, text) from public;
grant execute on function public.admin_upsert_payment_instruction(text, text, text, text, text, boolean) to authenticated;
grant execute on function public.admin_list_payment_instructions() to authenticated;
grant execute on function public.member_get_payment_instruction(text) to authenticated;
grant execute on function public.admin_create_notification(text, text, text, text, text) to authenticated;
grant execute on function public.member_list_notifications() to authenticated;
grant execute on function public.member_mark_notification_read(uuid) to authenticated;
grant execute on function public.admin_list_notifications() to authenticated;
grant execute on function public.member_support_settings() to authenticated;
grant execute on function public.admin_update_support_settings(text, text, text) to authenticated;
