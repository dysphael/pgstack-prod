# Backup & Restore Guide

A step-by-step guide for beginners. No prior database experience required.

---

## What is a backup?

A **backup** is a copy of your database saved to a file. If something goes wrong (server crash, accidental deletion, bad update), you can **restore** the backup and get your data back.

Backups are stored in the `backups/` folder as `.sql.gz` files (compressed text files).

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
- Saves a compressed file like: `backups/backup_myapp_20260115_030000.sql.gz`

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
backups/backup_myapp_20260115_030000.sql.gz   2.4M
```

---

## How to restore a backup

**Warning:** restoring **replaces** the current data in that database. Always make a fresh backup before restoring if you are unsure.

### Step 1 — find your backup file

```bash
./scripts/backups/list-backups.sh
```

Copy the full filename, for example:

```text
backups/backup_myapp_20260115_030000.sql.gz
```

### Step 2 — run the restore

```bash
./scripts/backups/restore.sh backups/backup_myapp_20260115_030000.sql.gz myapp
```

Replace:
- the filename with your real backup file
- `myapp` with your real database name

### Step 3 — confirm

The script will ask:

```text
Type YES to continue:
```

Type exactly `YES` and press Enter.

### Step 4 — verify

```bash
docker compose exec postgres psql -U appuser -d myapp -c "\dt"
```

This lists tables in the database. If you see your tables, the restore worked.

---

## Automatic daily backup (cron)

Run backups every day at 3:00 AM server time.

### Step 1 — open the cron editor

```bash
crontab -e
```

### Step 2 — add this line at the bottom

```cron
0 3 * * * cd /root/pgstack-prod && ./scripts/backups/backup.sh >> ./logs/backup.log 2>&1
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
| `>> ./logs/backup.log` | Save output to a log file |

---

## Copy backups off the server (recommended)

Backups on the same server as the database are not enough if the server dies. Copy files to your computer or cloud storage regularly.

### Download to your Mac/PC (from your local machine)

```bash
scp root@YOUR_SERVER_IP:~/pgstack-prod/backups/backup_myapp_*.sql.gz ./Downloads/
```

Replace `YOUR_SERVER_IP` with your VPS IP address.

---

## Persistent logs

PostgreSQL writes daily log files to:

```text
logs/postgres/postgresql-YYYY-MM-DD.log
```

### View today's log

```bash
ls -la logs/postgres/
tail -f logs/postgres/postgresql-$(date +%Y-%m-%d).log
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

These are separate from the files in `logs/postgres/` and rotate automatically.

---

## Common problems

### "ERROR: .env file not found"

```bash
cp .env.example .env
nano .env
```

### "database does not exist" when backing up

Create the database first (with isolated users):

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
| Backup one DB | `./scripts/backups/backup.sh myapp` |
| Backup all DBs | `./scripts/backups/backup.sh` |
| List backups | `./scripts/backups/list-backups.sh` |
| Restore | `./scripts/backups/restore.sh backups/FILE.sql.gz myapp` |
| View log files | `tail -f logs/postgres/postgresql-$(date +%Y-%m-%d).log` |
| List tables | `docker compose exec postgres psql -U appuser -d myapp -c "\dt"` |

---

## Important rules

1. **Never** run `docker compose down -v` — it deletes all database data.
2. Always test a restore on a **copy** of the database before relying on a backup in an emergency.
3. Keep backups **outside** the server (download or sync to cloud).
4. Make a backup **before** any major change (migration, update, manual SQL).
