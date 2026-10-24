-- pgTAP: drop_summary, apply_transactions and sweep_drops behaviour.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-111111111111', 'a@test.dev', '{"display_name":"Ada"}');

select is(
  (select threshold_cents from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  500, 'new user gets a profile with the $5.00 default threshold');
select is(
  (select display_name from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  'Ada', 'display_name comes from signup metadata');
select is(
  (select pending_cents from public.drop_summary where user_id = '11111111-1111-1111-1111-111111111111'),
  0::bigint, 'summary exists with zero pending before any transaction');

select public.apply_transactions('11111111-1111-1111-1111-111111111111',
  '[{"plaid_transaction_id":"t1","merchant_name":"Blue Bottle","amount_cents":567,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":"FOOD_AND_DRINK","roundup_cents":33,"roundup_status":"pending"}]'::jsonb,
  '{}');
select is(
  (select pending_cents from public.drop_summary where user_id = '11111111-1111-1111-1111-111111111111'),
  33::bigint, 'pending drop is summed');
select is(
  (select count(*) from public.sweep_drops('11111111-1111-1111-1111-111111111111', 'SOL', 100)),
  0::bigint, 'below threshold: sweep returns no row');

select public.apply_transactions('11111111-1111-1111-1111-111111111111',
  '[{"plaid_transaction_id":"t2","merchant_name":"A","amount_cents":101,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":99,"roundup_status":"pending"},
    {"plaid_transaction_id":"t3","merchant_name":"B","amount_cents":101,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":99,"roundup_status":"pending"},
    {"plaid_transaction_id":"t4","merchant_name":"C","amount_cents":101,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":99,"roundup_status":"pending"},
    {"plaid_transaction_id":"t5","merchant_name":"D","amount_cents":101,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":99,"roundup_status":"pending"},
    {"plaid_transaction_id":"t6","merchant_name":"E","amount_cents":101,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":99,"roundup_status":"pending"},
    {"plaid_transaction_id":"s1","merchant_name":"Whole dollar","amount_cents":400,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":0,"roundup_status":"skipped"}]'::jsonb,
  '{}');

select results_eq(
  $$ select amount_cents, price_usd, quantity, mode
     from public.sweep_drops('11111111-1111-1111-1111-111111111111', 'SOL', 100) $$,
  $$ values (528::bigint, '100'::text, '0.0528'::text, 'simulated'::text) $$,
  'at threshold: invests the whole pending amount at the given price');
select is(
  (select count(*) from public.transactions
   where user_id = '11111111-1111-1111-1111-111111111111' and roundup_status = 'invested'),
  6::bigint, 'the six consumed rows are marked invested');
select is(
  (select roundup_status from public.transactions where plaid_transaction_id = 's1'),
  'skipped', 'skipped rows are not consumed');
select is(
  (select pending_cents from public.drop_summary where user_id = '11111111-1111-1111-1111-111111111111'),
  0::bigint, 'nothing pending after the sweep');
select is(
  (select count(*) from public.sweep_drops('11111111-1111-1111-1111-111111111111', 'SOL', 100)),
  0::bigint, 'a second sweep is a no-op');

select public.apply_transactions('11111111-1111-1111-1111-111111111111',
  '[{"plaid_transaction_id":"t1","merchant_name":"Blue Bottle (edited)","amount_cents":567,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":33,"roundup_status":"pending"}]'::jsonb,
  '{t2}');
select is(
  (select roundup_status || ':' || merchant_name from public.transactions where plaid_transaction_id = 't1'),
  'invested:Blue Bottle', 'upserts and removals never touch invested rows');

select public.apply_transactions('11111111-1111-1111-1111-111111111111',
  '[{"plaid_transaction_id":"t7","merchant_name":"Refunded","amount_cents":250,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":50,"roundup_status":"pending"}]'::jsonb,
  '{}');
select public.apply_transactions('11111111-1111-1111-1111-111111111111', '[]'::jsonb, '{t7}');
select is(
  (select roundup_status || ':' || roundup_cents from public.transactions where plaid_transaction_id = 't7'),
  'reversed:0', 'a removed pending transaction is reversed and zeroed');

update public.profiles set roundups_paused = true where id = '11111111-1111-1111-1111-111111111111';
select public.apply_transactions('11111111-1111-1111-1111-111111111111',
  '[{"plaid_transaction_id":"p1","merchant_name":"X","amount_cents":101,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":99,"roundup_status":"pending"},
    {"plaid_transaction_id":"p2","merchant_name":"Y","amount_cents":101,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":99,"roundup_status":"pending"},
    {"plaid_transaction_id":"p3","merchant_name":"Z","amount_cents":101,"iso_currency_code":"USD","date":"2026-10-24","pending":false,"category":null,"roundup_cents":99,"roundup_status":"pending"}]'::jsonb,
  '{}');
update public.profiles set threshold_cents = 200 where id = '11111111-1111-1111-1111-111111111111';
select is(
  (select count(*) from public.sweep_drops('11111111-1111-1111-1111-111111111111', 'SOL', 100)),
  0::bigint, 'paused users are never swept');

select results_eq(
  $$ select asset_symbol, invested_cents, quantity
     from public.portfolio_by_asset where user_id = '11111111-1111-1111-1111-111111111111' $$,
  $$ values ('SOL'::text, 528::bigint, '0.0528'::text) $$,
  'portfolio_by_asset aggregates invested cents and quantity per asset');

select * from finish();
rollback;
