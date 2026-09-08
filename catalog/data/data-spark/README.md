# `DATA-SPARK` -- Apache Spark

**Status: `IMPLEMENTATION_REQUIRED`**

- **Type:** platform-service (Platform Service -- Governance "Service vs image":
  must be provisioned via an approved operator/template, not a raw Deployment)
- **Domain:** Data & Analytics
- **Use cases:** Distributed data processing
- **Recommended technology (from workbook):** Approved Spark distribution/operator
- **Delivery (from workbook):** Template/Operator + approved images
- **Profile:** large (see `config/profiles.yaml`)
- **Storage:** 100Gi
- **Approval:** review
- **Owner:** Infra + Data
- **Priority:** P1

## Decision needed

Select and OperatorHub-certify a Spark operator/distribution for OpenShift; define driver/executor resource policy.

## Candidate operators to evaluate

- Kubeflow Spark Operator (spark-operator)
- Apache Spark on Kubernetes (spark-submit, in-cluster scheduler mode)

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
