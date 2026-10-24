-- Droplet schema: tables in foreign-key order, plus the curated asset seed.
-- Money is integer cents; asset price/quantity are numeric(38,18).

create table public.assets (
  symbol      text primary key,
  name        text not null,
  chain       text not null,
  tm_asset_id uuid not null,
  icon_url    text,
  sort_order  int  not null default 0,
  enabled     boolean not null default true
);

insert into public.assets (symbol, name, chain, tm_asset_id, icon_url, sort_order) values
  ('SOL',    'Solana',          'solana', '495e07ac-fa3e-4179-85b7-b1e8cece3dc4', 'https://coin-images.coingecko.com/coins/images/4128/large/solana.png?1718769756', 1),
  ('ETH',    'Ethereum',        'base',   '28e9d809-26ec-4269-ba55-b1cd1e052cd8', 'https://coin-images.coingecko.com/coins/images/279/large/ethereum.png?1696501628', 2),
  ('CBBTC',  'Bitcoin (cbBTC)', 'base',   'f227d00e-1665-47e0-b598-959387a19373', 'https://coin-images.coingecko.com/coins/images/40143/large/cbbtc.webp?1726136727', 3),
  ('AAVE',   'Aave',            'base',   '64925b1c-338b-487f-bba0-3484764b4856', 'https://coin-images.coingecko.com/coins/images/12645/large/aave-token-round.png?1720472354', 4),
  ('JUP',    'Jupiter',         'solana', 'f7fc05d1-f30a-4765-b527-8b12aaa649dc', 'https://coin-images.coingecko.com/coins/images/34188/large/jup.png?1704266489', 5),
  ('RENDER', 'Render',          'solana', 'bbed4a7b-491b-4e44-a04b-9991c1612a97', 'https://coin-images.coingecko.com/coins/images/11636/large/rndr.png?1696511529', 6);

create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  display_name    text not null default '',
  threshold_cents int  not null default 500 check (threshold_cents in (200, 500, 1000)),
  target_asset    text not null default 'SOL' references public.assets (symbol),
  roundups_paused boolean not null default false,
  created_at      timestamptz not null default now()
);

-- Holds the Plaid access token. RLS on with no policies and no client grants (see rls migration),
-- so only the service role (Edge Functions) can read it.
create table public.plaid_items (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null unique references auth.users (id) on delete cascade,
  item_id          text not null unique,
  access_token     text not null,
  cursor           text,
  institution_name text,
  status           text not null default 'active' check (status in ('active', 'login_required', 'error')),
  linked_on        date not null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- Client-safe mirror of plaid_items (no token).
create table public.bank_connections (
  user_id          uuid primary key references auth.users (id) on delete cascade,
  institution_name text,
  status           text not null default 'active' check (status in ('active', 'login_required', 'error')),
  last_synced_at   timestamptz
);

create table public.investments (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  asset_symbol text not null references public.assets (symbol),
  amount_cents bigint not null check (amount_cents > 0),
  price_usd    numeric(38, 18) not null check (price_usd > 0),
  quantity     numeric(38, 18) not null check (quantity > 0),
  mode         text not null default 'simulated' check (mode in ('simulated', 'live')),
  status       text not null default 'filled' check (status in ('filled', 'failed')),
  tm_order_id  text,
  created_at   timestamptz not null default now()
);
create index investments_user_created_idx on public.investments (user_id, created_at desc);

create table public.transactions (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references auth.users (id) on delete cascade,
  plaid_transaction_id text not null unique,
  merchant_name        text not null,
  amount_cents         bigint not null,
  iso_currency_code    text not null default 'USD',
  date                 date not null,
  pending              boolean not null default false,
  category             text,
  roundup_cents        int not null default 0 check (roundup_cents between 0 and 99),
  roundup_status       text not null check (roundup_status in ('pending', 'invested', 'skipped', 'reversed')),
  investment_id        uuid references public.investments (id),
  created_at           timestamptz not null default now()
);
create index transactions_user_date_idx on public.transactions (user_id, date desc, created_at desc);
create index transactions_user_pending_idx on public.transactions (user_id) where roundup_status = 'pending';
create index transactions_investment_idx on public.transactions (investment_id);
