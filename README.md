# pgstack-prod

PostgreSQL 16 com persistência via Docker Compose.

## Uso

```bash
cp .env.example .env
nano .env
docker compose up -d
```

## Conexão

```text
postgresql://appuser:PASSWORD@localhost:5432/blockway
```

Substitua `PASSWORD` pelo valor de `POSTGRES_PASSWORD` no `.env`.

## Comandos úteis

```bash
docker compose ps
docker compose logs -f postgres
docker compose exec postgres psql -U appuser -d blockway
docker compose down          # para o container (dados preservados)
```

**Não use** `docker compose down -v` em produção — isso apaga o volume com os dados.

## Persistência

Os dados ficam no volume Docker `pgdata` e sobrevivem a restart, `down` e reboot do servidor.
