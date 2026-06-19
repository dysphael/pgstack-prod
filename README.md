# pgstack-prod

Production PostgreSQL 16 with persistent storage and DNS-based access for applications.

> **Scripts:** Quick guide → **[docs/SCRIPTS.md](docs/SCRIPTS.md)**  
> **Backups (beginner):** Full guide → **[docs/BACKUP.md](docs/BACKUP.md)**

## Quick start

```bash
cp .env.example .env
nano .env                    # set POSTGRES_PASSWORD and POSTGRES_HOST
mkdir -p data/postgres data/backups data/logs/postgres
docker compose up -d         # starts PostgreSQL (persists under data/)
./bin/manager.sh              # interactive manager (or ./manager.sh)
```

All persistent files live under **`data/`** — database files, backups, and logs in one place. See [data/README.md](data/README.md).

The manager is a colorized terminal UI (72-column layout) with a live system dashboard, boxed menus, breadcrumbs, and keyboard shortcuts.

```text
+-- pgstack -----------------------------------------------------------+
| Host           db.yourdomain.com                                     |
| Admin          blockway                                              |
| Status         ONLINE                                                |
+----------------------------------------------------------------------+
  > Main

+-- System ------------------------------------------------------------+
| PostgreSQL     ONLINE                                                |
| Version        PG 16.14                                              |
| Uptime         00:40:24                                              |
| Databases      2 project: myapp, test                                 |
| Backups        3 files (12M)                                         |
| Latest         2026-06-18 14:30:00                                   |
| Docker         postgres: running                                     |
| Backup dir     data/backups/                                         |
| Logs dir       data/logs/postgres/                                   |
+----------------------------------------------------------------------+

+-- Menu --------------------------------------------------------------+
|   1) Overview           status, stats, logs                          |
|   2) Databases          create, list, drop                           |
|  ...                                                                 |
+----------------------------------------------------------------------+
```

| Key | Action |
|-----|--------|
| `1`–`5` | Open section |
| `0` | Exit (main) or Back (submenu) |
| `h` | Jump to main menu from any screen |
| `?` | Show shortcuts and paths |
| `q` | Quit (main) or Home (submenu) |

After running an action: `[Enter]` continues, `[h]` returns to main menu.

Layout uses a fixed **72-column** width. Override with `PGSTACK_UI_WIDTH=80 ./bin/manager.sh` if your terminal is wider.

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

## The whole model: just databases

Everything uses the default **`public`** schema. There is no "app" abstraction,
no registry, and no manifest. The flow is:

```text
create db  →  add user  →  backup  →  drop  →  restore  →  add user again
```

- **Create** an empty database (`public` schema).
- **Add a user** when you need one (e.g. the Django user) — owner / read / write / admin.
- **Backup** produces a portable `.sql.gz` (`pg_dump --no-owner --no-acl`).
- **Restore** drops and recreates the database, then loads the dump 100%.
  It needs **no password, no manifest, no registry** — copy a `.sql.gz` from
  another server and restore it directly.
- After a restore, **add the app user again** (users are not part of backups).

## Create a project database

Creates **only the database** (schema `public`). Users are added separately.

```bash
./scripts/databases/create-db.sh myapp
```

**Add a user** (owner is what an app like Django needs):

```bash
./scripts/users/add-user.sh myapp owner myapp_app
./scripts/users/add-user.sh myapp read analytics
./scripts/users/add-user.sh myapp write worker
./scripts/users/add-user.sh myapp admin myapp_admin
```

| Access | What it can do |
|--------|----------------|
| `owner` | Read, write, delete, create tables, run migrations (main app) |
| `read` | Read only |
| `write` | Read + write on tables |
| `admin` | Create read/write users for this DB |

## Application connection

Use the **owner** user you created — not the server admin:

```text
postgresql://myapp_app:PASSWORD@db.yourdomain.com:5432/myapp
```

The app connects to the default `public` schema; no `search_path` is needed.

## Logs (persistent files)

PostgreSQL saves daily log files to `data/logs/postgres/`:

```bash
ls data/logs/postgres/
tail -f data/logs/postgres/postgresql-$(date +%Y-%m-%d).log
```

The `data/` folder is created on first `docker compose up` (or run `mkdir -p` above).

Logged events: schema changes (DDL) and slow queries (> 500 ms).

## Persistent data folder

```text
data/
├── postgres/          # PostgreSQL database files (bind mount)
├── backups/           # .sql.gz backups
└── logs/postgres/     # daily log files
```

Copy the whole `data/` folder to migrate servers or for off-site backup.

## Backup & restore (summary)

| Task | Command |
|------|---------|
| Backup one database | `./scripts/backups/backup.sh myapp` |
| Backup all databases | `./scripts/backups/backup.sh` |
| List backup files | `./scripts/backups/list-backups.sh` |
| Restore a backup | `./scripts/backups/restore.sh data/backups/backup_myapp_DATE.sql.gz myapp` |
| Health check | `./scripts/overview/status.sh` |

See **[docs/SCRIPTS.md](docs/SCRIPTS.md)** for what each script does.  
See **[docs/BACKUP.md](docs/BACKUP.md)** for the full backup/restore walkthrough.

## Important: after a restore, recreate the app user

A backup contains **only the database data — not the users/roles**. Restore drops
and recreates the database, so the previous app user (e.g. the Django user) loses
its ownership/privileges and the app will fail with errors like
`permission denied for table ...` or `password authentication failed`.

**Always recreate the app user right after restoring:**

```bash
# 1. Restore the data
./scripts/backups/restore.sh data/backups/backup_myapp_DATE.sql.gz myapp

# 2. Recreate the app user as owner (use the EXACT password from your app's DATABASE_URL)
PGSTACK_PASSWORD='your-app-password' \
  ./scripts/users/add-user.sh myapp owner myapp_app

# 3. Restart the app so it reconnects
```

Using `owner` is what makes it work: it takes ownership of all restored tables and
sequences, so the app can read, write, and run migrations without
`permission denied`. In the Manager UI, this is **Users → Add user → owner**.

> Tip: the password must match the one in your app's `DATABASE_URL`. If you ever
> see `password authentication failed`, just re-run step 2 (or
> `./scripts/users/set-password.sh myapp_app`) with the correct password.

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

`POSTGRES_USER` and `POSTGRES_PASSWORD` are applied **only on first boot** (empty `data/postgres/`). Changing `.env` later does not rename the admin user.

**Fresh install (no data to keep):**

```bash
docker compose down
rm -rf ./data/postgres
docker compose up -d
./scripts/overview/status.sh

# Create the database, then the app user
./scripts/databases/create-db.sh myapp
PGSTACK_PASSWORD='your-app-password' \
  ./scripts/users/add-user.sh myapp owner myapp_api

# Diagnose remote-style login if needed
PGSTACK_PASSWORD='your-app-password' \
  ./scripts/tools/diagnose-user.sh myapp_api myapp
```

> After wiping `data/postgres/`, **all roles and databases are gone**. The database and app user (`myapp_api`) must be recreated. `POSTGRES_USER` in `.env` is only the server admin, not your application user.

**Migrate from old Docker volume** (`pgstack-prod_pgdata`):

```bash
docker compose down
mkdir -p data/postgres
docker run --rm -v pgstack-prod_pgdata:/from -v "$(pwd)/data/postgres:/to" alpine \
  sh -c 'cp -a /from/. /to/'
# Update .env: DATA_DIR=./data, BACKUP_DIR=./data/backups, LOG_DIR=./data/logs/postgres
docker compose up -d
```

**Already has databases:** put the **original** `POSTGRES_USER` back in `.env` (the one used on first `docker compose up`), then restart:

```bash
docker compose restart postgres
```

---

| Feature | Implementation |
|---------|----------------|
| Persistent data | `data/postgres/` (bind mount) |
| Persistent logs | `data/logs/postgres/postgresql-YYYY-MM-DD.log` |
| Backups | `data/backups/` |
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
| `DATA_DIR` | Root for all persistent files (default `./data`) — postgres, backups, logs |

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
│   └── ui.sh                   # manager TUI helpers
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
├── data/                       # all persistent files (see data/README.md)
│   ├── postgres/
│   ├── backups/
│   └── logs/postgres/
└── postgres/
    ├── entrypoint-wrapper.sh
    ├── conf/postgresql.conf
    └── init/01-extensions.sql
```
