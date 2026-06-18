# Scripts Guide

Quick reference for `bin/`, `lib/`, and `scripts/`.

Run all commands from the project root (`~/pgstack-prod`).

## Project layout

```text
pgstack-prod/
├── manager.sh              # shortcut → bin/manager.sh
├── bin/
│   └── manager.sh          # interactive menu
├── lib/                    # internal helpers (do not run directly)
│   ├── init.sh
│   ├── common.sh
│   ├── db-users.sh
│   └── backups.sh
└── scripts/
    ├── overview/           # monitoring & logs
    ├── databases/          # create, list, drop
    ├── users/              # roles & access
    ├── backups/            # backup & restore
    └── tools/              # psql shell
```

## Entry point

```bash
./bin/manager.sh    # or ./manager.sh
```

Interactive menu with 5 sections. Every option calls a CLI script below.

## CLI scripts

| Script | Usage |
|--------|-------|
| **Overview** | |
| `scripts/overview/status.sh` | `./scripts/overview/status.sh` |
| `scripts/overview/db-stats.sh` | `./scripts/overview/db-stats.sh [db]` |
| `scripts/overview/connections.sh` | `./scripts/overview/connections.sh [db]` |
| `scripts/overview/db-tables.sh` | `./scripts/overview/db-tables.sh <db>` |
| `scripts/overview/slow-queries.sh` | `./scripts/overview/slow-queries.sh [limit]` |
| `scripts/overview/logs.sh` | `./scripts/overview/logs.sh [--tail N\|--list]` |
| **Databases** | |
| `scripts/databases/list-dbs.sh` | `./scripts/databases/list-dbs.sh` |
| `scripts/databases/create-db.sh` | `./scripts/databases/create-db.sh <db>` |
| `scripts/databases/drop-db.sh` | `./scripts/databases/drop-db.sh <db>` |
| `scripts/databases/conn-info.sh` | `./scripts/databases/conn-info.sh <db>` |
| **Users** | |
| `scripts/users/list-access.sh` | `./scripts/users/list-access.sh [db]` |
| `scripts/users/add-user.sh` | `./scripts/users/add-user.sh <db> <owner\|read\|write\|admin> <user>` |
| `scripts/users/reset-password.sh` | `./scripts/users/reset-password.sh <user>` |
| `scripts/users/drop-user.sh` | `./scripts/users/drop-user.sh <user>` |
| **Backups** | |
| `scripts/backups/backup.sh` | `./scripts/backups/backup.sh [db]` |
| `scripts/backups/list-backups.sh` | `./scripts/backups/list-backups.sh [--path N]` |
| `scripts/backups/restore.sh` | `./scripts/backups/restore.sh <file> <db>` |
| **Tools** | |
| `scripts/tools/psql.sh` | `./scripts/tools/psql.sh [db]` |

`backup.sh --list` delegates to `list-backups.sh`.

---

## First deploy

```bash
cp .env.example .env
nano .env
docker compose up -d
./bin/manager.sh
```

Or run scripts directly:

```bash
./scripts/overview/status.sh
./scripts/databases/create-db.sh myapp
./scripts/backups/backup.sh myapp
```

---

## Manager sections

| Section | Actions |
|---------|---------|
| Overview | Status, stats, connections, table sizes, slow queries, logs |
| Databases | List, create, drop, connection strings |
| Users | List access, add, reset password, drop |
| Backups | Backup one/all, list, restore |
| Tools | psql shell |

---

## `create-db.sh`

Creates database + schema `app`. **Users are optional** — you choose each one interactively.

```bash
./scripts/databases/create-db.sh myapp
```

1. Creates `myapp`
2. **Add a user? (y/n)** — for each user: access → username → password

| Access | Role |
|--------|------|
| `owner` | Read, write, delete, create tables |
| `read` | Read only |
| `write` | Read + write on tables |
| `admin` | Create read/write users for this DB |

Add users later with `add-user.sh`.

---

## Backups

```bash
./scripts/backups/backup.sh myapp
./scripts/backups/backup.sh
./scripts/backups/list-backups.sh
./scripts/backups/restore.sh backups/backup_myapp_DATE.sql.gz myapp
```

> Full guide: [BACKUP.md](BACKUP.md)

---

## Cheat sheet

| I want to… | Command |
|------------|---------|
| Interactive menu | `./bin/manager.sh` |
| Start stack | `docker compose up -d` |
| Health check | `./scripts/overview/status.sh` |
| Database stats | `./scripts/overview/db-stats.sh` |
| Active connections | `./scripts/overview/connections.sh` |
| Table sizes | `./scripts/overview/db-tables.sh myapp` |
| View logs | `./scripts/overview/logs.sh --tail 50` |
| List databases | `./scripts/databases/list-dbs.sh` |
| Create project DB | `./scripts/databases/create-db.sh myapp` |
| Connection strings | `./scripts/databases/conn-info.sh myapp` |
| List users | `./scripts/users/list-access.sh` |
| Add user | `./scripts/users/add-user.sh myapp owner USER` |
| Reset password | `./scripts/users/reset-password.sh USER` |
| Backup | `./scripts/backups/backup.sh myapp` |
| List backups | `./scripts/backups/list-backups.sh` |
| Restore | `./scripts/backups/restore.sh FILE myapp` |
| SQL shell | `./scripts/tools/psql.sh` |

---

## Common errors

| Error | Fix |
|-------|-----|
| `.env file not found` | `cp .env.example .env && nano .env` |
| `PostgreSQL is not running` | `docker compose up -d` |
| `role "X" does not exist` | `POSTGRES_USER` changed after first boot — see README Troubleshooting |
| `backup file is empty` | Check `docker compose logs postgres` |
