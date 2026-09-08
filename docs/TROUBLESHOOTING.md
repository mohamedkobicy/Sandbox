# Troubleshooting

First-line diagnostic reference. Start with:

```bash
scripts/health-check.sh --request-id <REQ_ID>
```

It automatically detects most of the issues below and points at the
relevant section here.

---

## ImagePullBackOff / ErrImagePull

**Symptoms:** Pod stuck in `ImagePullBackOff` or `ErrImagePull`;
`scripts/health-check.sh` flags it.

**Diagnostic commands:**
```bash
oc describe pod -n <namespace> <pod>
oc get events -n <namespace> --sort-by='.lastTimestamp' | grep -i pull
```

**Likely causes:**
- The namespace has no valid Quay pull secret linked
  (`config/registry.yaml` `registry.pullSecretName`).
- `config/registry.yaml` `registry.hostname` / `registry.organization`
  (or `QUAY_REGISTRY` / `QUAY_ORGANIZATION`) do not match where the image
  actually lives.
- The image tag/digest referenced by `config/catalog.yaml` was retired or
  never published for this Catalog ID.
- Network policy or a proxy is blocking egress to the registry (check
  `config/policies.yaml` `network.allowedEgressCIDRs`).

**Corrective actions:**
1. Confirm the pull secret exists and is linked:
   `oc get secret <pullSecretName> -n <namespace>` and
   `oc get serviceaccount sandbox-runtime -n <namespace> -o yaml | grep -A3 imagePullSecrets`.
2. Confirm the image reference: `oc get deployment <name> -n <namespace> -o jsonpath='{.spec.template.spec.containers[0].image}'`
   and compare against `scripts/common.sh::resolve_image_ref` output for
   that Catalog ID.
3. Confirm the image actually exists in Quay at that tag/digest.
4. Re-run `scripts/provision.sh` after fixing the above -- it is idempotent.

---

## CrashLoopBackOff

**Symptoms:** Pod restarts repeatedly; `scripts/health-check.sh` flags it.

**Diagnostic commands:**
```bash
oc logs -n <namespace> <pod> --previous
oc describe pod -n <namespace> <pod>
```

**Likely causes:**
- The workspace image's entrypoint expects a volume/config that isn't
  mounted (e.g. missing `--enable secrets`/`--enable git` when the
  workload's startup script expects them).
- Resource limits from the assigned profile
  (`config/profiles.yaml`) are too low for the workload's actual startup
  footprint.
- An application-level misconfiguration inside the image itself.

**Corrective actions:**
1. Read the previous container's logs first -- they usually show the
   actual failure before the restart.
2. If it's a resource limit issue, consider whether this Catalog ID's
   `profile` in `config/catalog.yaml` should move to a larger tier
   (change centrally, not per-request).
3. If the image itself is broken, this is an image-build issue -- route
   back to the image owner (`config/catalog.yaml` `owner` field).

---

## Pending (Pod)

**Symptoms:** Pod stuck in `Pending`.

**Diagnostic commands:**
```bash
oc describe pod -n <namespace> <pod>
oc get resourcequota -n <namespace>
oc get nodes
```

**Likely causes:**
- `ResourceQuota` exhausted in the namespace (see "Quota exceeded" below).
- No node has enough allocatable CPU/memory for the requested profile.
- GPU requested but no node advertises the configured
  `config/policies.yaml` `gpu.resourceName`.

**Corrective actions:**
1. Check the Events section of `oc describe pod` for the scheduler's
   stated reason -- it names the exact constraint that failed.
2. If it's cluster capacity, escalate to Infra; this is not something
   `provision.sh` can work around.
3. If it's GPU, see "GPU unavailable" below.

---

## PVC Pending

**Symptoms:** `PersistentVolumeClaim` stuck in `Pending`;
`scripts/health-check.sh` flags it.

**Diagnostic commands:**
```bash
oc describe pvc -n <namespace> <pvc>
oc get storageclass
```

**Likely causes:**
- `config/policies.yaml` `storage.defaultClass` (or `STORAGE_CLASS`) names
  a StorageClass that doesn't exist on this cluster.
- No default StorageClass is set and none was specified.
- The requested size exceeds what the StorageClass/backend can provision.

**Corrective actions:**
1. `oc get storageclass` to see what's actually available.
2. Either set `config/policies.yaml` `storage.defaultClass` to a real
   StorageClass name, or ensure the cluster has a StorageClass marked
   default (`storageclass.kubernetes.io/is-default-class: "true"`).
3. Re-run `scripts/provision.sh` -- PVC creation is idempotent.

---

## Route inaccessible

**Symptoms:** `oc get route` shows a host, but it doesn't resolve or
returns a connection error / TLS error.

**Diagnostic commands:**
```bash
oc get route -n <namespace> -o yaml
oc get route -n <namespace> <name> -o jsonpath='{.status.ingress[0].conditions}'
curl -kv https://<route-host>/
```

**Likely causes:**
- DNS for the cluster's wildcard domain isn't set up (see
  `DEFAULT_DOMAIN` / `docs/RUNBOOK.md` "DNS/Routes").
- Enterprise ingress/TLS policy overrides the `edge` termination this
  repository defaults to (Section 18) -- confirm with Network/Security.
- The backing Service has no Ready endpoints yet (pod still starting or
  crash-looping -- see above).

**Corrective actions:**
1. Confirm the Service has endpoints: `oc get endpoints -n <namespace> <name>`.
2. Confirm the Route's `status.ingress[].conditions` show `Admitted: True`.
3. If DNS resolution fails entirely, this is a cluster-level DNS/ingress
   configuration issue -- escalate to Infra, not a per-request fix.

---

## Permission / RBAC failures

**Symptoms:** `oc` commands inside the workspace (or `provision.sh` itself)
fail with `Forbidden`.

**Diagnostic commands:**
```bash
oc auth can-i <verb> <resource> -n <namespace> --as=<user>
oc get rolebinding -n <namespace>
oc describe clusterrole sandbox-workspace-edit
```

**Likely causes:**
- `scripts/deploy.sh` was never run on this cluster (the
  `sandbox-workspace-edit` ClusterRole doesn't exist yet).
- The owner's identity doesn't match `OWNER_SUBJECT_NAME` used at
  provisioning time (e.g. requested as an individual user but the Remedy
  identity is actually a group).
- The action being attempted is genuinely outside
  `base/rbac/cluster-role.yaml` (by design -- see `docs/SECURITY.md`).

**Corrective actions:**
1. Confirm the platform-level install: `scripts/deploy.sh` (idempotent,
   safe to re-run).
2. Confirm the RoleBinding subject matches: `oc get rolebinding
   sandbox-owner-binding -n <namespace> -o yaml`.
3. If the action is legitimately outside scope, this is a design
   decision (delegated, non-cluster-admin RBAC) -- do not widen
   `base/rbac/cluster-role.yaml` without a Security review.

---

## Quota exceeded

**Symptoms:** Pod/PVC creation fails with `exceeded quota`.

**Diagnostic commands:**
```bash
oc describe resourcequota sandbox-quota -n <namespace>
```

**Likely causes:**
- The namespace's `config/policies.yaml` `quota.*` defaults are too low
  for what this Catalog ID's profile actually needs (e.g. a Large-profile
  Platform Service alongside other workloads in the same namespace).

**Corrective actions:**
1. Confirm which dimension is exhausted (`oc describe resourcequota`
   shows used vs. hard limits per resource).
2. If it's a systemic sizing issue, adjust `config/policies.yaml`
   `quota.*` (affects all future namespaces) rather than patching one
   namespace's ResourceQuota by hand.

---

## SCC / security-context failures

**Symptoms:** Pod creation is rejected with an SCC-related admission
error (e.g. "unable to validate against any security context
constraint").

**Diagnostic commands:**
```bash
oc get pod -n <namespace> <pod> -o yaml | grep -A10 securityContext
oc get scc restricted-v2 -o yaml
oc describe pod -n <namespace> <pod>
```

**Likely causes:**
- The container image itself requires root or a fixed UID that
  `restricted-v2` disallows (an image-build problem, not a manifest
  problem -- every template in this repository already requests
  `runAsNonRoot: true` with no fixed UID).
- A future catalog change accidentally requested `privileged: true`,
  `hostNetwork`, `hostPID`, or `hostPath` (all forbidden by
  `config/policies.yaml` `security.forbid*` and CI's prohibited-pattern
  check -- see `docs/RUNBOOK.md` "CI/CD Recommendations").

**Corrective actions:**
1. If it's the image, route back to the image owner -- the fix is
   rebuilding the image to run as an arbitrary non-root UID.
2. If it's a manifest regression, `git blame`/diff `templates/*/base` to
   find what changed and revert it; this should never legitimately need
   an SCC beyond `restricted-v2`.

---

## GPU unavailable

**Symptoms:** `scripts/provision.sh --gpu true` fails with
`EXIT_GPU_UNAVAILABLE`, or the pod stays `Pending` referencing a GPU
resource.

**Diagnostic commands:**
```bash
oc get nodes -o jsonpath='{.items[*].status.allocatable}' | grep -o '"nvidia.com/gpu":"[0-9]*"'
oc get pods -n openshift-nfd -o wide 2>/dev/null   # Node Feature Discovery, if used
oc get csv -A | grep -i gpu                         # GPU Operator, if installed via OLM
```

**Likely causes:**
- The GPU Operator (or equivalent device plugin) isn't installed on this
  cluster.
- `config/policies.yaml` `gpu.resourceName` doesn't match the accelerator
  vendor actually installed (it defaults to `nvidia.com/gpu` -- confirm
  this against your cluster).
- No node currently has a free GPU to schedule onto.

**Corrective actions:**
1. Confirm the real resource name with Infra and update
   `config/policies.yaml` `gpu.resourceName` if it doesn't match.
2. If the GPU Operator genuinely isn't installed, this is a cluster
   capability gap -- do not attempt to work around it in
   `scripts/provision.sh`; escalate to Infra.
3. Retry without `--gpu true` if GPU is genuinely optional for the
   requester's use case.

---

## Operator unavailable

**Symptoms:** Provisioning a Platform Service Catalog ID
(`DB-PG`, `INT-KAFKA`, `DATA-SPARK`, etc.) exits with
`EXIT_IMPLEMENTATION_REQUIRED` (70), or a downstream `INT-KCONNECT`
request fails because its `--config-ref` ConfigMap doesn't exist.

**This is not a bug** -- see `docs/CATALOG-MAPPING.md`
"IMPLEMENTATION_REQUIRED summary". The namespace and its governance
scaffolding were still created; the workload itself is pending an
enterprise operator/Helm chart selection.

**Corrective actions:**
1. Read `catalog/<domain>/<id>/README.md` for the specific decision
   needed and candidate technologies.
2. Escalate to Infra/DevOps to make that selection; this is an
   organizational decision, not something `scripts/provision.sh` can
   infer.
3. For `INT-KCONNECT` specifically: confirm `INT-KAFKA` (or an equivalent
   enterprise Kafka cluster) is reachable and its bootstrap-servers
   ConfigMap exists before retrying with `--config-ref`.

---

## Quay authentication

**Symptoms:** `ImagePullBackOff` specifically with an `unauthorized` or
`401`/`403` reason in `oc describe pod`.

**Diagnostic commands:**
```bash
oc get secret <pullSecretName> -n <namespace> -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
oc describe pod -n <namespace> <pod> | grep -A5 -i "failed to pull"
```

**Likely causes:**
- The pull secret's credential expired or was rotated in Quay without
  updating the OpenShift Secret.
- The wrong robot account is linked (read-only "sandbox-puller" vs. a
  per-namespace scoped account -- see `docs/SECURITY.md` "Quay
  permissions", still `IMPLEMENTATION_REQUIRED`).

**Corrective actions:**
1. Confirm the credential is still valid directly against Quay.
2. Rotate/recreate the OpenShift Secret and re-link it to the
   `sandbox-runtime` ServiceAccount:
   `oc secrets link sandbox-runtime <pullSecretName> --for=pull -n <namespace>`.

---

## DNS problems

**Symptoms:** Route hosts don't resolve; in-cluster DNS lookups fail from
inside a workspace pod.

**Diagnostic commands:**
```bash
oc exec -n <namespace> <pod> -- getent hosts kubernetes.default.svc.cluster.local
oc get pods -n openshift-dns
oc get networkpolicy -n <namespace>
```

**Likely causes:**
- `base/network-policy/20-allow-dns-egress.yaml` targets the
  `openshift-dns` namespace label -- confirm this cluster's DNS operator
  actually runs there with that label (Section 9 / `docs/RUNBOOK.md`
  "Prerequisites"). A non-standard DNS setup needs this policy adjusted.
- External DNS (for Route hosts) is a cluster/enterprise DNS
  configuration issue, not something this repository manages.

**Corrective actions:**
1. Confirm the DNS NetworkPolicy is present and matches the cluster's
   actual DNS namespace/labels.
2. For external Route DNS, escalate to the Network team -- out of scope
   for per-sandbox troubleshooting.

---

## Unschedulable pods

**Symptoms:** `FailedScheduling` events; `scripts/health-check.sh` flags it.

**Diagnostic commands:**
```bash
oc describe pod -n <namespace> <pod>
oc get nodes -o wide
oc describe nodes | grep -A5 Taints
```

**Likely causes:** insufficient cluster capacity, taints without a
matching toleration, or (for GPU workloads) no GPU-capable node
available.

**Corrective actions:** escalate to Infra for capacity/taint
configuration; not resolvable from the sandbox namespace side.

---

## Failed probes

**Symptoms:** `Unhealthy` events, readiness/liveness probe failures
(mostly relevant to `service-template` workloads like `WEB-NGINX`).

**Diagnostic commands:**
```bash
oc describe pod -n <namespace> <pod>
oc logs -n <namespace> <pod>
```

**Likely causes:** the container takes longer to become ready than the
probe's `initialDelaySeconds`, or the application isn't actually
listening on `SERVICE_PORT`.

**Corrective actions:** confirm the port the application binds inside
the image matches `config/catalog.yaml` `network.route.port` for that
Catalog ID; if the image just needs more startup time, that's a template
tuning change in `templates/service/base/deployment.yaml`, not a
per-request workaround.
