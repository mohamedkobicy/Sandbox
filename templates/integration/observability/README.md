# SHARED-OBS: Observability Integration

**Catalog type:** `integration` -- **not** a standalone Deployment.
Notes: "Prefer shared platform capability."

## How it is applied

`scripts/provision.sh --enable observability ...` renders
`observability-annotations-patch.yaml`, which adds the annotations/labels
the enterprise's existing OpenShift observability stack (cluster logging,
cluster monitoring / user-workload monitoring, and/or a distributed
tracing operator) uses to auto-discover workloads for log/metric/trace
collection.

This repository does **not** deploy a logging/metrics/tracing agent or
sidecar itself -- it assumes an enterprise-managed, cluster-wide
observability platform is already collecting from every namespace (the
standard OpenShift pattern), and only adds the labels/annotations needed
to opt a sandbox workload into any *additional*, non-default scraping
(e.g. a custom Prometheus `ServiceMonitor` selector).

## IMPLEMENTATION_REQUIRED

Confirm with the Infra/Observability team:

1. Whether cluster logging and user-workload monitoring are enabled
   cluster-wide (in which case no per-namespace action is needed at all).
2. The exact label/annotation keys their `ServiceMonitor`/`PodMonitor`
   selectors expect, if additional metrics scraping must be opted in
   per namespace.
3. Whether sandbox namespaces should be excluded from any log/metric
   retention SLA that applies to production namespaces.
