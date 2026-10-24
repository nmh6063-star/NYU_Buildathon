-- pgTAP: users only see their own rows; plaid_items and the RPCs are unreachable from clients.
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

insert into public.plaid_items (user_id, item_id, access_token, linked_on)
values ('11111111-1111-1111-1111-111111111111', 'item-a', 'access-sandbox-fake', '2026-10-24');
insert into public.bank_connections (user_id, institution_name)
values ('11111111-1111-1111-1111-111111111111', 'First Platypus Bank');
select public.apply_transactions('11111111-1111-1111-1111-111111111111',
  '[{"plaid_transaction_id":"a1","merchant_name":"Blue Bottle","amount_cents":567,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":33,"roundup_status":"pending"}]'::jsonb, '{}');
select public.apply_transactions('22222222-2222-2222-2222-222222222222',
  '[{"plaid_transaction_id":"b1","merchant_name":"Sweetgreen","amount_cents":1342,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":58,"roundup_status":"pending"}]'::jsonb, '{}');

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select results_eq($$ select plaid_transaction_id from public.transactions $$, $$ values ('a1'::text) $$,
  'user A sees only their own transactions');
select results_eq($$ select count(*) from public.profiles $$, $$ values (1::bigint) $$,
  'user A sees only their own profile');
select results_eq($$ select pending_cents from public.drop_summary $$, $$ values (33::bigint) $$,
  'drop_summary is scoped to the caller');
select results_eq($$ select institution_name from public.bank_connections $$, $$ values ('First Platypus Bank'::text) $$,
  'user A sees their bank connection');
select results_eq($$ select count(*) from public.assets $$, $$ values (6::bigint) $$,
  'all six curated assets are readable');
select throws_ok($$ select * from public.plaid_items $$, '42501', null,
  'plaid_items is not readable by clients');
select throws_ok($$ select public.sweep_drops('11111111-1111-1111-1111-111111111111', 'SOL', 100) $$, '42501', null,
  'clients cannot call sweep_drops');
select throws_ok($$ insert into public.transactions (user_id, plaid_transaction_id, merchant_name, amount_cents, date, roundup_status)
                    values ('11111111-1111-1111-1111-111111111111', 'forged', 'X', 1, '2026-10-24', 'pending') $$, '42501', null,
  'clients cannot insert transactions');

update public.profiles set threshold_cents = 1000;
select results_eq($$ select threshold_cents from public.profiles $$, $$ values (1000) $$,
  'user A can update their own threshold');
select throws_ok($$ update public.profiles set id = '22222222-2222-2222-2222-222222222222' $$, '42501', null,
  'clients cannot update non-whitelisted profile columns');
select is(has_table_privilege('authenticated', 'public.drop_summary', 'INSERT, UPDATE, DELETE'), false,
  'views are read-only for signed-in users');

reset role;
set local role anon;
select throws_ok($$ select * from public.drop_summary $$, '42501', null,
  'anon cannot read drop_summary');
select throws_ok($$ select * from public.portfolio_by_asset $$, '42501', null,
  'anon cannot read portfolio_by_asset');

select * from finish();
rollback;
