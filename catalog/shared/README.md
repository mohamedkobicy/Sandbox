# Catalog Domain: Shared Capability

This directory documents the Catalog IDs in this domain and how each one is implemented. Full machine-readable detail lives in `config/catalog.yaml`; this file is the human-readable index. See `docs/CATALOG-MAPPING.md` for the complete cross-catalog table.

| Catalog ID | Offering | Type | Implementation | Approval | Priority |
|---|---|---|---|---|---|
| `SHARED-GIT` | Git Integration | integration | platform-integration | auto | P0 |
| `SHARED-OBS` | Observability Integration | integration | platform-integration | auto | P0 |
| `SHARED-SECRETS` | Secrets Integration | integration | platform-integration | review | P0 |

## Shared platform-integration entries (not standalone workloads)

- **`SHARED-GIT`** (Git Integration) -- see `templates/integration/git/README.md`
- **`SHARED-OBS`** (Observability Integration) -- see `templates/integration/observability/README.md`
- **`SHARED-SECRETS`** (Secrets Integration) -- see `templates/integration/secrets/README.md`

