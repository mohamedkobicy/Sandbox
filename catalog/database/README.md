# Catalog Domain: Database

This directory documents the Catalog IDs in this domain and how each one is implemented. Full machine-readable detail lives in `config/catalog.yaml`; this file is the human-readable index. See `docs/CATALOG-MAPPING.md` for the complete cross-catalog table.

| Catalog ID | Offering | Type | Implementation | Approval | Priority |
|---|---|---|---|---|---|
| `DB-ELASTIC` | OpenSearch | platform-service | operator-placeholder | review | P1 |
| `DB-MONGO` | MongoDB-compatible | platform-service | operator-placeholder | review | P2 |
| `DB-MYSQL` | MySQL | platform-service | operator-placeholder | review | P2 |
| `DB-PG` | PostgreSQL | platform-service | operator-placeholder | auto | P0 |
| `DB-VALKEY` | Valkey / Cache | platform-service | statefulset-template | auto | P1 |

## Entries requiring an enterprise implementation decision

- **`DB-ELASTIC`** (OpenSearch) -- see `catalog/database/db-elastic/README.md`
- **`DB-MONGO`** (MongoDB-compatible) -- see `catalog/database/db-mongo/README.md`
- **`DB-MYSQL`** (MySQL) -- see `catalog/database/db-mysql/README.md`
- **`DB-PG`** (PostgreSQL) -- see `catalog/database/db-pg/README.md`

