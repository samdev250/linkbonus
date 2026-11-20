do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'payment_proof_status') then
    create type public.payment_proof_status as enum ('pending','approved','rejected','cancelled');
  end if;
end $$;

create table if not exists public.payment_proofs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  idempotency_key text not null unique,
  amount_minor bigint not null check (amount_minor > 0),
  asset_code text not null,
  phone text not null,
  full_name text not null,
  payer_name text not null,
  payee_name text,
  screenshot_path text not null,
  provider_reference text,
  note text,
  plan_id uuid references public.investment_plans(id) on delete restrict,
  investment_id uuid references public.investments(id) on delete set null,
  status public.payment_proof_status not null default 'pending',
  rejection_reason text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  transaction_id uuid references public.ledger_transactions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),
  inviter_id uuid not null references public.profiles(id) on delete restrict,
  invitee_id uuid references public.profiles(id) on delete set null,
  email text not null,
  token text not null unique,
  status text not null default 'pending' check (status in ('pending','accepted','expired')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  check (invitee_id is null or inviter_id <> invitee_id)
);

alter table public.payment_proofs enable row level security;
alter table public.invitations enable row level security;

drop policy if exists "payment proofs own read" on public.payment_proofs;
create policy "payment proofs own read" on public.payment_proofs for select to authenticated using (owner_id = auth.uid());
drop policy if exists "payment proofs admin read" on public.payment_proofs;
create policy "payment proofs admin read" on public.payment_proofs for select to authenticated using (public.has_admin_role(array['super_admin','finance','compliance']));
drop policy if exists "invitations own read" on public.invitations;
create policy "invitations own read" on public.invitations for select to authenticated using (inviter_id = auth.uid() or invitee_id = auth.uid());

insert into storage.buckets (id, name, public, file_size_limit)
values ('payment-proofs', 'payment-proofs', false, 5242880)
on conflict (id) do nothing;

drop policy if exists "payment proof own upload" on storage.objects;
create policy "payment proof own upload" on storage.objects for insert to authenticated
with check (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "payment proof own read" on storage.objects;
create policy "payment proof own read" on storage.objects for select to authenticated
using (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "payment proof admin read" on storage.objects;
create policy "payment proof admin read" on storage.objects for select to authenticated
using (bucket_id = 'payment-proofs' and public.is_admin());

create or replace function public.member_create_invitation(p_email text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_token text;
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Enter a valid email address';
  end if;
  insert into public.invitations (inviter_id, email, token)
  values (auth.uid(), v_email, encode(gen_random_bytes(12), 'hex'))
  returning id, token into v_id, v_token;
  return jsonb_build_object('id', v_id, 'email', v_email, 'token', v_token, 'status', 'pending');
end;
$$;

create or replace function public.member_list_invitations()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  select jsonb_agg(jsonb_build_object(
    'id', i.id, 'email', i.email, 'token', i.token, 'status', i.status,
    'created_at', i.created_at, 'accepted_at', i.accepted_at
  ) order by i.created_at desc) into v_rows
  from public.invitations i where i.inviter_id = auth.uid();
  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

create or replace function public.accept_invitation(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_row public.invitations;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  select * into v_row from public.invitations where token = p_token for update;
  if not found then
    raise exception 'Invitation not found';
  end if;
  if v_row.inviter_id = auth.uid() then
    raise exception 'You cannot accept your own invitation';
  end if;
  if v_row.status = 'accepted' then
    return jsonb_build_object('status', 'accepted', 'already_accepted', true);
  end if;
  if v_row.status <> 'pending' then
    raise exception 'Invitation is no longer active';
  end if;
  update public.profiles set referred_by = v_row.inviter_id, updated_at = now()
  where id = auth.uid() and referred_by is null;
  update public.invitations set status = 'accepted', invitee_id = auth.uid(), accepted_at = now()
  where id = v_row.id;
  return jsonb_build_object('status', 'accepted', 'already_accepted', false);
end;
$$;

create or replace function public.submit_payment_proof(
  p_amount_minor bigint,
  p_asset_code text,
  p_screenshot_path text,
  p_phone text,
  p_full_name text,
  p_payer_name text,
  p_idempotency_key text,
  p_plan_id uuid default null,
  p_provider_reference text default null,
  p_note text default null,
  p_payee_name text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_investment_id uuid;
  v_plan public.investment_plans;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if coalesce(p_amount_minor, 0) <= 0 then
    raise exception 'Enter a deposit amount';
  end if;
  if split_part(coalesce(p_screenshot_path, ''), '/', 1) <> auth.uid()::text then
    raise exception 'Invalid screenshot path';
  end if;
  if nullif(trim(coalesce(p_phone, '')), '') is null or nullif(trim(coalesce(p_payer_name, '')), '') is null then
    raise exception 'Phone number and payer name are required';
  end if;
  if p_plan_id is not null then
    select * into v_plan from public.investment_plans where id = p_plan_id and active = true;
    if not found then
      raise exception 'Plan is not available';
    end if;
    if p_amount_minor < v_plan.minimum_minor or (v_plan.maximum_minor is not null and p_amount_minor > v_plan.maximum_minor) then
      raise exception 'Amount is outside the plan limits';
    end if;
    insert into public.investments (owner_id, plan_id, principal_minor, asset_code, status)
    values (auth.uid(), p_plan_id, p_amount_minor, p_asset_code, 'pending')
    returning id into v_investment_id;
  end if;
  insert into public.payment_proofs (
    owner_id, idempotency_key, amount_minor, asset_code, phone, full_name, payer_name,
    payee_name, screenshot_path, provider_reference, note, plan_id, investment_id
  ) values (
    auth.uid(), p_idempotency_key, p_amount_minor, p_asset_code, trim(p_phone), trim(p_full_name),
    trim(p_payer_name), nullif(trim(coalesce(p_payee_name, '')), ''), p_screenshot_path,
    nullif(trim(coalesce(p_provider_reference, '')), ''), nullif(trim(coalesce(p_note, '')), ''),
    p_plan_id, v_investment_id
  ) returning id into v_id;
  return jsonb_build_object('id', v_id, 'investment_id', v_investment_id, 'status', 'pending');
end;
$$;

create or replace function public.member_list_payment_proofs()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  select jsonb_agg(jsonb_build_object(
    'id', p.id, 'amount_minor', p.amount_minor, 'asset_code', p.asset_code,
    'payer_name', p.payer_name, 'phone', p.phone, 'provider_reference', p.provider_reference,
    'status', p.status, 'rejection_reason', p.rejection_reason, 'created_at', p.created_at,
    'reviewed_at', p.reviewed_at, 'plan_id', p.plan_id, 'investment_id', p.investment_id,
    'screenshot_path', p.screenshot_path
  ) order by p.created_at desc) into v_rows
  from public.payment_proofs p where p.owner_id = auth.uid();
  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

create or replace function public.admin_list_payment_proofs(p_status text default 'pending', p_limit integer default 50, p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rows jsonb;
  v_total integer;
begin
  if not public.has_admin_role(array['super_admin','finance','compliance']) then
    raise exception 'Administrator access required';
  end if;
  select count(*) into v_total from public.payment_proofs p
  where coalesce(p_status, 'pending') in ('pending', 'all') or p.status::text = p_status;
  select jsonb_agg(jsonb_build_object(
    'id', p.id, 'owner_id', p.owner_id,
    'name', coalesce(nullif(pr.full_name, ''), split_part(u.email, '@', 1), 'Member'),
    'email', u.email, 'phone', p.phone,
    'amount_minor', p.amount_minor, 'asset_code', p.asset_code,
    'payer_name', p.payer_name, 'payee_name', p.payee_name,
    'provider_reference', p.provider_reference, 'note', p.note,
    'plan', pl.name, 'investment_id', p.investment_id,
    'screenshot_path', p.screenshot_path, 'status', p.status,
    'rejection_reason', p.rejection_reason, 'created_at', p.created_at,
    'reviewed_at', p.reviewed_at
  ) order by p.created_at desc) into v_rows
  from (
    select * from public.payment_proofs
    where coalesce(p_status, 'pending') in ('pending', 'all') or status::text = p_status
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(0, coalesce(p_offset, 0))
  ) p
  left join public.profiles pr on pr.id = p.owner_id
  left join auth.users u on u.id = p.owner_id
  left join public.investment_plans pl on pl.id = p.plan_id;
  return jsonb_build_object('total', v_total, 'rows', coalesce(v_rows, '[]'::jsonb));
end;
$$;

create or replace function public.admin_review_payment_proof(p_id uuid, p_action text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_proof public.payment_proofs;
  v_status public.payment_proof_status;
  v_transaction_id uuid;
begin
  if not public.has_admin_role(array['super_admin','finance','compliance']) then
    raise exception 'Administrator access required';
  end if;
  if p_action not in ('approve','reject','cancel') then
    raise exception 'Unsupported review action';
  end if;
  select * into v_proof from public.payment_proofs where id = p_id for update;
  if not found then
    raise exception 'Payment proof not found';
  end if;
  if v_proof.status <> 'pending' then
    raise exception 'Payment proof has already been reviewed';
  end if;
  if p_action = 'approve' then
    v_transaction_id := public.post_ledger(
      v_proof.owner_id, 'deposit', v_proof.asset_code, v_proof.amount_minor,
      'Approved deposit proof ' || v_proof.id::text, 'proof:' || v_proof.id::text
    );
    update public.payment_proofs
    set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(),
        transaction_id = v_transaction_id, rejection_reason = null, updated_at = now()
    where id = p_id;
    if v_proof.investment_id is not null then
      perform public.activate_investment(v_proof.investment_id);
    end if;
    v_status := 'approved';
  else
    v_status := case p_action when 'reject' then 'rejected'::public.payment_proof_status else 'cancelled'::public.payment_proof_status end;
    update public.payment_proofs
    set status = v_status, reviewed_by = auth.uid(), reviewed_at = now(),
        rejection_reason = nullif(trim(coalesce(p_note, '')), ''), updated_at = now()
    where id = p_id;
  end if;
  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (auth.uid(), 'payment_proof_' || p_action, 'payment_proof', p_id,
          jsonb_build_object('status', v_status, 'amount_minor', v_proof.amount_minor, 'note', p_note));
  return jsonb_build_object('id', p_id, 'status', v_status, 'investment_id', v_proof.investment_id);
end;
$$;

create or replace function public.member_sync_roi(p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v record;
  v_amount bigint;
  v_start timestamptz;
  v_end timestamptz;
  v_key text;
  v_transaction_id uuid;
  v_credit_id uuid;
  v_processed integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  for v in
    select i.id, i.owner_id, i.asset_code, i.principal_minor, i.roi_rate_bps,
           i.roi_interval_hours, i.next_roi_at
    from public.investments i
    where i.owner_id = auth.uid() and i.status = 'active' and i.next_roi_at <= now() and i.roi_rate_bps > 0
    order by i.next_roi_at
    limit greatest(1, least(coalesce(p_limit, 20), 100))
    for update skip locked
  loop
    begin
      v_amount := (v.principal_minor * v.roi_rate_bps + 5000) / 10000;
      v_start := v.next_roi_at;
      v_end := v_start + make_interval(hours => v.roi_interval_hours);
      v_key := 'roi:' || v.id::text || ':' || to_char(v_start at time zone 'UTC', 'YYYYMMDDHH24MISSUS');
      v_transaction_id := public.post_ledger(v.owner_id, 'roi_credit', v.asset_code, v_amount, 'Automated investment return', v_key);
      insert into public.roi_credits(
        investment_id, owner_id, transaction_id, period_start, period_end,
        rate_bps, base_minor, amount_minor, idempotency_key
      ) values (v.id, v.owner_id, v_transaction_id, v_start, v_end, v.roi_rate_bps, v.principal_minor, v_amount, v_key)
      on conflict (investment_id, period_start) do nothing returning id into v_credit_id;
      if v_credit_id is not null then
        update public.investments
        set last_roi_at = v_start, next_roi_at = v_end,
            total_roi_paid_minor = total_roi_paid_minor + v_amount, updated_at = now()
        where id = v.id;
      else
        update public.investments set next_roi_at = v_end, updated_at = now() where id = v.id;
      end if;
      v_processed := v_processed + 1;
    exception when others then
      update public.investments
      set next_roi_at = now() + make_interval(hours => v.roi_interval_hours), updated_at = now()
      where id = v.id;
    end;
  end loop;
  return jsonb_build_object('processed', v_processed, 'executed_at', now());
end;
$$;

create or replace function public.member_roi_summary()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'paid_minor', coalesce((select sum(i.total_roi_paid_minor) from public.investments i where i.owner_id = auth.uid()), 0),
    'accrued_minor', coalesce((
      select sum(round(
        (i.principal_minor::numeric * i.roi_rate_bps *
         greatest(extract(epoch from (now() - coalesce(i.last_roi_at, i.activated_at))) / 3600, 0) /
         nullif(i.roi_interval_hours, 0)) / 10000
      ))
      from public.investments i
      where i.owner_id = auth.uid() and i.status = 'active' and i.roi_rate_bps > 0
    ), 0),
    'daily_minor', coalesce((
      select sum(round(i.principal_minor::numeric * i.roi_rate_bps / 10000))
      from public.investments i
      where i.owner_id = auth.uid() and i.status = 'active' and i.roi_rate_bps > 0
    ), 0),
    'next_credit_at', (
      select min(i.next_roi_at) from public.investments i
      where i.owner_id = auth.uid() and i.status = 'active' and i.roi_rate_bps > 0
    ),
    'investments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'plan', pl.name, 'principal_minor', i.principal_minor,
        'status', i.status, 'rate_bps', i.roi_rate_bps,
        'daily_minor', round(i.principal_minor::numeric * i.roi_rate_bps / 10000),
        'paid_minor', i.total_roi_paid_minor, 'next_roi_at', i.next_roi_at,
        'activated_at', i.activated_at
      ) order by i.created_at desc)
      from public.investments i join public.investment_plans pl on pl.id = i.plan_id
      where i.owner_id = auth.uid()
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.member_create_invitation(text) from public;
revoke all on function public.member_list_invitations() from public;
revoke all on function public.accept_invitation(text) from public;
revoke all on function public.submit_payment_proof(bigint, text, text, text, text, text, text, uuid, text, text, text) from public;
revoke all on function public.member_list_payment_proofs() from public;
revoke all on function public.admin_list_payment_proofs(text, integer, integer) from public;
revoke all on function public.admin_review_payment_proof(uuid, text, text) from public;
revoke all on function public.member_sync_roi(integer) from public;
revoke all on function public.member_roi_summary() from public;
grant execute on function public.member_create_invitation(text) to authenticated;
grant execute on function public.member_list_invitations() to authenticated;
grant execute on function public.accept_invitation(text) to authenticated;
grant execute on function public.submit_payment_proof(bigint, text, text, text, text, text, text, uuid, text, text, text) to authenticated;
grant execute on function public.member_list_payment_proofs() to authenticated;
grant execute on function public.admin_list_payment_proofs(text, integer, integer) to authenticated;
grant execute on function public.admin_review_payment_proof(uuid, text, text) to authenticated;
grant execute on function public.member_sync_roi(integer) to authenticated;
grant execute on function public.member_roi_summary() to authenticated;

insert into public.investment_plans (name, minimum_minor, roi_rate_bps, roi_interval_hours, duration_days, active, performance_methodology, risk_disclosure, updated_at)
values
  ('Starter', 1000, 50, 24, 30, true, 'Automated periodic return configured by the administrator', 'Capital at risk. Returns are not guaranteed.', now()),
  ('Basic', 2500, 50, 24, 30, true, 'Automated periodic return configured by the administrator', 'Capital at risk. Returns are not guaranteed.', now()),
  ('Silver', 5000, 50, 24, 30, true, 'Automated periodic return configured by the administrator', 'Capital at risk. Returns are not guaranteed.', now()),
  ('Bronze', 10000, 50, 24, 30, true, 'Automated periodic return configured by the administrator', 'Capital at risk. Returns are not guaranteed.', now()),
  ('Gold', 25000, 50, 24, 30, true, 'Automated periodic return configured by the administrator', 'Capital at risk. Returns are not guaranteed.', now()),
  ('Platinum', 50000, 50, 24, 30, true, 'Automated periodic return configured by the administrator', 'Capital at risk. Returns are not guaranteed.', now()),
  ('Diamond', 100000, 50, 24, 30, true, 'Automated periodic return configured by the administrator', 'Capital at risk. Returns are not guaranteed.', now()),
  ('Premium', 250000, 50, 24, 30, true, 'Automated periodic return configured by the administrator', 'Capital at risk. Returns are not guaranteed.', now()),
  ('Professional', 500000, 50, 24, 30, true, 'Automated periodic return configured by the administrator', 'Capital at risk. Returns are not guaranteed.', now()),
  ('VIP', 1000000, 50, 24, 30, true, 'Automated periodic return configured by the administrator', 'Capital at risk. Returns are not guaranteed.', now())
on conflict (name) do update set
  roi_rate_bps = excluded.roi_rate_bps,
  roi_interval_hours = excluded.roi_interval_hours,
  duration_days = excluded.duration_days,
  active = true,
  performance_methodology = excluded.performance_methodology,
  risk_disclosure = excluded.risk_disclosure,
  updated_at = now();
