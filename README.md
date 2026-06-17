# pgstack-prod

Production-ready PostgreSQL 16 stack with PgBouncer, pgAdmin, Netdata monitoring, and automated backups — Docker Compose template for self-hosted deployments.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue.svg)](https://www.postgresql.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED.svg)](https://docs.docker.com/compose/)

## Overview

pgstack-prod is a self-hosted PostgreSQL 16 deployment template built on Docker Compose. It bundles connection pooling (PgBouncer), a web-based admin UI (pgAdmin), scheduled backups, and full observability via Netdata into a single stack designed for production VPS deployments.

The stack isolates the database on an internal Docker network with no direct internet exposure, routes admin and monitoring access through Traefik with TLS and IP whitelisting, and persists all data in named Docker volumes that survive container restarts and host reboots.

Netdata provides a secured web dashboard covering host CPU/RAM/disk/network, per-container Docker metrics, and optional deep PostgreSQL monitoring (connections, query throughput, locks, WAL, autovacuum, checkpoints).

Intended for experienced developers and DevOps engineers who need a reliable, maintainable, and observable PostgreSQL foundation without managed cloud database services.

## Architecture

```
┌─────────────────┬──────────────────────────────────────┬──────────────────────────────────────┐
│ Service         │ Image                                │ Network / Exposure                   │
├─────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
│ postgres        │ postgres:16-alpine                   │ db_internal + monitor_internal       │
│                 │                                      │ no ports                             │
│ pgbouncer       │ neondatabase/pgbouncer (Bitnami fork)│ 127.0.0.1:5432 (loopback)            │
│ pgadmin         │ dpage/pgadmin4:latest                │ Traefik HTTPS + IP whitelist         │
│ postgres-backup │ prodrigestivill/postgres-backup-local│ db_internal only — no ports          │
│                 │ :16-alpine                           │                                      │
│ netdata         │ netdata/netdata:stable               │ Traefik HTTPS + BasicAuth + IP       │
│                 │                                      │ whitelist — no direct ports          │
└─────────────────┴──────────────────────────────────────┴──────────────────────────────────────┘
```

Traffic flow:

- Application containers connect to `pgbouncer:5432` on the `db_internal` network.
- Local processes on the VPS connect via `localhost:5432` (loopback-bound PgBouncer).
- pgAdmin is reachable at `https://<PGADMIN_DOMAIN>` through Traefik, restricted by IP whitelist.
- Netdata is reachable at `https://<NETDATA_DOMAIN>` through Traefik, protected by BasicAuth and IP whitelist.
- PostgreSQL itself is never exposed outside `db_internal` / `monitor_internal`.

## Prerequisites

- Docker 24+ and Docker Compose v2 (`docker compose`)
- Traefik running on the host with:
  - An external Docker network named `traefik_proxy`
  - A `websecure` entrypoint with TLS
  - A `letsencrypt` certificate resolver
- DNS A records pointing to the server IP for both `PGADMIN_DOMAIN` and `NETDATA_DOMAIN`

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

3. Edit `.env` — set strong passwords, domains, and allowed IPs:

   ```bash
   nano .env
   ```

4. Generate the Netdata BasicAuth credential and paste it into `.env`:

   ```bash
   ./deploy.sh htpasswd admin YOUR_STRONG_PASSWORD
   ```

5. Deploy:

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
| `NETDATA_DOMAIN` | Hostname for Netdata via Traefik | `metrics.yourdomain.com` |
| `NETDATA_HOSTNAME` | Node name shown in Netdata UI | `prod-server-01` |
| `NETDATA_ALLOWED_IPS` | Comma-separated CIDRs for Netdata access | `203.0.113.10/32` |
| `NETDATA_BASIC_AUTH` | htpasswd entry for Traefik BasicAuth | `admin:$$apr1$$...` |

## Generating Netdata Basic Auth

Traefik protects the Netdata dashboard with HTTP Basic Authentication. The credential must be in htpasswd format with `$` characters escaped as `$$` for Docker Compose.

**Recommended — use deploy.sh (no local dependencies):**

```bash
./deploy.sh htpasswd admin YOUR_STRONG_PASSWORD
```

Copy the printed `NETDATA_BASIC_AUTH=...` line into your `.env` file.

**Manual — requires `apache2-utils`:**

```bash
echo $(htpasswd -nb admin YOURPASSWORD) | sed -e s/\$/\$\$/g
```

Paste the output as the value of `NETDATA_BASIC_AUTH` in `.env`.

## Connection Strings

Replace `PASSWORD` with your `POSTGRES_PASSWORD` value:

```text
# From another Docker container on db_internal network (via PgBouncer):
postgresql://appuser:PASSWORD@pgbouncer:5432/appdb

# From the VPS host itself (loopback):
postgresql://appuser:PASSWORD@localhost:5432/appdb
```

## Data Persistence

All persistent state is stored in named Docker volumes (`driver: local`):

| Volume | Stores | Survives |
|--------|--------|----------|
| `pgdata` | PostgreSQL data files | restarts, `down`, reboots |
| `pgbackups` | Automated backup dumps | restarts, `down`, reboots |
| `netdata_lib` | Netdata state, alarms, baselines | restarts, `down`, reboots |
| `netdata_cache` | Netdata metrics cache | restarts, `down`, reboots |

Data persists across container restarts, `docker compose down`, and host reboots.

**Never run `docker compose down -v` in production.** The `-v` flag removes named volumes and permanently destroys all database data and Netdata history.

To inspect a volume location on the host:

```bash
docker volume inspect pgstack-prod_pgdata
```

The `Mountpoint` field shows where Docker stores the files.

## What Netdata Monitors

- **Host:** CPU, RAM, disk usage, disk I/O, network throughput
- **Docker containers:** Per-container CPU, memory, network, and disk I/O for all stack services
- **PostgreSQL (optional, requires monitoring role):**
  - Active connections and query throughput
  - Lock waits and blocking queries
  - WAL generation and checkpoint activity
  - Autovacuum activity and table bloat indicators
  - Top queries via `pg_stat_statements`

Without the optional monitoring role, Netdata still collects container-level metrics for the `postgres` container.

## Optional: PostgreSQL Deep Monitoring

To enable deep PostgreSQL metrics in Netdata, create a read-only monitoring role:

```sql
CREATE ROLE netdata WITH LOGIN PASSWORD 'netdata_password_here';
GRANT pg_monitor TO netdata;
```

Run this inside the database as a superuser:

```bash
./deploy.sh shell
```

Then paste the SQL above. This step is optional — the stack works fully without it.

## Tuning for Your Server

The default `postgres/conf.d/postgresql.conf` is tuned for a VPS with 2–4 GB RAM. Adjust `shared_buffers` and `effective_cache_size` proportionally:

| Total RAM | shared_buffers (~25%) | effective_cache_size (~75%) |
|-----------|----------------------|----------------------------|
| 1 GB | 256MB | 768MB |
| 2 GB | 512MB | 1536MB |
| 4 GB | 1GB | 3GB |
| 8 GB | 2GB | 6GB |

After editing `postgresql.conf`, restart PostgreSQL:

```bash
./deploy.sh restart postgres
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
| `up` | Validate `.env`, connect Traefik to shared network, start stack |
| `down` | Stop stack (volumes preserved) |
| `restart [service]` | Restart all services or a specific one |
| `status` | Show service status and volumes |
| `check` | Diagnose Traefik connectivity, DNS, and service health |
| `logs [service]` | Tail logs (all services or one) |
| `shell` | Open `psql` as `POSTGRES_USER` |
| `backup` | Manual `pg_dump` to gzip file |
| `restore <file>` | Restore from a `.sql.gz` file |
| `htpasswd <user> <password>` | Generate `NETDATA_BASIC_AUTH` for `.env` |
| `help` | Show usage |

## Traefik Integration

This stack assumes Traefik is already running on the host. On `./deploy.sh up`, the script:

1. Creates the shared Docker network (`TRAEFIK_NETWORK`, default `traefik_proxy`)
2. Auto-connects any running Traefik container to that network
3. Registers routers with unique `pgstack-*` names to avoid collisions with other stacks

Configure Traefik-related values in `.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `TRAEFIK_NETWORK` | `traefik_proxy` | External Docker network shared with Traefik |
| `TRAEFIK_CERT_RESOLVER` | `letsencrypt` | Traefik certificate resolver name |
| `TRAEFIK_ENTRYPOINT_SECURE` | `websecure` | HTTPS entrypoint |
| `TRAEFIK_ENTRYPOINT_INSECURE` | `web` | HTTP entrypoint (redirects to HTTPS) |

**pgAdmin** is exposed through Traefik with:

- HTTPS via the `websecure` entrypoint
- HTTP → HTTPS redirect on the `web` entrypoint
- TLS certificates from the `letsencrypt` certresolver
- IP whitelist middleware restricting access to `PGADMIN_ALLOWED_IPS`
- `traefik.docker.network` set so Traefik reaches the container on the correct network

**Netdata** is exposed through Traefik with:

- HTTPS via the `websecure` entrypoint
- HTTP → HTTPS redirect on the `web` entrypoint
- TLS certificates from the `letsencrypt` certresolver
- BasicAuth middleware (`pgstack-netdata-auth`) using `NETDATA_BASIC_AUTH`
- IP whitelist middleware (`pgstack-netdata-ipwhitelist`) restricting access to `NETDATA_ALLOWED_IPS`

If your Traefik instance uses a different network name, set `TRAEFIK_NETWORK` in `.env`.

## Troubleshooting

### pgAdmin shows "Bad Gateway"

Usually Traefik cannot reach the `pgadmin` container.

1. Run diagnostics:
   ```bash
   ./deploy.sh check
   ```
2. Ensure Traefik is connected to `TRAEFIK_NETWORK`:
   ```bash
   docker network inspect traefik_proxy
   ```
   The Traefik container and `pgadmin` must both appear in `Containers`.
3. Wait up to 90 seconds after first deploy — pgAdmin needs time to initialize.
4. Check logs:
   ```bash
   ./deploy.sh logs pgadmin
   ```

### Netdata shows "404 page not found" or HTTPS fails

Usually the router is not registered or DNS/certificates are missing.

1. Confirm DNS A records exist for **both** domains in `.env`:
   - `PGADMIN_DOMAIN` (e.g. `db.hyperfx.io`)
   - `NETDATA_DOMAIN` (e.g. `metrics.hyperfx.io`)
2. Run:
   ```bash
   ./deploy.sh check
   ./deploy.sh up
   ```
3. Verify Traefik picked up labels:
   ```bash
   docker inspect pgadmin --format '{{json .Config.Labels}}' | jq .
   docker inspect netdata --format '{{json .Config.Labels}}' | jq .
   ```
4. Check Traefik logs for ACME/certificate errors.
5. Access via HTTPS (not HTTP): `https://metrics.yourdomain.com`

### Image pull errors (`bitnami/pgbouncer`)

Bitnami removed free images from Docker Hub. This stack uses `neondatabase/pgbouncer` instead.

## Security Notes

- All credentials are stored in `.env` only — never committed to version control
- PostgreSQL has zero port mappings — not reachable from the host or internet
- PgBouncer binds to `127.0.0.1:5432` only — loopback access, not `0.0.0.0`
- Netdata has zero port mappings — accessible only via Traefik
- pgAdmin is IP-restricted via Traefik middleware
- Netdata is double-protected: BasicAuth plus IP whitelist via Traefik
- TLS terminates at Traefik — PostgreSQL runs without SSL inside the internal network
- Password authentication uses `scram-sha-256`
- The `public` schema is locked down on init — application objects live in the `app` schema
- `db_internal` and `monitor_internal` networks are isolated (`internal: true`)

## License

MIT — see [LICENSE](LICENSE).
