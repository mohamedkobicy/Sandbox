# Operator / Helm Platform-Service Placeholder

## Why this exists

Governance rule **"Service vs image"** requires that databases, Kafka,
Spark, OpenSearch, messaging, and Airflow-class services be provisioned
through approved **templates/operators**, never as arbitrary Deployments
built from a raw container image. For the Catalog IDs listed in
`docs/CATALOG-MAPPING.md` as `operator-placeholder` or `helm-placeholder`,
the workbook names the *category* of technology (e.g. "Approved Kafka
operator/distribution") but does not name a specific, enterprise-licensed
operator or Helm chart. Per the task constraints, this repository does
**not** invent or assume a company-specific operator.

## What `scripts/provision.sh` actually does for these Catalog IDs

For a request against a Catalog ID whose `implementation.method` is
`operator-placeholder` or `helm-placeholder`, provisioning still creates
the full governance scaffolding so the request is tracked and isolated:

1. Namespace (`base/namespace`) with the standard labels/annotations.
2. RBAC (`base/rbac`) -- owner RoleBinding, runtime ServiceAccount.
3. NetworkPolicy (`base/network-policy`) -- default-deny plus same-namespace.
4. ResourceQuota / LimitRange (`base/resource-quota`, `base/limit-range`).
5. A `ConfigMap` named `sandbox-service-request` recording the request
   intent (Catalog ID, requester, profile, requested storage size,
   timestamp) -- see `service-request-configmap.yaml` in this directory.

It then **stops** without deploying a workload, prints a clearly labeled
`IMPLEMENTATION_REQUIRED` banner naming the decision needed and the
candidate technologies from `config/catalog.yaml`
`implementation.candidateOperators` / `candidateCharts`, and exits with a
distinct status code (`70`, see `scripts/common.sh`) so calling automation
(Remedy, a future API) can tell "namespace reserved, workload pending
operator selection" apart from a hard failure.

## What the DevOps team must decide, per Catalog ID

See `docs/CATALOG-MAPPING.md` and the `implementation.decisionNeeded` /
`implementation.candidateOperators` fields in `config/catalog.yaml` for
each of: `DATA-SPARK`, `DATA-AIRFLOW`, `DATA-TRINO`, `DB-PG`, `DB-MYSQL`,
`DB-MONGO`, `DB-ELASTIC`, `INT-KAFKA`, `INT-MQ`.

For each one, the decision is:

1. **Select** a specific operator (OperatorHub-installable) or Helm chart.
2. **Certify** it against OpenShift's `restricted-v2` SCC and this
   repository's non-root/no-privileged-escalation baseline.
3. **License/entitle** it if it is not a pure community/OSS distribution
   (Governance: "Entitlement").
4. **Replace** `example-operator-cr.yaml` (or add a Helm `values.yaml`
   override) in the corresponding `catalog/<domain>/<id>/` directory with
   the real, working manifest for that operator/chart.
5. **Update** `config/catalog.yaml` `implementation.method` for that
   Catalog ID to `operator-cr` (or `helm-release`) once implemented, and
   remove the `IMPLEMENTATION_REQUIRED` status.
6. **Wire** `scripts/provision.sh`'s placeholder branch to instead apply
   the real CR / run `helm upgrade --install` for that Catalog ID.

## `example-operator-cr.yaml`

A generic, commented, **not applied to the cluster** illustration of the
shape a future CR takes once an operator is selected. It uses a
non-existent placeholder `apiVersion` on purpose so it can never be
mistaken for a real, working manifest if it is copy-pasted without reading
the comments.
