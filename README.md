# pgstack-prod

Production-ready PostgreSQL 16 stack with PgBouncer, pgAdmin, and automated backups — Docker Compose template for self-hosted deployments.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue.svg)](https://www.postgresql.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED.svg)](https://docs.docker.com/compose/)

## Overview

pgstack-prod is a self-hosted PostgreSQL 16 deployment template built on Docker Compose. It bundles connection pooling (PgBouncer), a web-based admin UI (pgAdmin), and scheduled backups into a single stack designed for production VPS deployments.

The stack isolates the database on an internal Docker network with no direct internet exposure, routes admin access through Traefik with TLS and IP whitelisting, and persists all data in named Docker volumes that survive container restarts and host reboots.

Intended for experienced developers and DevOps engineers who need a reliable, maintainable PostgreSQL foundation without managed cloud database services.

## Architecture

```
┌─────────────────┬──────────────────────────────────────┬─────────────────────────────┐
│ Service         │ Image                                │ Network / Exposure          │
├─────────────────┼──────────────────────────────────────┼─────────────────────────────┤
│ postgres        │ postgres:16-alpine                   │ db_internal only — no ports │
│ pgbouncer       │ bitnami/pgbouncer:latest             │ 127.0.0.1:5432 (loopback)   │
│ pgadmin         │ dpage/pgadmin4:latest                │ Traefik HTTPS + IP whitelist│
│ postgres-backup │ prodrigestivill/postgres-backup-local│ db_internal only — no ports │
│                 │ :16-alpine                           │                             │
└─────────────────┴──────────────────────────────────────┴─────────────────────────────┘
```

Traffic flow:

- Application containers connect to `pgbouncer:5432` on the `db_internal` network.
- Local processes on the VPS connect via `localhost:5432` (loopback-bound PgBouncer).
- pgAdmin is reachable only at `https://<PGADMIN_DOMAIN>` through Traefik, restricted by IP whitelist.
- PostgreSQL itself is never exposed outside `db_internal`.

## Prerequisites

- Docker 24+ and Docker Compose v2 (`docker compose`)
- Traefik running on the host with:
  - An external Docker network named `traefik_proxy`
  - A `websecure` entrypoint with TLS
  - A `letsencrypt` certificate resolver
- A DNS A record pointing `PGADMIN_DOMAIN` to the server IP

## Quick Start

1. Clone the repository:

   ```bash
   git clone https://github.com/your-org/pgstack-prod.git
   cd pgstack-prod
   ```

2. Create your environment file:

   ```bash
   cp .env.example .env
   ```

3. Edit `.env` — set strong passwords, your pgAdmin email/domain, and your allowed IP(s):

   ```bash
   nano .env
   ```

4. Deploy:

   ```bash
   ./deploy.sh up
   ```

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `POSTGRES_USER` | PostgreSQL application user | `appuser` |
| `POSTGRES_PASSWORD` | PostgreSQL password | `CHANGE_ME_STRONG_PASSWORD` |
| `POSTGRES_DB` | Default database name | `appdb` |
| `PGADMIN_EMAIL` | pgAdmin login email | `admin@yourdomain.com` |
| `PGADMIN_PASSWORD` | pgAdmin login password | `CHANGE_ME_STRONG_PASSWORD` |
| `PGADMIN_DOMAIN` | Hostname for pgAdmin via Traefik | `db.yourdomain.com` |
| `PGADMIN_ALLOWED_IPS` | Comma-separated CIDRs for pgAdmin access | `203.0.113.10/32` |

## Connection Strings

Replace `PASSWORD` with your `POSTGRES_PASSWORD` value:

```text
# From another Docker container on db_internal network (via PgBouncer):
postgresql://appuser:PASSWORD@pgbouncer:5432/appdb

# From the VPS host itself (loopback):
postgresql://appuser:PASSWORD@localhost:5432/appdb
```

## Data Persistence

All PostgreSQL data is stored in the **`pgdata`** named Docker volume (`driver: local`). This volume is mounted at `/var/lib/postgresql/data/pgdata` inside the container.

Data persists across:

- Container restarts (`docker compose restart`)
- Container recreation (`docker compose up -d`)
- Stack shutdown (`docker compose down`)
- Host reboots

Automated backup dumps are stored in the separate **`pgbackups`** named volume.

**Never run `docker compose down -v` in production.** The `-v` flag removes named volumes and permanently destroys all database data.

To inspect the volume location on the host:

```bash
docker volume inspect pgstack-prod_pgdata
```

The `Mountpoint` field shows where Docker stores the data files.

## Tuning for Your Server

The default `postgres/conf.d/postgresql.conf` is tuned for a VPS with 2–4 GB RAM. Adjust `shared_buffers` and `effective_cache_size` proportionally for your server:

| Total RAM | shared_buffers (~25%) | effective_cache_size (~75%) |
|-----------|----------------------|----------------------------|
| 1 GB | 256MB | 768MB |
| 2 GB | 512MB | 1536MB |
| 4 GB | 1GB | 3GB |
| 8 GB | 2GB | 6GB |

After editing `postgresql.conf`, restart PostgreSQL:

```bash
./deploy.sh restart
```

## Backup & Restore

### Automated Backups

The `postgres-backup` service runs `pg_dump` on a daily schedule (`@daily`) and stores compressed dumps in the `pgbackups` volume.

Retention policy:

- Daily backups: 7 days
- Weekly backups: 4 weeks
- Monthly backups: 6 months

### Manual Backup

```bash
./deploy.sh backup
```

Creates `backup_manual_YYYYMMDD_HHMMSS.sql.gz` in the project directory.

### Restore

```bash
./deploy.sh restore backup_manual_20260101_120000.sql.gz
```

Prompts for confirmation before overwriting the target database.

## deploy.sh Reference

| Command | Description |
|---------|-------------|
| `up` | Validate `.env`, ensure Traefik network exists, start stack |
| `down` | Stop stack (volumes preserved) |
| `restart` | Restart all services |
| `status` | Show service status and volumes |
| `logs [service]` | Tail logs (all services or one) |
| `shell` | Open `psql` as `POSTGRES_USER` |
| `backup` | Manual `pg_dump` to gzip file |
| `restore <file>` | Restore from a `.sql.gz` file |
| `help` | Show usage |

## Traefik Integration

This stack assumes Traefik is already running on the host and connected to an external Docker network named **`traefik_proxy`**. The `deploy.sh up` command creates this network if it does not exist.

pgAdmin is exposed through Traefik with:

- HTTPS via the `websecure` entrypoint
- TLS certificates from the `letsencrypt` certresolver
- IP whitelist middleware (`pgadmin-ipwhitelist`) restricting access to `PGADMIN_ALLOWED_IPS`

If your Traefik instance uses a different network name, update the `traefik_proxy` network definition in `docker-compose.yml`:

```yaml
networks:
  traefik_proxy:
    external: true
    name: your-traefik-network-name
```

## Security Notes

- All credentials are stored in `.env` only — never committed to version control
- PostgreSQL has zero port mappings — not reachable from the host or internet
- PgBouncer binds to `127.0.0.1:5432` only — loopback access, not `0.0.0.0`
- pgAdmin is IP-restricted via Traefik middleware — configure `PGADMIN_ALLOWED_IPS` carefully
- TLS terminates at Traefik — PostgreSQL runs without SSL inside the internal network
- Password authentication uses `scram-sha-256`
- The `public` schema is locked down on init — application objects live in the `app` schema

## License

MIT — see [LICENSE](LICENSE).
