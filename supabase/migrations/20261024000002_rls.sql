-- Row level security: clients read only their own rows; only Edge Functions (service_role) write
-- transactions, investments, plaid_items and bank_connections.

alter table public.assets           enable row level security;
alter table public.profiles         enable row level security;
alter table public.plaid_items      enable row level security;
alter table public.bank_connections enable row level security;
alter table public.investments      enable row level security;
alter table public.transactions     enable row level security;

revoke all on table public.assets, public.profiles, public.plaid_items,
  public.bank_connections, public.investments, public.transactions
  from anon, authenticated;

grant select on table public.assets to authenticated;
create policy "assets are readable" on public.assets
  for select to authenticated using (enabled);

grant select on table public.profiles to authenticated;
grant update (display_name, threshold_cents, target_asset, roundups_paused) on table public.profiles to authenticated;
create policy "read own profile" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy "update own profile" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

grant select on table public.bank_connections to authenticated;
create policy "read own bank connection" on public.bank_connections
  for select to authenticated using ((select auth.uid()) = user_id);

grant select on table public.investments to authenticated;
create policy "read own investments" on public.investments
  for select to authenticated using ((select auth.uid()) = user_id);

grant select on table public.transactions to authenticated;
create policy "read own transactions" on public.transactions
  for select to authenticated using ((select auth.uid()) = user_id);

-- public.plaid_items: intentionally no grants and no policies for anon/authenticated.
