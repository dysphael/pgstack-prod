# pgstack-prod

Production PostgreSQL 16 with persistent storage and DNS-based access for applications.

> **Scripts:** Quick guide → **[docs/SCRIPTS.md](docs/SCRIPTS.md)**  
> **Backups (beginner):** Full guide → **[docs/BACKUP.md](docs/BACKUP.md)**

## Quick start

```bash
cp .env.example .env
nano .env                    # set POSTGRES_PASSWORD and POSTGRES_HOST
docker compose up -d         # creates folders and starts PostgreSQL
./scripts/manager.sh         # interactive manager (recommended)
```

Or run individual scripts:

```bash
./scripts/status.sh          # verify everything is healthy
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

Each project gets **one database** and **three users**:

| User | Access | Use in apps? |
|------|--------|--------------|
| `appuser` (`.env`) | Server admin — backups, scripts | **No** |
| `myapp_owner` | Read, write, delete, create tables | **Yes** (main app) |
| `myapp_read` | Read only — all tables in `app` | **Yes** (reports, BI) |
| `myapp_admin` | Create read/write users for `myapp` only | **No** (management) |

```bash
./scripts/create-db.sh myapp
```

Creates `myapp` plus `myapp_owner`, `myapp_read`, and `myapp_admin` (you set each password).

**Main app connection:**

```text
postgresql://myapp_owner:PASSWORD@db.yourdomain.com:5432/myapp
```

**Read-only connection:**

```text
postgresql://myapp_read:PASSWORD@db.yourdomain.com:5432/myapp
```

**Add more users later:**

```bash
./scripts/add-user.sh myapp read analytics
./scripts/add-user.sh myapp write worker
```

**Or let the DB admin create users** (logged in as `myapp_admin`):

```sql
SELECT app.provision_user('analytics', 'read',  'password');
SELECT app.provision_user('worker',    'write', 'password');
```

Verify isolation:

```bash
./scripts/list-access.sh
./scripts/list-access.sh myapp
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
| Backup one database | `./scripts/backup.sh myapp` |
| Backup all databases | `./scripts/backup.sh` |
| List backup files | `./scripts/backup.sh --list` |
| Restore a backup | `./scripts/restore.sh backups/backup_myapp_DATE.sql.gz myapp` |
| Health check | `./scripts/status.sh` |

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
| Per-project users | `./scripts/create-db.sh myapp` — owner + read + admin per DB |
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
./scripts/manager.sh         # interactive menu for all tasks
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
├── docs/
│   ├── SCRIPTS.md              # quick guide for every script
│   └── BACKUP.md               # beginner backup/restore guide
├── logs/postgres/              # persistent PostgreSQL log files
├── backups/                    # backup .sql.gz files
├── postgres/
│   ├── entrypoint-wrapper.sh
│   ├── conf/postgresql.conf
│   └── init/01-extensions.sql
└── scripts/
    ├── manager.sh              # interactive menu (start here)
    ├── status.sh               # health check
    ├── create-db.sh            # owner + read + admin per project
    ├── add-user.sh             # add read/write user to a project
    ├── list-access.sh          # verify user isolation
    ├── backup.sh
    └── restore.sh
```
