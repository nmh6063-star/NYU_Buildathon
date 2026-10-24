-- New-user trigger, read views, and the two atomic RPCs used by Edge Functions.

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create view public.drop_summary with (security_invoker = true) as
select
  p.id                                          as user_id,
  coalesce(t.pending_cents, 0)::bigint          as pending_cents,
  p.threshold_cents                             as threshold_cents,
  coalesce(t.lifetime_roundup_cents, 0)::bigint as lifetime_roundup_cents,
  coalesce(i.invested_cents, 0)::bigint         as invested_cents
from public.profiles p
left join lateral (
  select
    sum(x.roundup_cents) filter (where x.roundup_status = 'pending')               as pending_cents,
    sum(x.roundup_cents) filter (where x.roundup_status in ('pending', 'invested')) as lifetime_roundup_cents
  from public.transactions x
  where x.user_id = p.id
) t on true
left join lateral (
  select sum(y.amount_cents) as invested_cents
  from public.investments y
  where y.user_id = p.id and y.status = 'filled'
) i on true;

create view public.portfolio_by_asset with (security_invoker = true) as
select
  i.user_id,
  i.asset_symbol,
  a.name                            as asset_name,
  a.icon_url,
  sum(i.amount_cents)::bigint       as invested_cents,
  trim_scale(sum(i.quantity))::text as quantity,
  max(i.created_at)                 as last_invested_at
from public.investments i
join public.assets a on a.symbol = i.asset_symbol
where i.status = 'filled'
group by i.user_id, i.asset_symbol, a.name, a.icon_url;

-- Views inherit Supabase's default privileges (ALL to anon/authenticated); narrow them to read-only.
revoke all on public.drop_summary, public.portfolio_by_asset from anon, authenticated;
grant select on public.drop_summary, public.portfolio_by_asset to authenticated;

-- Upserts mapped Plaid rows and reverses removed ones. Never touches rows already invested.
create function public.apply_transactions(p_user uuid, p_rows jsonb, p_removed text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.transactions as t (
    user_id, plaid_transaction_id, merchant_name, amount_cents, iso_currency_code,
    date, pending, category, roundup_cents, roundup_status
  )
  select
    p_user, r.plaid_transaction_id, r.merchant_name, r.amount_cents, coalesce(r.iso_currency_code, 'USD'),
    r.date, r.pending, r.category, r.roundup_cents, r.roundup_status
  from jsonb_to_recordset(coalesce(p_rows, '[]'::jsonb)) as r (
    plaid_transaction_id text, merchant_name text, amount_cents bigint, iso_currency_code text,
    date date, pending boolean, category text, roundup_cents int, roundup_status text
  )
  on conflict (plaid_transaction_id) do update set
    merchant_name     = excluded.merchant_name,
    amount_cents      = excluded.amount_cents,
    iso_currency_code = excluded.iso_currency_code,
    date              = excluded.date,
    pending           = excluded.pending,
    category          = excluded.category,
    roundup_cents     = excluded.roundup_cents,
    roundup_status    = excluded.roundup_status
  where t.user_id = p_user and t.roundup_status <> 'invested';

  update public.transactions
  set roundup_status = 'reversed', roundup_cents = 0
  where user_id = p_user
    and plaid_transaction_id = any (coalesce(p_removed, '{}'::text[]))
    and roundup_status in ('pending', 'skipped');
end;
$$;

-- Invests every pending drop for a user once the total reaches their threshold.
-- Locks the profile row (serialises concurrent sweeps) and the pending rows it consumes.
create function public.sweep_drops(p_user uuid, p_asset text, p_price numeric)
returns table (
  id uuid, asset_symbol text, amount_cents bigint, price_usd text,
  quantity text, mode text, created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_profile public.profiles;
  v_ids     uuid[];
  v_pending bigint;
  v_inv     public.investments;
begin
  if p_price is null or p_price <= 0 then
    raise exception 'sweep_drops: price must be positive';
  end if;

  select * into v_profile from public.profiles where public.profiles.id = p_user for update;
  if not found or v_profile.roundups_paused then
    return;
  end if;

  select coalesce(array_agg(s.id), '{}'::uuid[]), coalesce(sum(s.roundup_cents), 0)
    into v_ids, v_pending
  from (
    select x.id, x.roundup_cents
    from public.transactions x
    where x.user_id = p_user and x.roundup_status = 'pending'
    for update
  ) s;

  if v_pending < v_profile.threshold_cents then
    return;
  end if;

  insert into public.investments (user_id, asset_symbol, amount_cents, price_usd, quantity, mode)
  values (p_user, p_asset, v_pending, p_price, round((v_pending::numeric / 100) / p_price, 18), 'simulated')
  returning * into v_inv;

  update public.transactions
  set roundup_status = 'invested', investment_id = v_inv.id
  where public.transactions.id = any (v_ids);

  return query select
    v_inv.id, v_inv.asset_symbol, v_inv.amount_cents,
    trim_scale(v_inv.price_usd)::text, trim_scale(v_inv.quantity)::text,
    v_inv.mode, v_inv.created_at;
end;
$$;

revoke execute on function public.apply_transactions(uuid, jsonb, text[]) from public, anon, authenticated;
revoke execute on function public.sweep_drops(uuid, text, numeric) from public, anon, authenticated;
grant execute on function public.apply_transactions(uuid, jsonb, text[]) to service_role;
grant execute on function public.sweep_drops(uuid, text, numeric) to service_role;
