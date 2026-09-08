# `DATA-AIRFLOW` -- Airflow

**Status: `IMPLEMENTATION_REQUIRED`**

- **Type:** platform-service (Platform Service -- Governance "Service vs image":
  must be provisioned via an approved operator/template, not a raw Deployment)
- **Domain:** Data & Analytics
- **Use cases:** Workflow/data pipeline orchestration
- **Recommended technology (from workbook):** Airflow via approved Helm/operator pattern
- **Delivery (from workbook):** Template/Helm + approved images
- **Profile:** medium (see `config/profiles.yaml`)
- **Storage:** 50Gi
- **Approval:** review
- **Owner:** Infra + Data
- **Priority:** P1

## Decision needed

Select and security-review an Airflow Helm chart/version; define executor (Celery/Kubernetes) and metadata DB dependency (DB-PG).

## Candidate Helm charts to evaluate

- apache/airflow (community Helm chart)
- vendor-certified Airflow distribution

None of the above is pre-selected by this repository -- selection, OpenShift/
`restricted-v2` certification, and (where applicable) licensing/entitlement
sign-off are the responsibility of the Infra/DevOps/Security teams named
above. See `templates/platform-service/base/operator-placeholder/README.md`
for exactly what `scripts/provision.sh` does today (namespace + RBAC +
NetworkPolicy + ResourceQuota/LimitRange + an audit-trail ConfigMap) and
what changes once this decision is made.

## Files

- `example-operator-cr.yaml` / `helm-values-placeholder.yaml` -- illustrative
  only, not applied to any cluster. Replace once the Helm chart above is chosen.
