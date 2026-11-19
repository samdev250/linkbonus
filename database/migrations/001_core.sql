create extension if not exists pgcrypto;
create type public.account_status as enum ('active','suspended');
create type public.transaction_status as enum ('pending','processing','completed','failed','reversed');
create type public.transaction_kind as enum ('deposit','withdrawal','investment','staking','exchange','referral_commission');
create table public.profiles (
 id uuid primary key references auth.users(id) on delete restrict,
 full_name text not null default '', country text, phone text,
 status public.account_status not null default 'active', verification_status text not null default 'unverified',
 referral_code text not null unique default upper(substr(encode(gen_random_bytes(8),'hex'),1,10)),
 referred_by uuid references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint no_self_referral check (referred_by is null or referred_by <> id)
);
-- Automatically provision a private member profile and empty per-asset ledger
-- accounts after successful Auth signup. This does not fund the accounts.
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare referrer uuid;
begin
 select p.id into referrer from public.profiles p
 where p.referral_code=upper(trim(coalesce(new.raw_user_meta_data->>'referral_code','')))
 and p.id<>new.id limit 1;
 insert into public.profiles(id,full_name,referred_by)
 values(new.id,coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(coalesce(new.email,''),'@',1)),referrer);
 insert into public.asset_accounts(owner_id,asset_code)
 values(new.id,'USD'),(new.id,'RWF'),(new.id,'BIF'),(new.id,'BTC'),(new.id,'ETH'),(new.id,'USDT'),(new.id,'USDC');
 return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
 for each row execute function public.handle_new_auth_user();
create table public.asset_accounts (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles(id) on delete restrict,
 asset_code text not null check(asset_code in ('USD','RWF','BIF','BTC','ETH','USDT','USDC')),
 created_at timestamptz not null default now(), unique(owner_id,asset_code)
);
create table public.ledger_transactions (
 id uuid primary key default gen_random_uuid(), idempotency_key text not null unique,
 kind public.transaction_kind not null, status public.transaction_status not null default 'pending',
 owner_id uuid not null references public.profiles(id) on delete restrict,
 amount_minor bigint not null check(amount_minor > 0), asset_code text not null,
 provider_reference text, description text, created_at timestamptz not null default now(), completed_at timestamptz
);
create table public.ledger_entries (
 id uuid primary key default gen_random_uuid(), transaction_id uuid not null references public.ledger_transactions(id) on delete restrict,
 account_id uuid not null references public.asset_accounts(id) on delete restrict,
 amount_minor bigint not null check(amount_minor <> 0), created_at timestamptz not null default now()
);
create index ledger_owner_created on public.ledger_transactions(owner_id,created_at desc);
create table public.investment_plans (
 id uuid primary key default gen_random_uuid(), name text not null unique,
 minimum_minor bigint not null check(minimum_minor>0), maximum_minor bigint check(maximum_minor is null or maximum_minor>=minimum_minor),
 duration_days integer, fee_bps integer not null default 0 check(fee_bps between 0 and 10000),
 performance_methodology text not null default 'Not configured', risk_disclosure text not null default 'Capital at risk',
 active boolean not null default false, created_at timestamptz not null default now()
);
create table public.investments (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles(id) on delete restrict,
 plan_id uuid not null references public.investment_plans(id) on delete restrict,
 principal_minor bigint not null check(principal_minor>0), asset_code text not null,
 status text not null default 'pending', created_at timestamptz not null default now()
);
create table public.staking_positions (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles(id) on delete restrict,
 asset_code text not null check(asset_code in ('USD','RWF','BIF','BTC','ETH','USDT','USDC')),
 principal_minor bigint not null check(principal_minor>0), status text not null default 'pending'
 check(status in ('pending','active','completed','unstaking','cancelled')),
 lock_period_days integer, created_at timestamptz not null default now()
);
create table public.referral_commissions (
 id uuid primary key default gen_random_uuid(), referrer_id uuid not null references public.profiles(id) on delete restrict,
 invitee_id uuid not null unique references public.profiles(id) on delete restrict,
 qualifying_transaction_id uuid not null unique references public.ledger_transactions(id) on delete restrict,
 rate_bps integer not null check(rate_bps=5000), amount_minor bigint not null check(amount_minor>0),
 status text not null default 'pending' check(status in ('pending','credited','reversed')),
 created_at timestamptz not null default now(), credited_at timestamptz,
 check(referrer_id<>invitee_id)
);
create table public.admin_roles (user_id uuid primary key references public.profiles(id) on delete restrict, role text not null check(role in ('super_admin','finance','support','compliance')), permissions text[] not null default '{}');
create table public.audit_log (
 id uuid primary key default gen_random_uuid(), actor_id uuid references public.profiles(id) on delete restrict,
 action text not null, entity_type text not null, entity_id uuid, details jsonb not null default '{}', created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
alter table public.asset_accounts enable row level security;
alter table public.ledger_transactions enable row level security;
alter table public.ledger_entries enable row level security;
alter table public.investment_plans enable row level security;
alter table public.investments enable row level security;
alter table public.staking_positions enable row level security;
alter table public.referral_commissions enable row level security;
alter table public.admin_roles enable row level security;
alter table public.audit_log enable row level security;
create policy "profiles own read" on public.profiles for select using (id=auth.uid());
create policy "assets own read" on public.asset_accounts for select using (owner_id=auth.uid());
create policy "transactions own read" on public.ledger_transactions for select using (owner_id=auth.uid());
create policy "ledger entries own read" on public.ledger_entries for select using (
 exists (select 1 from public.asset_accounts a where a.id=account_id and a.owner_id=auth.uid())
);
create policy "investment plans active read" on public.investment_plans for select using (active=true);
create policy "investments own read" on public.investments for select using (owner_id=auth.uid());
create policy "staking own read" on public.staking_positions for select using (owner_id=auth.uid());
create policy "commissions party read" on public.referral_commissions for select using (referrer_id=auth.uid());
create policy "admin role self read" on public.admin_roles for select using (user_id=auth.uid());
-- No client write policies on financial or administrative tables. Use audited server-side RPCs.

-- Return only the signed-in member's referral counts and commission totals; do not
-- expose invitee profile details through this aggregate.
create or replace function public.member_referral_summary()
returns jsonb language sql stable security definer set search_path = '' as $$
 select jsonb_build_object(
  'direct_referrals', (select count(*) from public.profiles p where p.referred_by=auth.uid()),
  'qualifying_referrals', (select count(*) from public.referral_commissions c where c.referrer_id=auth.uid() and c.status in ('credited','pending')),
  'credited_minor', coalesce((select sum(c.amount_minor) from public.referral_commissions c where c.referrer_id=auth.uid() and c.status='credited'),0),
  'pending_minor', coalesce((select sum(c.amount_minor) from public.referral_commissions c where c.referrer_id=auth.uid() and c.status='pending'),0)
 );
$$;
revoke all on function public.member_referral_summary() from public;
grant execute on function public.member_referral_summary() to authenticated;
