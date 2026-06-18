# Persistent data (not in git)

All Docker persistent files for this stack live here:

```text
data/
├── postgres/          PostgreSQL cluster (database files)
├── backups/           .sql.gz backup files
└── logs/
    └── postgres/      daily PostgreSQL log files
```

Configured in `.env` via `DATA_DIR` only. Backups and logs are always:
`DATA_DIR/backups` and `DATA_DIR/logs/postgres`.

**Backup this entire `data/` folder** when moving servers or for disaster recovery.

On first start: `docker compose up -d` creates missing subfolders automatically.
