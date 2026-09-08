# `DB-PG` -- PostgreSQL

**Status: `IMPLEMENTATION_REQUIRED`**

- **Type:** platform-service (Platform Service -- Governance "Service vs image":
  must be provisioned via an approved operator/template, not a raw Deployment)
- **Domain:** Database
- **Use cases:** Relational DB, application prototypes
- **Recommended technology (from workbook):** PostgreSQL operator/template
- **Delivery (from workbook):** Operator + sandbox/data/postgresql
- **Profile:** medium (see `config/profiles.yaml`)
- **Storage:** 20Gi
- **Approval:** auto
- **Owner:** Infra + DBA
- **Priority:** P0

## Decision needed

Select and OperatorHub-certify a PostgreSQL operator for OpenShift; define backup/HA policy for sandbox use.

## Candidate operators to evaluate

- Crunchy Postgres for Kubernetes (PGO)
- CloudNativePG

None of the above is pre-selected by this repository -- selection, OpenShift/
`restricted-v2` certification, and (where applicable) licensing/entitlement
sign-off are the responsibility of the Infra/DevOps/Security teams named
above. See `templates/platform-service/base/operator-placeholder/README.md`
for exactly what `scripts/provision.sh` does today (namespace + RBAC +
NetworkPolicy + ResourceQuota/LimitRange + an audit-trail ConfigMap) and
what changes once this decision is made.

## Files

- `example-operator-cr.yaml` / `helm-values-placeholder.yaml` -- illustrative
  only, not applied to any cluster. Replace once the operator above is chosen.
