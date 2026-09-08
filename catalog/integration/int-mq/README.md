# `INT-MQ` -- Message Broker

**Status: `IMPLEMENTATION_REQUIRED`**

- **Type:** platform-service (Platform Service -- Governance "Service vs image":
  must be provisioned via an approved operator/template, not a raw Deployment)
- **Domain:** Integration
- **Use cases:** Messaging/queue experiments
- **Recommended technology (from workbook):** Approved AMQ/RabbitMQ equivalent
- **Delivery (from workbook):** Operator/Template
- **Profile:** medium (see `config/profiles.yaml`)
- **Storage:** 20Gi
- **Approval:** review
- **Owner:** Infra + Integration
- **Priority:** P2

## Decision needed

Select and OperatorHub-certify a messaging operator; define queue/exchange provisioning policy.

## Candidate operators to evaluate

- AMQ Broker Operator
- RabbitMQ Cluster Operator

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
