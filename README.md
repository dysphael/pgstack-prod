# pgstack-prod

Production PostgreSQL 16 with persistent storage and DNS-based access for applications.

> **New to backups?** Read the full beginner guide: **[docs/BACKUP.md](docs/BACKUP.md)**

## Quick start

```bash
cp .env.example .env
nano .env                    # set POSTGRES_PASSWORD and POSTGRES_HOST
./scripts/setup.sh           # create folders and fix log permissions
docker compose up -d
./scripts/status.sh          # verify everything is healthy
```

## DNS

Create an **A record** pointing to this server's public IP:

```text
db.yourdomain.com  →  YOUR_VPS_PUBLIC_IP
```

Use the same hostname as `POSTGRES_HOST` in `.env`.

## Application connection

```text
postgresql://appuser:PASSWORD@db.yourdomain.com:5432/DATABASE_NAME
```

On the same VPS:

```text
postgresql://appuser:PASSWORD@localhost:5432/DATABASE_NAME
```

## Create a project database

**Simple** (shared `appuser`):

```bash
docker compose exec postgres psql -U appuser -d postgres -c "CREATE DATABASE myapp;"
```

**Recommended** (dedicated user per project):

```bash
./scripts/create-db.sh myapp
```

## Logs (persistent files)

PostgreSQL saves daily log files to `logs/postgres/`:

```bash
ls logs/postgres/
tail -f logs/postgres/postgresql-$(date +%Y-%m-%d).log
```

Logged events: connections, disconnections, schema changes (DDL), slow queries (> 500 ms).

If logs are not created, run:

```bash
sudo chown -R 70:70 logs/postgres
docker compose restart postgres
```

## Backup & restore (summary)

Full step-by-step guide for beginners: **[docs/BACKUP.md](docs/BACKUP.md)**

| Task | Command |
|------|---------|
| Backup one database | `./scripts/backup.sh myapp` |
| Backup all databases | `./scripts/backup.sh` |
| List backup files | `./scripts/backup.sh --list` |
| Restore a backup | `./scripts/restore.sh backups/backup_myapp_DATE.sql.gz myapp` |
| Health check | `./scripts/status.sh` |

## Verify DNS connectivity

| Step | Command |
|------|---------|
| DNS resolves | `dig +short A db.yourdomain.com` |
| Port open | `nc -zv db.yourdomain.com 5432` |
| DB accepts login | `psql "postgresql://appuser:PASSWORD@db.yourdomain.com:5432/postgres" -c "SELECT 1;"` |

## Security

| Practice | Details |
|----------|---------|
| Firewall | `sudo ufw allow from APP_SERVER_IP to any port 5432 proto tcp` |
| Strong password | 32+ random characters in `.env` |
| Per-project users | `./scripts/create-db.sh myapp` instead of sharing `appuser` |
| Localhost only | `POSTGRES_PORT_PUBLISH=127.0.0.1:5432:5432` if apps run on the same VPS |
| Copy backups off-server | `scp` or cloud sync — see [docs/BACKUP.md](docs/BACKUP.md) |

## Production defaults

| Feature | Implementation |
|---------|----------------|
| Persistent data | Docker volume `pgdata` |
| Persistent logs | `logs/postgres/postgresql-YYYY-MM-DD.log` |
| Integrity checks | `data-checksums` on new installs |
| Tuning | `postgres/conf/postgresql.conf` (defaults for 2 GB RAM) |
| Extensions | `uuid-ossp`, `pg_stat_statements` (first boot only) |
| Memory limit | `POSTGRES_MEM_LIMIT` (default 1536M) |
| Auth | `scram-sha-256` |

### Scaling memory

Edit `postgres/conf/postgresql.conf` for your VPS RAM, then `docker compose restart postgres`.

| VPS RAM | `shared_buffers` | `effective_cache_size` |
|---------|------------------|------------------------|
| 2 GB | 512MB | 1536MB |
| 4 GB | 1GB | 3GB |
| 8 GB | 2GB | 6GB |

## Environment variables

| Variable | Description |
|----------|-------------|
| `POSTGRES_USER` | Admin/application user |
| `POSTGRES_PASSWORD` | User password |
| `POSTGRES_DB` | Database created on first boot (`postgres` recommended) |
| `POSTGRES_HOST` | DNS hostname for connection strings (not used by Docker) |
| `POSTGRES_PORT_PUBLISH` | `5432:5432` or `127.0.0.1:5432:5432` |
| `POSTGRES_MEM_LIMIT` | Container memory cap (e.g. `1536M`) |
| `BACKUP_DIR` | Backup folder (default `./backups`) |
| `LOG_DIR` | Log folder (default `./logs/postgres`) |

## Operations

```bash
./scripts/status.sh
docker compose logs -f postgres
docker compose exec postgres psql -U appuser -d postgres
docker compose restart postgres
docker compose down              # stops container, keeps data
```

**Never run** `docker compose down -v` in production.

## Project layout

```text
pgstack-prod/
├── docker-compose.yml
├── docs/BACKUP.md
├── logs/postgres/              # persistent PostgreSQL log files
├── backups/                    # backup .sql.gz files
├── postgres/
│   ├── conf/postgresql.conf
│   └── init/01-extensions.sql
└── scripts/
    ├── setup.sh                # first-time folder setup
    ├── status.sh               # health check
    ├── backup.sh
    ├── restore.sh
    └── create-db.sh
```
