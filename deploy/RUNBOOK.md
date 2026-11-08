# n8n VPS Runbook

Placeholders: `<VPS_IP>`, `n8n.example.com`. Project lives in `/home/deploy/n8n`, compose files in `/home/deploy/n8n/deploy`.

> **WARNING: `N8N_ENCRYPTION_KEY` must be backed up SEPARATELY from the dumps** (password manager, not the same Supabase bucket). A restored database without the original key cannot decrypt any saved credential.

## Connect and check

```bash
ssh deploy@<VPS_IP>
cd /home/deploy/n8n/deploy
docker compose ps                       # all three should be Up; postgres "healthy"
docker compose logs --tail 100 n8n      # also: postgres, caddy
docker compose logs -f --tail 50 n8n    # follow live (Ctrl+C to stop)
```

## Restart

```bash
docker compose restart n8n              # one service
docker compose up -d                    # (re)create anything that changed
```

## Update n8n

```bash
cd /home/deploy/n8n/deploy
./backup.sh                             # always back up first
docker compose pull n8n
docker compose up -d
docker compose logs --tail 50 n8n       # watch for migration errors
```

## Backup now

```bash
/home/deploy/n8n/deploy/backup.sh
ls -lh /home/deploy/backups
```

Needs `/home/deploy/.backup.env` (`chmod 600`) with `SUPABASE_URL`, `SUPABASE_BUCKET`, `SUPABASE_SERVICE_KEY`. Cron line is documented at the top of `backup.sh`.

## Restore test (safe, run regularly)

Restores into a scratch database, prints the workflow count, drops it. Live data is untouched.

```bash
/home/deploy/n8n/deploy/restore-test.sh /home/deploy/backups/n8n-YYYYmmdd-HHMMSS.dump
```

## Real restore (disaster recovery)

Overwrites live data. Use the same `N8N_ENCRYPTION_KEY` as when the dump was taken.

```bash
cd /home/deploy/n8n/deploy
# 0. Copy the dump to the server if needed (download from Supabase, or scp from your PC)
# 1. Stop n8n so nothing writes during the restore
docker compose stop n8n
# 2. Recreate the database
docker compose exec -T postgres sh -c 'dropdb -U "$POSTGRES_USER" "$POSTGRES_DB" && createdb -U "$POSTGRES_USER" "$POSTGRES_DB"'
# 3. Restore
docker compose exec -T postgres sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner' < /home/deploy/backups/n8n-YYYYmmdd-HHMMSS.dump
# 4. Start n8n and check workflows and credentials in the UI
docker compose start n8n
docker compose logs --tail 50 n8n
```

## Where secrets live

| Secret | Location |
|---|---|
| Postgres password, `N8N_ENCRYPTION_KEY`, domain | `/home/deploy/n8n/deploy/.env` (`chmod 600`) |
| Supabase URL, bucket, service key | `/home/deploy/.backup.env` (`chmod 600`) |
| Copy of `N8N_ENCRYPTION_KEY` | Password manager (separate from dumps) |
| TLS certificates | Docker volume `caddy_data` (do not delete) |

None of these are in git.

## After a reboot

```bash
ssh deploy@<VPS_IP>
cd /home/deploy/n8n/deploy
docker compose ps                       # restart: unless-stopped should have brought everything back
curl -I https://n8n.example.com         # expect HTTP/2 200 (or a redirect to /signin)
```

If Docker itself did not start: `sudo systemctl enable --now docker`.
