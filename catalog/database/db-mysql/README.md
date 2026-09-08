# `DB-MYSQL` -- MySQL

**Status: `IMPLEMENTATION_REQUIRED`**

- **Type:** platform-service (Platform Service -- Governance "Service vs image":
  must be provisioned via an approved operator/template, not a raw Deployment)
- **Domain:** Database
- **Use cases:** Relational application testing
- **Recommended technology (from workbook):** Approved MySQL deployment
- **Delivery (from workbook):** Template/Operator + approved image
- **Profile:** medium (see `config/profiles.yaml`)
- **Storage:** 20Gi
- **Approval:** review
- **Owner:** Infra + DBA
- **Priority:** P2

## Decision needed

Select and OperatorHub-certify a MySQL operator; confirm licensing for any non-community distribution.

## Candidate operators to evaluate

- Percona Operator for MySQL
- Oracle MySQL Operator

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
