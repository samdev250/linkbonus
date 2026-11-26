create table if not exists public.member_withdrawal_accounts (
  owner_id uuid primary key references public.profiles(id) on delete cascade,
  payout_method text not null check (payout_method in ('mobile_money', 'bank')),
  payout_provider text not null,
  payout_account_name text not null,
  payout_account_number text not null,
  updated_at timestamptz not null default now()
);

alter table public.member_withdrawal_accounts enable row level security;
revoke all on public.member_withdrawal_accounts from public, anon, authenticated;

create or replace function public.member_get_withdrawal_account()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_account public.member_withdrawal_accounts;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_account
  from public.member_withdrawal_accounts a
  where a.owner_id = auth.uid();
  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'payout_method', v_account.payout_method,
    'payout_provider', v_account.payout_provider,
    'payout_account_name', v_account.payout_account_name,
    'payout_account_number', v_account.payout_account_number,
    'updated_at', v_account.updated_at
  );
end;
$$;

create or replace function public.member_save_withdrawal_account(
  p_payout_method text,
  p_payout_provider text,
  p_payout_account_name text,
  p_payout_account_number text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_owner_id uuid := auth.uid();
  v_provider text := btrim(coalesce(p_payout_provider, ''));
  v_account_name text := btrim(coalesce(p_payout_account_name, ''));
  v_account_number text := btrim(coalesce(p_payout_account_number, ''));
begin
  if v_owner_id is null then
    raise exception 'Authentication required';
  end if;
  if p_payout_method is null or p_payout_method not in ('mobile_money', 'bank') then
    raise exception 'Choose mobile money or bank payout';
  end if;
  if v_provider = '' or v_account_name = '' or v_account_number = '' then
    raise exception 'Complete the payout provider, account name, and account number';
  end if;
  if length(v_provider) > 120 or length(v_account_name) > 160 or length(v_account_number) > 80 then
    raise exception 'Payout details are too long';
  end if;

  insert into public.member_withdrawal_accounts(
    owner_id, payout_method, payout_provider, payout_account_name, payout_account_number, updated_at
  ) values (
    v_owner_id, p_payout_method, v_provider, v_account_name, v_account_number, now()
  )
  on conflict (owner_id) do update
  set payout_method = excluded.payout_method,
      payout_provider = excluded.payout_provider,
      payout_account_name = excluded.payout_account_name,
      payout_account_number = excluded.payout_account_number,
      updated_at = excluded.updated_at;

  return jsonb_build_object(
    'payout_method', p_payout_method,
    'payout_provider', v_provider,
    'payout_account_name', v_account_name,
    'payout_account_number', v_account_number
  );
end;
$$;

revoke all on function public.member_get_withdrawal_account() from public, anon;
revoke all on function public.member_save_withdrawal_account(text, text, text, text) from public, anon;
grant execute on function public.member_get_withdrawal_account() to authenticated;
grant execute on function public.member_save_withdrawal_account(text, text, text, text) to authenticated;
