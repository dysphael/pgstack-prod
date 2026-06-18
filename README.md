# pgstack-prod

Production PostgreSQL 16 with persistent storage and DNS-based access for applications.

> **Scripts:** Quick guide → **[docs/SCRIPTS.md](docs/SCRIPTS.md)**  
> **Backups (beginner):** Full guide → **[docs/BACKUP.md](docs/BACKUP.md)**

## Quick start

```bash
cp .env.example .env
nano .env                    # set POSTGRES_PASSWORD and POSTGRES_HOST
docker compose up -d         # creates folders and starts PostgreSQL
./bin/manager.sh              # interactive manager (or ./manager.sh)
```

Or run individual scripts:

```bash
./scripts/overview/status.sh   # verify everything is healthy
```

## DNS

Create an **A record** pointing to this server's public IP:

```text
db.yourdomain.com  →  YOUR_VPS_PUBLIC_IP
```

Use the same hostname as `POSTGRES_HOST` in `.env`.

## Application connection

Use the **project owner** user from `create-db.sh` — not `appuser`:

```text
postgresql://myapp_owner:PASSWORD@db.yourdomain.com:5432/myapp
```

## Create a project database

Creates **only the database** (schema `app`). Users are **optional** — you choose if, when, and which to create.

```bash
./scripts/databases/create-db.sh myapp
```

Flow:
1. Creates database `myapp`
2. Asks: **Add a user? (y/n)** — repeat as needed
3. For each user: choose access → username → password

| Access | What it can do |
|--------|----------------|
| `owner` | Read, write, delete, create tables (main app) |
| `read` | Read only |
| `write` | Read + write on tables |
| `admin` | Create read/write users for this DB |

**Add users later:**

```bash
./scripts/users/add-user.sh myapp owner myapp_app
./scripts/users/add-user.sh myapp read analytics
./scripts/users/add-user.sh myapp write worker
./scripts/users/add-user.sh myapp admin myapp_admin
```

**App connection (example):**

```text
postgresql://myapp_app:PASSWORD@db.yourdomain.com:5432/myapp
```

## Logs (persistent files)

PostgreSQL saves daily log files to `logs/postgres/`:

```bash
ls logs/postgres/
tail -f logs/postgres/postgresql-$(date +%Y-%m-%d).log
```

Logged events: schema changes (DDL) and slow queries (> 500 ms).

Folders `logs/postgres/` and `backups/` are created automatically on `docker compose up`.

## Backup & restore (summary)

| Task | Command |
|------|---------|
| Backup one database | `./scripts/backups/backup.sh myapp` |
| Backup all databases | `./scripts/backups/backup.sh` |
| List backup files | `./scripts/backups/list-backups.sh` |
| Restore a backup | `./scripts/backups/restore.sh backups/backup_myapp_DATE.sql.gz myapp` |
| Health check | `./scripts/overview/status.sh` |

See **[docs/SCRIPTS.md](docs/SCRIPTS.md)** for what each script does.  
See **[docs/BACKUP.md](docs/BACKUP.md)** for the full backup/restore walkthrough.

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
| Per-project users | `./scripts/databases/create-db.sh` + `./scripts/users/add-user.sh` |
| Localhost only | `POSTGRES_PORT_PUBLISH=127.0.0.1:5432:5432` if apps run on the same VPS |
| Copy backups off-server | `scp` or cloud sync — see [docs/BACKUP.md](docs/BACKUP.md) |

## Troubleshooting

### `role "X" does not exist` / login failed for admin user

`POSTGRES_USER` and `POSTGRES_PASSWORD` are applied **only on first boot** (empty Docker volume). Changing `.env` later does not rename the admin user.

**Fresh install (no data to keep):**

```bash
docker compose down
docker volume rm pgstack-prod_pgdata    # name may vary: docker volume ls | grep pgdata
docker compose up -d
./scripts/overview/status.sh
```

**Already has databases:** put the **original** `POSTGRES_USER` back in `.env` (the one used on first `docker compose up`), then restart:

```bash
docker compose restart postgres
```

---

| Feature | Implementation |
|---------|----------------|
| Persistent data | Docker volume `pgdata` |
| Persistent logs | `logs/postgres/postgresql-YYYY-MM-DD.log` |
| Integrity checks | `data-checksums` on new installs |
| Tuning | `postgres/conf/postgresql.conf` (defaults for 2 GB RAM) |
| Extensions | `uuid-ossp`, `pg_stat_statements` (first boot only) |
| Memory limit | `POSTGRES_MEM_LIMIT` (default 1536M) |
| Auth | `scram-sha-256` |
| Logs | DDL + slow queries (> 500 ms), daily rotation |

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
./bin/manager.sh                              # interactive menu
./scripts/overview/db-stats.sh                # sizes, connections, cache hit
./scripts/overview/connections.sh             # active queries
./scripts/overview/logs.sh --tail 50          # recent log lines
./scripts/databases/conn-info.sh myapp        # connection strings
docker compose logs -f postgres
docker compose restart postgres
docker compose down                           # stops container, keeps data
```

**Never run** `docker compose down -v` in production.

## Project layout

```text
pgstack-prod/
├── manager.sh                  # shortcut → bin/manager.sh
├── bin/
│   └── manager.sh              # interactive menu
├── lib/                        # shared helpers (internal)
├── scripts/
│   ├── overview/               # status, stats, connections, logs
│   ├── databases/              # create, list, drop, conn-info
│   ├── users/                  # add, list, reset, drop
│   ├── backups/                # backup, list, restore
│   └── tools/                  # psql shell
├── docker-compose.yml
├── docs/
│   ├── SCRIPTS.md
│   └── BACKUP.md
├── logs/postgres/
├── backups/
└── postgres/
    ├── entrypoint-wrapper.sh
    ├── conf/postgresql.conf
    └── init/01-extensions.sql
```
