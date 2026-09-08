# `DB-ELASTIC` -- OpenSearch

**Status: `IMPLEMENTATION_REQUIRED`**

- **Type:** platform-service (Platform Service -- Governance "Service vs image":
  must be provisioned via an approved operator/template, not a raw Deployment)
- **Domain:** Database
- **Use cases:** Search, indexing, vector/search experiments
- **Recommended technology (from workbook):** Approved OpenSearch deployment
- **Delivery (from workbook):** Template/Operator + approved images
- **Profile:** large (see `config/profiles.yaml`)
- **Storage:** 100Gi
- **Approval:** review
- **Owner:** Infra + Data
- **Priority:** P1

## Decision needed

Select and OperatorHub-certify the OpenSearch operator; define cluster sizing and snapshot policy.

## Candidate operators to evaluate

- OpenSearch Operator (opensearch-project/opensearch-k8s-operator)

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
