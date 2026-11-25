with cancelled as (
  update public.investments i
  set status = 'cancelled',
      updated_at = now()
  where i.status = 'pending'
    and exists (
      select 1
      from public.payment_proofs pp
      where pp.investment_id = i.id
        and pp.status in ('rejected', 'cancelled')
    )
  returning i.id, i.principal_minor
)
insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
select null, 'pending_investment_cancelled_by_migration', 'investment', c.id,
       jsonb_build_object(
         'principal_minor', c.principal_minor,
         'proof_id', (
           select pp.id
           from public.payment_proofs pp
           where pp.investment_id = c.id
             and pp.status in ('rejected', 'cancelled')
           order by pp.reviewed_at desc nulls last
           limit 1
         )
       )
from cancelled c;

create or replace function public.admin_review_payment_proof(
  p_id uuid,
  p_action text,
  p_note text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_proof public.payment_proofs;
  v_status public.payment_proof_status;
  v_transaction_id uuid;
begin
  if not public.has_admin_role(array['super_admin','finance','compliance']) then
    raise exception 'Administrator access required';
  end if;
  if p_action is null or p_action not in ('approve','reject','cancel') then
    raise exception 'Unsupported review action';
  end if;
  select * into v_proof
  from public.payment_proofs
  where id = p_id
  for update;
  if not found then
    raise exception 'Payment proof not found';
  end if;
  if v_proof.status <> 'pending' then
    raise exception 'Payment proof has already been reviewed';
  end if;

  if p_action = 'approve' then
    v_transaction_id := public.post_ledger(
      v_proof.owner_id,
      'deposit',
      v_proof.asset_code,
      v_proof.amount_minor,
      'Approved deposit proof ' || v_proof.id::text,
      'proof:' || v_proof.id::text
    );
    update public.payment_proofs
    set status = 'approved',
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        transaction_id = v_transaction_id,
        rejection_reason = null,
        updated_at = now()
    where id = p_id;
    if v_proof.investment_id is not null then
      perform public.activate_investment(v_proof.investment_id);
    end if;
    v_status := 'approved';
  else
    v_status := case p_action
      when 'reject' then 'rejected'::public.payment_proof_status
      else 'cancelled'::public.payment_proof_status
    end;
    update public.payment_proofs
    set status = v_status,
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        rejection_reason = nullif(trim(coalesce(p_note, '')), ''),
        updated_at = now()
    where id = p_id;
    if v_proof.investment_id is not null then
      update public.investments
      set status = 'cancelled',
          updated_at = now()
      where id = v_proof.investment_id
        and status = 'pending';
    end if;
  end if;

  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    'payment_proof_' || p_action,
    'payment_proof',
    p_id,
    jsonb_build_object(
      'status', v_status,
      'amount_minor', v_proof.amount_minor,
      'investment_id', v_proof.investment_id,
      'note', p_note
    )
  );
  return jsonb_build_object(
    'id', p_id,
    'status', v_status,
    'investment_id', v_proof.investment_id
  );
end;
$$;

create or replace function public.admin_list_users(
  p_search text default '',
  p_status text default 'All users',
  p_limit integer default 50,
  p_offset integer default 0
)
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
      or lower(p.status::text) = lower(p_status)
      or (p_status = 'Verified' and p.verification_status = 'verified')
      or (p_status = 'Pending verification' and p.verification_status <> 'verified'));

  select jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', coalesce(nullif(p.full_name, ''), split_part(p.email, '@', 1), 'Member'),
    'email', p.email,
    'country', p.country,
    'phone', p.phone,
    'status', p.status,
    'verification_status', p.verification_status,
    'referral_code', p.referral_code,
    'role', p.role,
    'created_at', p.created_at,
    'balance_asset_code', amounts.asset_code,
    'balance_minor', amounts.balance_minor::text,
    'invested_minor', amounts.invested_minor::text,
    'bonus_minor', amounts.bonus_minor::text,
    'referral_minor', amounts.referral_minor::text,
    'portfolio_minor', (amounts.balance_minor + amounts.invested_minor)::text
  ) order by p.created_at desc) into v_rows
  from (
    select p.id, p.full_name, p.country, p.phone, p.status, p.verification_status,
           p.referral_code, p.created_at, u.email, ar.role
    from public.profiles p
    join auth.users u on u.id = p.id
    left join public.admin_roles ar on ar.user_id = p.id
    where (coalesce(p_search, '') = ''
        or p.full_name ilike '%' || p_search || '%'
        or u.email ilike '%' || p_search || '%'
        or p.id::text = p_search)
      and (coalesce(p_status, 'All users') in ('All users', '')
        or lower(p.status::text) = lower(p_status)
        or (p_status = 'Verified' and p.verification_status = 'verified')
        or (p_status = 'Pending verification' and p.verification_status <> 'verified'))
    order by p.created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 200))
    offset greatest(0, coalesce(p_offset, 0))
  ) p
  cross join lateral (
    select public.currency_for_country(p.country) as asset_code
  ) preferred
  cross join lateral (
    select
      preferred.asset_code,
      coalesce((
        select sum(le.amount_minor)
        from public.asset_accounts aa
        join public.ledger_entries le on le.account_id = aa.id
        where aa.owner_id = p.id and aa.asset_code = preferred.asset_code
      ), 0) as balance_minor,
      coalesce((
        select sum(i.principal_minor)
        from public.investments i
        where i.owner_id = p.id
          and i.asset_code = preferred.asset_code
          and i.status = 'active'
      ), 0) as invested_minor,
      coalesce((
        select sum(le.amount_minor)
        from public.asset_accounts aa
        join public.ledger_entries le on le.account_id = aa.id
        join public.ledger_transactions t on t.id = le.transaction_id
        where aa.owner_id = p.id
          and aa.asset_code = preferred.asset_code
          and t.status = 'completed'
          and t.kind::text in ('bonus_credit','bonus_debit')
      ), 0) as bonus_minor,
      coalesce((
        select sum(c.amount_minor)
        from public.referral_commissions c
        join public.ledger_transactions t on t.id = c.qualifying_transaction_id
        where c.referrer_id = p.id
          and c.status = 'credited'
          and t.asset_code = preferred.asset_code
      ), 0) as referral_minor
  ) amounts;

  return jsonb_build_object('total', v_total, 'rows', coalesce(v_rows, '[]'::jsonb));
end;
$$;

create or replace function public.member_roi_summary()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'paid_minor', coalesce((
      select sum(i.total_roi_paid_minor)
      from public.investments i
      where i.owner_id = auth.uid()
        and i.status <> 'pending'
        and i.asset_code = public.currency_for_country(
          (select p.country from public.profiles p where p.id = auth.uid())
        )
    ), 0),
    'accrued_minor', coalesce((
      select sum(round(
        (i.principal_minor::numeric * i.roi_rate_bps *
         greatest(extract(epoch from (now() - case
           when i.total_roi_paid_minor > 0
             then coalesce(i.last_roi_at, i.activated_at) + make_interval(hours => i.roi_interval_hours)
           else coalesce(i.activated_at, i.last_roi_at)
         end)) / 3600, 0) /
         nullif(i.roi_interval_hours, 0)) / 10000
      ))
      from public.investments i
      where i.owner_id = auth.uid() and i.status = 'active' and i.roi_rate_bps > 0
        and i.asset_code = public.currency_for_country(
          (select p.country from public.profiles p where p.id = auth.uid())
        )
    ), 0),
    'daily_minor', coalesce((
      select sum(round(i.principal_minor::numeric * i.roi_rate_bps / 10000))
      from public.investments i
      where i.owner_id = auth.uid() and i.status = 'active' and i.roi_rate_bps > 0
        and i.asset_code = public.currency_for_country(
          (select p.country from public.profiles p where p.id = auth.uid())
        )
    ), 0),
    'next_credit_at', (
      select min(i.next_roi_at)
      from public.investments i
      where i.owner_id = auth.uid() and i.status = 'active' and i.roi_rate_bps > 0
        and i.asset_code = public.currency_for_country(
          (select p.country from public.profiles p where p.id = auth.uid())
        )
    ),
    'investments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'plan', pl.name, 'principal_minor', i.principal_minor,
        'asset_code', i.asset_code, 'status', i.status, 'rate_bps', i.roi_rate_bps,
        'daily_minor', round(i.principal_minor::numeric * i.roi_rate_bps / 10000),
        'paid_minor', i.total_roi_paid_minor, 'next_roi_at', i.next_roi_at,
        'activated_at', i.activated_at
      ) order by i.created_at desc)
      from public.investments i
      join public.investment_plans pl on pl.id = i.plan_id
      where i.owner_id = auth.uid()
        and i.status in ('active', 'completed')
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.admin_review_payment_proof(uuid,text,text) from public;
grant execute on function public.admin_review_payment_proof(uuid,text,text) to authenticated;
revoke all on function public.admin_list_users(text,text,integer,integer) from public;
grant execute on function public.admin_list_users(text,text,integer,integer) to authenticated;
revoke all on function public.member_roi_summary() from public;
grant execute on function public.member_roi_summary() to authenticated;
