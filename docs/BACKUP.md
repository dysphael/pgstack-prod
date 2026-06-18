# Backup & Restore Guide

> **Plug-and-play (recomendado):** use o [RUNBOOK.md](RUNBOOK.md) — menu **Backups** no Manager.

A step-by-step guide for beginners. No prior database experience required.

Backups are **portable**: a `.sql.gz` is created with `pg_dump --no-owner --no-acl`,
so you can copy it to another server and restore it directly. Restore drops and
recreates the database and loads the dump 100% — **no password, manifest, or
registry needed**. Users are not part of a backup; recreate the app user after a
restore (see step 4).

---

## What is a backup?

A **backup** is a copy of your database saved to a file. If something goes wrong (server crash, accidental deletion, bad update), you can **restore** the backup and get your data back.

Backups are stored in `data/backups/` as `.sql.gz` files (compressed text files).

---

## Before you start

1. You must be logged into your server (SSH).
2. Go to the project folder:

```bash
cd ~/pgstack-prod
```

3. Start PostgreSQL:

```bash
docker compose up -d
```

4. Make sure PostgreSQL is running:

```bash
./scripts/overview/status.sh
```

You should see `PostgreSQL: ready`.

---

## How to create a backup (manual)

### Backup one database

Replace `myapp` with your real database name:

```bash
./scripts/backups/backup.sh myapp
```

**What happens:**
- The script connects to PostgreSQL inside Docker
- Exports all tables and data from `myapp`
- Saves a compressed file like: `data/backups/backup_myapp_20260115_030000.sql.gz`

### Backup all project databases

```bash
./scripts/backups/backup.sh
```

### List existing backups

```bash
./scripts/backups/list-backups.sh
```

Example output:

```text
data/backups/backup_myapp_20260115_030000.sql.gz   2.4M
```

---

## How to restore a backup

**Warning:** restoring **drops and recreates** the database — all current data in it is replaced. Always make a fresh backup before restoring if you are unsure.

Restore needs **no password, manifest, or registry**. It works with any `.sql.gz`, including a file copied from another server.

### Step 1 — find your backup file

```bash
./scripts/backups/list-backups.sh
```

Copy the full filename, for example:

```text
data/backups/backup_myapp_20260115_030000.sql.gz
```

### Step 2 — run the restore

```bash
./scripts/backups/restore.sh data/backups/backup_myapp_20260115_030000.sql.gz myapp
```

The database name is optional — it's inferred from the filename. Replace `myapp`
with your real database name if you pass it explicitly.

Or use the guided wizard: **Manager → Backups → Restore**.

### Step 3 — confirm

The script will ask:

```text
Type YES to continue:
```

Type exactly `YES` and press Enter. (Set `PGSTACK_YES=1` to skip the prompt in scripts.)

The script then drops the database, recreates it, and loads the dump 100%.

### Step 4 — recreate the app user

Users are not part of the backup. Recreate the app user (use the exact password
from your app `DATABASE_URL`):

```bash
PGSTACK_PASSWORD='your-app-password' ./scripts/users/add-user.sh myapp owner myapp_api
```

Then point your app at that user and restart it. Verify login if needed:

```bash
PGSTACK_PASSWORD='your-app-password' ./scripts/tools/diagnose-user.sh myapp_api myapp
```

---

## Automatic daily backup (cron)

Run backups every day at 3:00 AM server time.

### Step 1 — open the cron editor

```bash
crontab -e
```

### Step 2 — add this line at the bottom

```cron
0 3 * * * cd /root/pgstack-prod && ./scripts/backups/backup.sh >> ./data/logs/backup.log 2>&1
```

**Change `/root/pgstack-prod`** if your project is in a different folder.

### Step 3 — save and exit

- nano: `Ctrl+O`, Enter, `Ctrl+X`
- vim: `:wq`

### Step 4 — check it was saved

```bash
crontab -l
```

### What the cron line means

| Part | Meaning |
|------|---------|
| `0 3 * * *` | Every day at 03:00 |
| `cd /root/pgstack-prod` | Go to project folder |
| `./scripts/backups/backup.sh` | Run backup |
| `>> ./data/logs/backup.log` | Save output to a log file |

---

## Copy backups off the server (recommended)

Backups on the same server as the database are not enough if the server dies. Copy files to your computer or cloud storage regularly.

### Download to your Mac/PC (from your local machine)

```bash
scp root@YOUR_SERVER_IP:~/pgstack-prod/data/backups/backup_myapp_*.sql.gz ./Downloads/
```

Replace `YOUR_SERVER_IP` with your VPS IP address.

---

## Persistent logs

PostgreSQL writes daily log files to:

```text
data/logs/postgres/postgresql-YYYY-MM-DD.log
```

### View today's log

```bash
ls -la data/logs/postgres/
tail -f data/logs/postgres/postgresql-$(date +%Y-%m-%d).log
```

### What is logged

| Event | Logged? |
|-------|---------|
| Connections / disconnections | Yes |
| Schema changes (CREATE TABLE, etc.) | Yes |
| Slow queries (> 500 ms) | Yes |
| Every single SELECT | No (too noisy) |

### Docker logs (alternative)

```bash
docker compose logs -f postgres
```

These are separate from the files in `data/logs/postgres/` and rotate automatically.

---

## Common problems

### "ERROR: .env file not found"

```bash
cp .env.example .env
nano .env
```

### "database does not exist" when backing up

Create the database first:

```bash
./scripts/databases/create-db.sh myapp
```

### Restore says file not found

Run `./scripts/backups/list-backups.sh` and copy the exact filename.

### Backup file is very small (e.g. 20 bytes)

The database might be empty or the backup failed. Check:

```bash
docker compose logs postgres
```

---

## Quick reference

| Task | Command |
|------|---------|
| Create DB | `./scripts/databases/create-db.sh myapp` |
| Add app user | `PGSTACK_PASSWORD='...' ./scripts/users/add-user.sh myapp owner myapp_api` |
| Backup one DB | `./scripts/backups/backup.sh myapp` |
| Backup all DBs | `./scripts/backups/backup.sh` |
| List backups | `./scripts/backups/list-backups.sh` |
| Restore | `./scripts/backups/restore.sh data/backups/FILE.sql.gz myapp` |
| Drop DB | `./scripts/databases/drop-db.sh myapp` |
| Diagnose user | `PGSTACK_PASSWORD='...' ./scripts/tools/diagnose-user.sh myapp_api myapp` |

---

## Important rules

1. **Never** run `docker compose down -v` — it deletes all database data.
2. Always test a restore on a **copy** of the database before relying on a backup in an emergency.
3. Keep backups **outside** the server (download or sync to cloud).
4. Make a backup **before** any major change (migration, update, manual SQL).
