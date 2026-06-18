# Runbook — ciclo completo de apps

Guia plug-and-play para criar, fazer backup, apagar e restaurar bancos com a aplicação voltando ao normal.

Use o **Manager** (`./bin/manager.sh`) — menu **Apps**.

---

## Antes de começar

```bash
cd ~/pgstack-prod
docker compose up -d
./scripts/overview/status.sh   # PostgreSQL: ready
```

A senha do app deve ser **exatamente** a do `DATABASE_URL` no `.env` do Django (ou outro app).

---

## 1. Primeira vez — Setup app

**Manager → Apps → Setup app**

| Campo | Exemplo hyperfx |
|-------|-----------------|
| Database | `hyperfx` |
| App user | `hyperfx_django` |
| Label | `HyperFX Stake` (opcional) |
| Password | senha do `DATABASE_URL` |

O script cria o banco, schema `app`, usuário owner, isola acesso e **verifica login** antes de mostrar OK.

Depois no app:

```bash
python manage.py migrate
python manage.py check
```

---

## 2. Rotina — Backup

**Manager → Apps → Backup app** → escolha `hyperfx`

Gera dois arquivos em `data/backups/`:

- `backup_hyperfx_YYYYMMDD_HHMMSS.sql.gz` — dados
- `backup_hyperfx_YYYYMMDD_HHMMSS.manifest.json` — usuários e permissões

---

## 3. Quando der problema — Restore

**Manager → Apps → Restore app**

1. Escolha o app (`hyperfx`)
2. Escolha o número do backup
3. Digite a senha do `DATABASE_URL`
4. Confirme com `YES`

O restore:

- Limpa schema `app` (ou cria DB vazio se não existir)
- Importa o backup
- Recria usuários e grants
- Sincroniza senha
- **Verifica login** — se falhar, mostra erro (sem OK falso)

Reinicie o app para limpar connection pools.

---

## 4. Apagar banco

**Manager → Apps → Drop app**

- Por padrão faz **backup antes** de apagar
- Confirme com `YES`
- Usuários exclusivos do banco são removidos

Para voltar: **Restore app** com o backup de segurança.

---

## 5. Verificar se está OK

**Manager → Apps → Verify app**

- Escolha o app
- Senha do `DATABASE_URL`

Mostra `PASS` só se login SCRAM + `search_path=app` + schema existirem.

Use isso **antes** de culpar o Django.

---

## CLI (SSH sem Manager)

```bash
export PGSTACK_PASSWORD='senha-do-DATABASE_URL'

./scripts/app.sh setup   hyperfx hyperfx_django "HyperFX Stake"
./scripts/app.sh backup  hyperfx
./scripts/app.sh verify  hyperfx

# Restore após drop ou corrupção
PGSTACK_YES=1 ./scripts/app.sh restore data/backups/backup_hyperfx_XXXXXX.sql.gz

# Drop com backup automático
PGSTACK_YES=1 ./scripts/app.sh drop hyperfx --backup-first
```

---

## Registro de apps

Apps ficam em `data/apps/registry.json` (sem senha):

```json
{
  "hyperfx": {
    "user": "hyperfx_django",
    "label": "HyperFX Stake"
  }
}
```

---

## Teste automatizado (servidor)

```bash
./scripts/setup/test-app-lifecycle.sh
```

Roda: setup → backup → drop → restore → verify e limpa sozinho.

---

## Recuperação rápida (hyperfx)

```
Manager → Apps → Restore → hyperfx → último backup → senha → YES
Manager → Apps → Verify → hyperfx
```

No Mac: `python manage.py check`

---

## Troubleshooting

| Sintoma | Ação |
|---------|------|
| `password authentication failed` | Apps → Verify; senha ≠ `.env` → Users → Reset password → From DATABASE_URL |
| `schema app does not exist` | Apps → Restore ou Setup |
| Restore OK mas app não conecta | Reinicie o app; rode Verify |
| Sem backups na lista | Apps → Backup app primeiro |

Mais detalhes: [BACKUP.md](BACKUP.md)
