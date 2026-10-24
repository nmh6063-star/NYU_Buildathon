-- Safety-net sync every 15 minutes. Reads the target URL and shared secret from Vault, so the job
-- is a no-op until Task 19 stores `droplet_functions_url` and `droplet_cron_secret` for this project.

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

select cron.schedule(
  'droplet-sync-all',
  '*/15 * * * *',
  $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'droplet_functions_url') || '/sync-all',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'droplet_cron_secret')
    ),
    body    := '{}'::jsonb
  )
  where exists (select 1 from vault.decrypted_secrets where name = 'droplet_functions_url')
    and exists (select 1 from vault.decrypted_secrets where name = 'droplet_cron_secret');
  $$
);
