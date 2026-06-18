# pgstack-prod

PostgreSQL 16 em produção — Docker Compose lite com persistência.

## Quick start

```bash
cp .env.example .env
nano .env          # set a strong POSTGRES_PASSWORD
docker compose up -d
docker compose ps  # wait for "healthy"
```

## Environment

| Variable | Description |
|----------|-------------|
| `POSTGRES_USER` | Application user | `appuser` |
| `POSTGRES_PASSWORD` | User password | strong secret |
| `POSTGRES_DB` | Database created on **first boot only** | `postgres` (recommended) |

`POSTGRES_DB=postgres` uses the standard admin database. Project databases (`blockway`, `hyperfx`, etc.) are created manually when needed.

## Create a project database

```bash
docker compose exec postgres psql -U appuser -d postgres -c "CREATE DATABASE blockway;"
```

Connect to it:

```text
postgresql://appuser:PASSWORD@localhost:5432/blockway
```

List databases:

```bash
docker compose exec postgres psql -U appuser -d postgres -c "\l"
```

## Production defaults

- Port `5432` bound to `127.0.0.1` only (not exposed to the internet)
- Data stored in Docker volume `pgdata`
- UTF-8 encoding, `data-checksums` on new installs
- Healthcheck, log rotation, graceful shutdown
- Container restarts automatically (`unless-stopped`)

## Operations

```bash
docker compose ps
docker compose logs -f postgres
docker compose exec postgres psql -U appuser -d postgres
docker compose restart postgres
docker compose down              # stops container, keeps data
```

**Never run** `docker compose down -v` in production — it deletes the volume and all data.

## Backup

```bash
docker compose exec -T postgres pg_dump -U appuser blockway | gzip > backup_blockway_$(date +%Y%m%d).sql.gz
```

Restore:

```bash
gunzip -c backup_blockway_20260101.sql.gz | docker compose exec -T postgres psql -U appuser -d blockway
```

## Notes

- `POSTGRES_DB` only applies on the **first** initialization (empty volume). Changing it later does not rename existing data.
- Other Docker containers on the same host can reach Postgres via `host.docker.internal:5432` (Docker Desktop) or the host gateway IP on Linux.
