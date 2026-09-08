# `DATA-TRINO` -- Trino

**Status: `IMPLEMENTATION_REQUIRED`**

- **Type:** platform-service (Platform Service -- Governance "Service vs image":
  must be provisioned via an approved operator/template, not a raw Deployment)
- **Domain:** Data & Analytics
- **Use cases:** Federated SQL/query experimentation
- **Recommended technology (from workbook):** Approved Trino deployment
- **Delivery (from workbook):** Template/Helm + approved images
- **Profile:** large (see `config/profiles.yaml`)
- **Storage:** 50Gi
- **Approval:** review
- **Owner:** Infra + Data
- **Priority:** P2

## Decision needed

Select and security-review a Trino Helm chart/version; define catalog/connector configuration policy.

## Candidate Helm charts to evaluate

- trinodb/trino (community Helm chart)

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
