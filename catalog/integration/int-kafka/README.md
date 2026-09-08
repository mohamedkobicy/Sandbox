# `INT-KAFKA` -- Kafka

**Status: `IMPLEMENTATION_REQUIRED`**

- **Type:** platform-service (Platform Service -- Governance "Service vs image":
  must be provisioned via an approved operator/template, not a raw Deployment)
- **Domain:** Integration
- **Use cases:** Event streaming, integration prototypes
- **Recommended technology (from workbook):** Approved Kafka operator/distribution
- **Delivery (from workbook):** Operator + approved images
- **Profile:** large (see `config/profiles.yaml`)
- **Storage:** 100Gi
- **Approval:** review
- **Owner:** Infra + Integration
- **Priority:** P1

## Decision needed

Confirm licensed Kafka operator (e.g. AMQ Streams subscription) and OperatorHub channel; define topic/quota policy.

## Candidate operators to evaluate

- Strimzi / AMQ Streams (Kafka-operator ecosystem)

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
