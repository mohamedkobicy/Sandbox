# Catalog Mapping

Complete Catalog ID -> implementation mapping for every entry in the `Catalog` sheet of `Sandbox_Image_Catalog.xlsx`, cross-referenced against `config/catalog.yaml` (the machine-readable source of truth consumed by `scripts/provision.sh`).

**Legend:** PVC = a PersistentVolumeClaim is created. Service/Route = an in-cluster Service / externally reachable Route is created. Approval = `Auto` (standard validation only) or `Review` (requires `--approved true` from an already-approved upstream workflow -- see `docs/SECURITY.md`).


## Base Images (not independently provisioned)

| Catalog ID | Type | Implementation | Image/Operator | PVC | Service | Route | Approval |
|---|---|---|---|---|---|---|---|
| `BASE-BUSYBOX` | base-image | N/A (base layer) | `sandbox/base/utility-minimal:approved` | No | No | No | auto |
| `BASE-UBI9` | base-image | N/A (base layer) | `sandbox/base/ubi9:approved` | No | No | No | auto |
| `BASE-UBI9M` | base-image | N/A (base layer) | `sandbox/base/ubi9-minimal:approved` | No | No | No | auto |

## Development Runtime

| Catalog ID | Type | Implementation | Image/Operator | PVC | Service | Route | Approval |
|---|---|---|---|---|---|---|---|
| `DEV-DOTNET` | workspace | `templates/workspace/base` | `sandbox/dev/dotnet:approved` | Yes | No | No | auto |
| `DEV-GO` | workspace | `templates/workspace/base` | `sandbox/dev/go:approved` | Yes | No | No | auto |
| `DEV-JAVA` | workspace | `templates/workspace/base` | `sandbox/dev/java:approved` | Yes | No | No | auto |
| `DEV-NODE` | workspace | `templates/workspace/base` | `sandbox/dev/nodejs:approved` | Yes | No | No | auto |
| `DEV-PHP` | workspace | `templates/workspace/base` | `sandbox/dev/php:approved` | Yes | No | No | auto |
| `DEV-PY` | workspace | `templates/workspace/base` | `sandbox/dev/python:approved` | Yes | No | No | auto |
| `DEV-RUBY` | workspace | `templates/workspace/base` | `sandbox/dev/ruby:approved` | Yes | No | No | review |
| `DEV-RUST` | workspace | `templates/workspace/base` | `sandbox/dev/rust:approved` | Yes | No | No | review |

## AI & Agentic

| Catalog ID | Type | Implementation | Image/Operator | PVC | Service | Route | Approval |
|---|---|---|---|---|---|---|---|
| `AI-AGENT` | workspace | `templates/workspace/base` | `sandbox/ai/agent-engineering:approved` | Yes | No | No | review |
| `AI-FULL` | workspace | `templates/workspace/base` | `sandbox/ai/fullstack-dev:approved` | Yes | No | No | auto |
| `AI-HF` | workspace | `templates/workspace/base` | `sandbox/ai/transformers:approved` | Yes | No | No | review |
| `AI-LLMTOOLS` | workspace | `templates/workspace/base` | `sandbox/ai/llm-app-dev:approved` | Yes | No | No | review |
| `AI-PT` | workspace | `templates/workspace/base` | `sandbox/ai/pytorch:approved` | Yes | No | No | review |
| `AI-PY` | workspace | `templates/workspace/base` | `sandbox/ai/python-ai:approved` | Yes | No | No | auto |
| `AI-TF` | workspace | `templates/workspace/base` | `sandbox/ai/tensorflow:approved` | Yes | No | No | review |

## Data & Analytics

| Catalog ID | Type | Implementation | Image/Operator | PVC | Service | Route | Approval |
|---|---|---|---|---|---|---|---|
| `DATA-AIRFLOW` | platform-service | **IMPLEMENTATION_REQUIRED** (Helm) -- `catalog/data/data-airflow/` | TBD: apache/airflow (community Helm chart); vendor-certified Airflow distribution | Yes | No | No | review |
| `DATA-DBT` | workspace | `templates/workspace/base` | `sandbox/data/dbt:approved` | Yes | No | No | review |
| `DATA-JUP` | workspace | `templates/workspace/base` | `sandbox/data/jupyter:approved` | Yes | Yes | Yes | auto |
| `DATA-R` | workspace | `templates/workspace/base` | `sandbox/data/r:approved` | Yes | No | No | review |
| `DATA-SPARK` | platform-service | **IMPLEMENTATION_REQUIRED** (operator) -- `catalog/data/data-spark/` | TBD: Kubeflow Spark Operator (spark-operator); Apache Spark on Kubernetes (spark-submit, in-cluster scheduler mode) | Yes | No | No | review |
| `DATA-TRINO` | platform-service | **IMPLEMENTATION_REQUIRED** (Helm) -- `catalog/data/data-trino/` | TBD: trinodb/trino (community Helm chart) | Yes | No | No | review |

## Database

| Catalog ID | Type | Implementation | Image/Operator | PVC | Service | Route | Approval |
|---|---|---|---|---|---|---|---|
| `DB-ELASTIC` | platform-service | **IMPLEMENTATION_REQUIRED** (operator) -- `catalog/database/db-elastic/` | TBD: OpenSearch Operator (opensearch-project/opensearch-k8s-operator) | Yes | No | No | review |
| `DB-MONGO` | platform-service | **IMPLEMENTATION_REQUIRED** (operator) -- `catalog/database/db-mongo/` | TBD: Percona Operator for MongoDB; MongoDB Community Kubernetes Operator; FerretDB (Postgres-backed, license-friendly alternative) | Yes | No | No | review |
| `DB-MYSQL` | platform-service | **IMPLEMENTATION_REQUIRED** (operator) -- `catalog/database/db-mysql/` | TBD: Percona Operator for MySQL; Oracle MySQL Operator | Yes | No | No | review |
| `DB-PG` | platform-service | **IMPLEMENTATION_REQUIRED** (operator) -- `catalog/database/db-pg/` | TBD: Crunchy Postgres for Kubernetes (PGO); CloudNativePG | Yes | No | No | auto |
| `DB-VALKEY` | platform-service | `templates/platform-service/base/statefulset` | `sandbox/data/valkey:approved` | Yes | Yes | No | auto |

## Integration

| Catalog ID | Type | Implementation | Image/Operator | PVC | Service | Route | Approval |
|---|---|---|---|---|---|---|---|
| `INT-API` | workspace | `templates/workspace/base` | `sandbox/integration/api-dev:approved` | Yes | No | No | auto |
| `INT-KAFKA` | platform-service | **IMPLEMENTATION_REQUIRED** (operator) -- `catalog/integration/int-kafka/` | TBD: Strimzi / AMQ Streams (Kafka-operator ecosystem) | Yes | No | No | review |
| `INT-KCONNECT` | platform-service | `templates/platform-service/base/statefulset` | `sandbox/integration/kafka-connect:approved` | Yes | Yes | No | review |
| `INT-MQ` | platform-service | **IMPLEMENTATION_REQUIRED** (operator) -- `catalog/integration/int-mq/` | TBD: AMQ Broker Operator; RabbitMQ Cluster Operator | Yes | No | No | review |

## DevOps & Platform

| Catalog ID | Type | Implementation | Image/Operator | PVC | Service | Route | Approval |
|---|---|---|---|---|---|---|---|
| `OPS-ANSIBLE` | workspace | `templates/workspace/base` | `sandbox/tools/ansible:approved` | Yes | No | No | review |
| `OPS-CICD` | workspace | `templates/workspace/base` | `sandbox/tools/cicd:approved` | Yes | No | No | review |
| `OPS-HELM` | workspace | `templates/workspace/base` | `sandbox/tools/k8s-packaging:approved` | Yes | No | No | auto |
| `OPS-IAC` | workspace | `templates/workspace/base` | `sandbox/tools/iac:approved` | Yes | No | No | review |
| `OPS-OC` | workspace | `templates/workspace/base` | `sandbox/tools/openshift:approved` | Yes | No | No | review |

## Testing

| Catalog ID | Type | Implementation | Image/Operator | PVC | Service | Route | Approval |
|---|---|---|---|---|---|---|---|
| `TEST-API` | workspace | `templates/workspace/base` | `sandbox/test/api:approved` | Yes | No | No | auto |
| `TEST-PERF` | workspace | `templates/workspace/base` | `sandbox/test/performance:approved` | Yes | No | No | review |
| `TEST-WEB` | workspace | `templates/workspace/base` | `sandbox/test/browser:approved` | Yes | No | No | review |

## Security

| Catalog ID | Type | Implementation | Image/Operator | PVC | Service | Route | Approval |
|---|---|---|---|---|---|---|---|
| `SEC-NET` | workspace | `templates/workspace/base` | `sandbox/security/network-tools:approved` | Yes | No | No | review |
| `SEC-SAST` | workspace | `templates/workspace/base` | `sandbox/security/devsecops:approved` | Yes | No | No | review |

## Web

| Catalog ID | Type | Implementation | Image/Operator | PVC | Service | Route | Approval |
|---|---|---|---|---|---|---|---|
| `WEB-FRONT` | workspace | `templates/workspace/base` | `sandbox/web/frontend-dev:approved` | Yes | Yes | Yes | auto |
| `WEB-NGINX` | service | `templates/service/base` | `sandbox/web/nginx:approved` | Yes | Yes | Yes | auto |

## Storage

| Catalog ID | Type | Implementation | Image/Operator | PVC | Service | Route | Approval |
|---|---|---|---|---|---|---|---|
| `STO-S3CLI` | workspace | `templates/workspace/base` | `sandbox/storage/s3-client:approved` | Yes | No | No | auto |

## Shared Capability

| Catalog ID | Type | Implementation | Image/Operator | PVC | Service | Route | Approval |
|---|---|---|---|---|---|---|---|
| `SHARED-GIT` | integration | `templates/integration/git` | (no image -- configuration only) | No | No | No | auto |
| `SHARED-OBS` | integration | `templates/integration/observability` | (no image -- configuration only) | No | No | No | auto |
| `SHARED-SECRETS` | integration | `templates/integration/secrets` | (no image -- configuration only) | No | No | No | review |

**Total Catalog IDs covered: 49** (matches `config/catalog.yaml` `metadata.generatedEntries`).


## Implementation method reference

| Method | Meaning | Where it lives |
|---|---|---|
| `workspace-template` | Deployment + optional PVC/Service/Route, rendered per request | `templates/workspace/base` |
| `service-template` | Stateless Deployment + Service (+ optional Route), rendered per request | `templates/service/base` |
| `statefulset-template` | StatefulSet + headless Service, direct approved image, no operator | `templates/platform-service/base/statefulset` |
| `operator-placeholder` | **IMPLEMENTATION_REQUIRED**: namespace scaffolding only, pending an enterprise-selected operator | `templates/platform-service/base/operator-placeholder` |
| `helm-placeholder` | **IMPLEMENTATION_REQUIRED**: namespace scaffolding only, pending an enterprise-selected/reviewed Helm chart | `templates/platform-service/base/operator-placeholder` (same scaffolding path) |
| `platform-integration` | Not a standalone workload; a component layered onto other workspaces via `--enable` | `templates/integration/*` |
| `none-base-image` | Build-time foundation layer; not independently provisioned or Remedy-selectable | N/A |

## IMPLEMENTATION_REQUIRED summary

The following Catalog IDs cannot be fully automated today because the workbook
names a category of technology ("Approved Kafka operator/distribution", "Airflow
via approved Helm/operator pattern", etc.) without naming a specific,
enterprise-licensed product. This repository deliberately does not invent or
assume a company-specific operator for these. See each entry's
`catalog/<domain>/<id>/README.md` for the exact decision needed and candidate
technologies to evaluate:

- `DATA-AIRFLOW` (Airflow) -- `catalog/data/data-airflow/README.md`
- `DATA-SPARK` (Apache Spark) -- `catalog/data/data-spark/README.md`
- `DATA-TRINO` (Trino) -- `catalog/data/data-trino/README.md`
- `DB-ELASTIC` (OpenSearch) -- `catalog/database/db-elastic/README.md`
- `DB-MONGO` (MongoDB-compatible) -- `catalog/database/db-mongo/README.md`
- `DB-MYSQL` (MySQL) -- `catalog/database/db-mysql/README.md`
- `DB-PG` (PostgreSQL) -- `catalog/database/db-pg/README.md`
- `INT-KAFKA` (Kafka) -- `catalog/integration/int-kafka/README.md`
- `INT-MQ` (Message Broker) -- `catalog/integration/int-mq/README.md`

## Reconciliation report: `Sandbox_Image_Catalog.xlsx` vs `config/catalog.yaml`

Performed by cross-loading every sheet of the workbook against
`config/catalog.yaml` field-by-field (Catalog ID set, `remedySelectable`,
`approval`, `profile`, `priority`, `storage`, and per-family counts). Result:

| Check | Result |
|---|---|
| `Catalog` sheet rows | 49, all unique -- **no duplicate Catalog IDs** |
| Catalog IDs in Excel but missing from `config/catalog.yaml` | **none** |
| Catalog IDs in `config/catalog.yaml` but not in the Excel `Catalog` sheet | **none** |
| Field-level mismatches (`remedySelectable`, `approval`, `profile`, `priority`) between the `Catalog` sheet and `config/catalog.yaml` | **none** |
| `Remedy Catalog View` sheet rows (46) vs `config/catalog.yaml` entries with `remedySelectable: true` (46) | **exact match**, including per-row `profile`/`storage`/`approval`/`priority` |
| `Family Summary` sheet per-domain counts vs `config/catalog.yaml` `domainLabel` counts | **exact match on all 13 families** (AI & Agentic 7, Base Images 3, Data & Analytics 6, Database 4, Database/Search 1, DevOps & Platform 5, Development Runtime 8, Integration 4, Security 2, Shared Capability 3, Storage 1, Testing 3, Web 2 -- sums to 49) |
| `Governance` sheet rules | all 9 rules mapped to `config/policies.yaml` (see that file's inline `governanceRule` comments) and enforced in `scripts/provision.sh`/`scripts/validate.sh` where automatable; the 3 rules requiring a human/organizational decision (Golden source, Scan, Entitlement) are documented as external process requirements, not simulated by this repository |

**Conclusion: `config/catalog.yaml` is a complete and consistent transcription
of the workbook.** No Catalog ID was dropped, renamed, or silently merged.
