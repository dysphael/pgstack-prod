# Runbook — ciclo completo (só databases)

Guia plug-and-play para **criar, fazer backup, apagar e restaurar** bancos, com a
aplicação voltando ao normal. Sem "Apps", sem registry, sem manifest, sem schema `app`.

Tudo usa o schema padrão **`public`**. Use o **Manager** (`./bin/manager.sh`).

```text
Create DB  →  Add user  →  Backup  →  Drop  →  Restore  →  Add user de novo
```

---

## Antes de começar

```bash
cd ~/pgstack-prod
docker compose up -d
./scripts/overview/status.sh   # PostgreSQL: ready
```

---

## 1. Criar o banco

**Manager → Databases → Create** (ou pela CLI):

```bash
./scripts/databases/create-db.sh myapp
```

Cria um banco **vazio** no schema `public` (com as extensões `uuid-ossp` e `pg_trgm`).
Nenhum usuário é criado aqui.

---

## 2. Criar o usuário do app

**Manager → Users → Add user** (ou pela CLI). Use a senha **exata** do
`DATABASE_URL` do Django/app:

```bash
PGSTACK_PASSWORD='senha-do-DATABASE_URL' \
  ./scripts/users/add-user.sh myapp owner myapp_api
```

O script cria o role, isola o acesso ao banco `myapp`, dá ownership total no
`public` e **verifica o login** (estilo remoto/SCRAM) antes de mostrar OK.

Depois, no app:

```bash
python manage.py migrate
python manage.py check
```

`owner` assume a ownership das tabelas/sequences (inclusive após restore), então
`migrate` e `ALTER TABLE` funcionam sem `permission denied`.

---

## 3. Backup

**Manager → Backups → Backup one** → escolha `myapp` (ou CLI):

```bash
./scripts/backups/backup.sh myapp        # um banco
./scripts/backups/backup.sh              # todos
```

Gera um único arquivo **portátil** em `data/backups/`:

```text
backup_myapp_YYYYMMDD_HHMMSS.sql.gz
```

Feito com `pg_dump --no-owner --no-acl` — pode ser **copiado para outro servidor**
e restaurado direto, sem depender de roles ou senhas.

---

## 4. Restaurar

**Manager → Backups → Restore** (ou CLI):

```bash
./scripts/backups/restore.sh data/backups/backup_myapp_YYYYMMDD_HHMMSS.sql.gz
# o nome do banco é inferido do arquivo; ou passe explícito:
./scripts/backups/restore.sh data/backups/backup_myapp_...sql.gz myapp
```

O restore:

1. Desconecta sessões abertas no banco
2. **DROP DATABASE** + **CREATE DATABASE** (banco limpo)
3. Carrega o dump **100%**

Não pede senha, manifest nem registry. Funciona com qualquer `.sql.gz`, inclusive
copiado de outro servidor.

> Usuários **não** fazem parte do backup. Depois do restore, **recrie o usuário do app**
> (passo 2): `add-user.sh myapp owner myapp_api`. Aí o Django conecta normalmente.

Reinicie o app para limpar os connection pools.

---

## 5. Apagar banco

**Manager → Databases → Drop** (ou CLI):

```bash
./scripts/databases/drop-db.sh myapp
```

Desconecta sessões e dá `DROP DATABASE`. **Não** mexe em roles. Confirme com `YES`
(ou `PGSTACK_YES=1` para pular a confirmação).

Para voltar: faça **Restore** com um backup.

---

## Copiar backup entre servidores

```bash
# no servidor de origem
scp data/backups/backup_myapp_*.sql.gz user@destino:~/pgstack-prod/data/backups/

# no servidor de destino
./scripts/backups/restore.sh data/backups/backup_myapp_*.sql.gz myapp
./scripts/users/add-user.sh myapp owner myapp_api   # recria o user do app
```

---

## Troubleshooting

| Sintoma | Ação |
|---------|------|
| `password authentication failed` | Senha ≠ `DATABASE_URL` → Users → Reset password → From DATABASE_URL |
| `permission denied for table ...` | Recrie o user como `owner` (assume ownership): `add-user.sh <db> owner <user>` |
| Restore OK mas app não conecta | Recrie o user do app; reinicie o app |
| Sem backups na lista | Backups → Backup one primeiro |

Diagnóstico de login:

```bash
PGSTACK_PASSWORD='...' ./scripts/tools/diagnose-user.sh myapp_api myapp
```

Mais detalhes: [BACKUP.md](BACKUP.md)
