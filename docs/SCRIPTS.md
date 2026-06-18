# Scripts Guide

Quick reference for every script in `scripts/`.

Run all commands from the project root (`~/pgstack-prod`).

No separate setup step is required — `docker compose up -d` creates folders and fixes permissions automatically.

---

## Order of use (first deploy)

```bash
cp .env.example .env
nano .env
docker compose up -d
./scripts/manager.sh             # interactive manager (recommended)
```

Or run scripts directly:

```bash
./scripts/status.sh              # confirm it is healthy
./scripts/create-db.sh myapp     # create your first project database (optional)
./scripts/backup.sh myapp        # first backup (recommended)
```

---

## `manager.sh`

**What it does:** Interactive menu to manage the whole stack while PostgreSQL is running.

| Option | Action |
|--------|--------|
| 1 | Status / health |
| 2 | List project databases |
| 3 | List users and access |
| 4 | Create project database (owner + read + admin) |
| 5 | Add read/write user |
| 6 | Backup one database |
| 7 | Backup all databases |
| 8 | List backups (full path, size, date) |
| 9 | Restore backup (guided) |
| 10 | Open psql shell |
| 0 | Exit |

**When to use:** Day-to-day operations on the server — preferred entry point.

```bash
./scripts/manager.sh
```

Shows host, admin user, backup folder, and log folder in the header.

---

## `status.sh`

**What it does:** Quick health check.

- Shows if the container is running
- Checks if PostgreSQL accepts connections
- Lists databases
- Shows log and backup folder paths

**When to use:** After deploy, after restart, or when something feels wrong.

```bash
./scripts/status.sh
```

---

## `create-db.sh`

**What it does:** Creates an isolated project database with **3 users**:

| User | Role |
|------|------|
| `myapp_owner` | Read, write, delete, create tables (main app) |
| `myapp_read` | Read only — all data in schema `app` |
| `myapp_admin` | Create read/write users for `myapp` only |

Each user can connect **only** to `myapp`.

```bash
./scripts/create-db.sh myapp
```

**App connection (owner):**

```text
postgresql://myapp_owner:PASSWORD@db.yourdomain.com:5432/myapp
```

**Read-only connection:**

```text
postgresql://myapp_read:PASSWORD@db.yourdomain.com:5432/myapp
```

---

## `add-user.sh`

**What it does:** Adds a read-only or read-write user to an existing project.

```bash
./scripts/add-user.sh myapp read analytics
./scripts/add-user.sh myapp write worker
```

**DB admin** (`myapp_admin`) can also create users via SQL:

```sql
SELECT app.provision_user('analytics', 'read',  'password');
SELECT app.provision_user('worker',    'write', 'password');
```

---

## `list-access.sh`

**What it does:** Shows users per database and detects cross-database access.

```bash
./scripts/list-access.sh
./scripts/list-access.sh myapp
```

Each project user should connect to **one database only**.

---

## `backup.sh`

**What it does:** Saves a compressed copy of your database (`.sql.gz`).

| Command | Result |
|---------|--------|
| `./scripts/backup.sh` | Backs up all project databases |
| `./scripts/backup.sh myapp` | Backs up only `myapp` |
| `./scripts/backup.sh --list` | Lists existing backup files |

**When to use:** Before updates, daily (cron), or before any risky change.

```bash
./scripts/backup.sh myapp
./scripts/backup.sh --list
```

Files are saved in `backups/`:

```text
backups/backup_myapp_20260115_030000.sql.gz
```

> Full beginner guide: [BACKUP.md](BACKUP.md)

---

## `restore.sh`

**What it does:** Loads a backup file back into a database.

**Warning:** Replaces existing data in the target database.

```bash
./scripts/restore.sh backups/backup_myapp_20260115_030000.sql.gz myapp
```

Steps:
1. Shows the file and target database
2. Asks you to type `YES` to confirm
3. Creates the database if it does not exist
4. Restores the data

**When to use:** Disaster recovery, or copying data to a fresh database.

---

## `_common.sh`

**What it does:** Internal helper used by the other scripts.

You do **not** run this directly. It handles:

- Loading `.env`
- Checking if PostgreSQL is running
- Validating database names

---

## Cheat sheet

| I want to… | Command |
|------------|---------|
| Manage everything (menu) | `./scripts/manager.sh` |
| Start everything | `docker compose up -d` |
| Check if DB is OK | `./scripts/status.sh` |
| Create project DB (owner + read + admin) | `./scripts/create-db.sh myapp` |
| Add read/write user | `./scripts/add-user.sh myapp read USER` |
| Verify user isolation | `./scripts/list-access.sh` |
| Backup one database | `./scripts/backup.sh myapp` |
| Backup everything | `./scripts/backup.sh` |
| See backup files | `./scripts/backup.sh --list` |
| Restore a backup | `./scripts/restore.sh backups/FILE.sql.gz myapp` |
| Open SQL shell | `docker compose exec postgres psql -U appuser -d postgres` |

---

## Common errors

| Error | Fix |
|-------|-----|
| `.env file not found` | `cp .env.example .env && nano .env` |
| `PostgreSQL is not running` | `docker compose up -d` |
| `backup file is empty` | Check `docker compose logs postgres` |
