# Catalog Domain: Data & Analytics

This directory documents the Catalog IDs in this domain and how each one is implemented. Full machine-readable detail lives in `config/catalog.yaml`; this file is the human-readable index. See `docs/CATALOG-MAPPING.md` for the complete cross-catalog table.

| Catalog ID | Offering | Type | Implementation | Approval | Priority |
|---|---|---|---|---|---|
| `DATA-AIRFLOW` | Airflow | platform-service | helm-placeholder | review | P1 |
| `DATA-DBT` | dbt Dev | workspace | workspace-template | review | P1 |
| `DATA-JUP` | JupyterLab | workspace | workspace-template | auto | P0 |
| `DATA-R` | R / RStudio-like Workspace | workspace | workspace-template | review | P2 |
| `DATA-SPARK` | Apache Spark | platform-service | operator-placeholder | review | P1 |
| `DATA-TRINO` | Trino | platform-service | helm-placeholder | review | P2 |

## Entries requiring an enterprise implementation decision

- **`DATA-AIRFLOW`** (Airflow) -- see `catalog/data/data-airflow/README.md`
- **`DATA-SPARK`** (Apache Spark) -- see `catalog/data/data-spark/README.md`
- **`DATA-TRINO`** (Trino) -- see `catalog/data/data-trino/README.md`

