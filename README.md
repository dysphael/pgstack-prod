# pgstack-prod

Production PostgreSQL 16 — DNS-based access for your applications (no admin UI).

## DNS setup (required)

Create an **A record** pointing to this server's public IP:

```text
db.yourdomain.com  →  YOUR_VPS_PUBLIC_IP
```

Use the same hostname as `POSTGRES_HOST` in `.env`.

## Deploy

```bash
cp .env.example .env
nano .env
docker compose up -d
docker compose ps   # wait for "healthy"
```

## Application connection

Use `POSTGRES_HOST` in your apps:

```text
postgresql://appuser:PASSWORD@db.yourdomain.com:5432/DATABASE_NAME
```

Example:

```env
DATABASE_URL=postgresql://appuser:PASSWORD@db.yourdomain.com:5432/myapp
```

Apps on the **same VPS** can also use:

```text
postgresql://appuser:PASSWORD@localhost:5432/DATABASE_NAME
```

## Create a project database

```bash
docker compose exec postgres psql -U appuser -d postgres -c "CREATE DATABASE myapp;"
```

## Will DNS work? (checklist)

This stack is configured for remote access via DNS when these conditions are met:

| Requirement | Status in this repo |
|-------------|---------------------|
| DNS A record → VPS public IP | You configure at your DNS provider |
| PostgreSQL listens on all interfaces | `listen_addresses=*` in `docker-compose.yml` |
| Port 5432 published on the host | `POSTGRES_PORT_PUBLISH=5432:5432` (default) |
| Password authentication | `POSTGRES_USER` / `POSTGRES_PASSWORD` in `.env` |
| Firewall allows port 5432 | You configure on the VPS (see below) |

**Verify after deploy:**

```bash
# 1. DNS resolves to your VPS IP
dig +short A db.yourdomain.com

# 2. Port 5432 is open (from your app server or local machine)
nc -zv db.yourdomain.com 5432

# 3. PostgreSQL accepts connections (replace PASSWORD)
psql "postgresql://appuser:PASSWORD@db.yourdomain.com:5432/postgres" -c "SELECT 1;"
```

If step 1 works but step 2 fails, open port 5432 in the VPS firewall and cloud security group.

## Security

Port `5432` is exposed on the network. Restrict it to your application servers:

```bash
sudo ufw allow from APP_SERVER_IP to any port 5432 proto tcp
sudo ufw enable
```

For **localhost-only** access on the VPS, set in `.env`:

```env
POSTGRES_PORT_PUBLISH=127.0.0.1:5432:5432
```

## Environment variables

| Variable | Description |
|----------|-------------|
| `POSTGRES_USER` | Database user |
| `POSTGRES_PASSWORD` | Database password |
| `POSTGRES_DB` | Database created on first boot (`postgres` recommended) |
| `POSTGRES_HOST` | DNS hostname used in application connection strings |
| `POSTGRES_PORT_PUBLISH` | Port mapping (`5432:5432` or `127.0.0.1:5432:5432`) |

## Operations

```bash
docker compose ps
docker compose logs -f postgres
docker compose exec postgres psql -U appuser -d postgres
docker compose down
```

**Never run** `docker compose down -v` in production — it deletes all data.

## Backup

```bash
docker compose exec -T postgres pg_dump -U appuser myapp | gzip > backup_myapp_$(date +%Y%m%d).sql.gz
```

## SSL note

PostgreSQL uses port **5432** with the `postgresql://` protocol — not HTTPS on port 443. DNS only resolves the hostname to your VPS IP.

For encrypted connections, configure PostgreSQL SSL or use a VPN/SSH tunnel between your apps and the database server.
