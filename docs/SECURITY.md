# Security

This document explains how the Enterprise Sandbox Catalog enforces the
Governance sheet's requirements and is written for both the DevOps team
operating it and the Security team reviewing it.

## Least privilege

No component in this repository requests, grants, or assumes
`cluster-admin`, or any cluster-scoped write access beyond what
`scripts/deploy.sh` needs once (creating the `sandbox-workspace-edit`
ClusterRole and the control-plane namespace -- a platform-admin action,
distinct from anything a sandbox owner can trigger). Every sandbox
namespace's RBAC is a `RoleBinding`, which by definition cannot grant
anything outside that one namespace (`base/rbac/role-binding.yaml`).

`OPS-OC` (Notes: "No cluster-admin") gets exactly the same
`sandbox-workspace-edit` binding as every other workspace -- "cluster/
project operations within delegated RBAC" means operating on its *own*
namespace via `oc`/`kubectl`/Helm/Kustomize, not cluster-wide access. It is
the only Catalog ID whose ServiceAccount token is mounted
(`serviceAccount.automountToken: true` in `config/catalog.yaml`), because
it is the only one whose entire purpose requires calling the API server
from inside the pod.

## SecurityContextConstraints / `restricted-v2` compatibility

Every container spec in `templates/*/base` sets:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  runAsNonRoot: true
  capabilities:
    drop: ["ALL"]
```

with pod-level `runAsNonRoot: true` and `seccompProfile: RuntimeDefault`.
No UID is fixed (`config/policies.yaml` `security.allowFixedUID: false`):
OpenShift assigns a UID from the namespace's allocated range, which is
what `restricted-v2` (the default SCC on any recent OpenShift version)
expects. This repository's manifests never request `hostNetwork`,
`hostPID`, or `hostPath`, and never set `privileged: true`
(`config/policies.yaml` `security.forbid*`) -- no Catalog ID in the
workbook documents an exception that would require one.

Container **images** must independently support running as an arbitrary
non-root UID (writable directories owned by the right group, no
root-only listen ports, etc.). That is an image-build-time requirement
enforced during the enterprise image promotion pipeline
(`config/registry.yaml` "Image promotion process"), not something the
Deployment spec alone can guarantee -- confirm each approved image has been
built and tested against `restricted-v2` before publication.

## Non-root containers

See above -- enforced at both the pod (`runAsNonRoot: true`) and container
(`securityContext.runAsNonRoot: true`, `allowPrivilegeEscalation: false`)
level in every template.

## Capabilities

`capabilities.drop: ["ALL"]` on every container; `config/policies.yaml`
`security.allowedCapabilitiesAdd: []` -- no template adds any capability
back. If a future Catalog ID genuinely needs one (e.g. `NET_RAW` for a
network diagnostic tool), that is a **documented security exception**,
reviewed by Security, added explicitly to that one Catalog ID's rendering
path -- never a blanket capability grant.

## Secrets

**No secret material is ever committed to this repository, baked into an
image, placed in a ConfigMap, or passed as a command-line argument.**
Concretely:

- `config/*.yaml` contain no credentials -- only hostnames, organization
  names, and policy values.
- `scripts/provision.sh` never accepts a secret *value* as a parameter,
  only a secret *reference* (`--secret-ref <existing-secret-name>`), and
  fails closed if that Secret does not already exist in the target
  namespace (Governance: "No embedded credentials").
- `templates/integration/secrets` documents the mount mechanism; it
  contains no example credential, real or fake.
- AI provider keys (Claude, OpenAI, or any other LLM API key) for
  `AI-AGENT` / `AI-LLMTOOLS` follow exactly this path -- injected at
  runtime from a pre-created Secret, never a default, never embedded.
- Git credentials (`SHARED-GIT`), database credentials (`DB-*`), and
  certificates all follow the same rule: configuration (hostnames, CA
  bundles, connection parameters) may live in a ConfigMap;
  authentication material never does.

### Approval trust boundary

`scripts/provision.sh --approved true` is a **plumbing** flag, not a
**security** control. It exists so this repository has something to
gate on today, before a real workflow-identity integration exists. In
production:

- The party invoking `provision.sh` (a Remedy integration service, a
  future HTTP API) must independently verify that the request was, in
  fact, approved by the correct human/workflow *before* it ever sets
  `--approved true` -- not trust that the caller wouldn't lie.
- `config/policies.yaml` `approval.review.trustedIssuers` names this gap
  explicitly (`IMPLEMENTATION_REQUIRED`): identify the real
  Remedy/workflow service identity (a mTLS client cert, an OIDC client, a
  signed token) and verify it server-side once this moves behind an API,
  rather than trusting a CLI flag from whoever can execute the script.
- Until that integration exists, `--approved true` should only ever be
  set by a human DevOps engineer who has personally confirmed the
  upstream approval, never automated end-to-end from an unauthenticated
  or loosely authenticated source.

## Image provenance, vulnerability scanning, immutability

Covered in depth in `docs/ARCHITECTURE.md` "Image Supply Chain" and
`config/registry.yaml`. Summary of the enforcement points that exist
today vs. what remains organizational process:

| Control | Enforced by |
|---|---|
| No arbitrary image URL from a requester | `scripts/provision.sh` only ever accepts a Catalog ID; `resolve_image_ref()` builds the reference from `config/catalog.yaml` + `config/registry.yaml`, never from caller input |
| Only the configured registry/organization | `config/registry.yaml` `registry.hostname` / `registry.organization`; `config/policies.yaml` `images.allowedRegistryHostnames` |
| Digest-pinned, immutable deployment | `resolve_image_ref()` prefers `image.digest` when set; `config/policies.yaml` `images.requireDigestInProduction` is the cutover switch (currently `false` while the catalog is bootstrapping) |
| Vulnerability/malware scanning before publication | **Organizational process**, external to this repository -- `config/policies.yaml` `scanning.required: true` records the requirement; the enterprise scanning platform (Clair-on-Quay or equivalent) must gate what ever reaches the `sandbox` organization in Quay |
| Licensing/entitlement for commercial components | **Organizational process** -- flagged per Catalog ID via `implementation.decisionNeeded` (e.g. `DB-MONGO`) |

## RBAC

Covered under "Least privilege" above. Summary: namespace-scoped
`RoleBinding`s only, one cluster-scoped `ClusterRole` (never bound
cluster-wide), no self-service RBAC or SCC changes granted to any
sandbox owner (`base/rbac/cluster-role.yaml` explicitly excludes
`rbac.authorization.k8s.io/*` and
`security.openshift.io/securitycontextconstraints`).

## NetworkPolicy

Deny-by-default with narrow exceptions -- see `docs/ARCHITECTURE.md`
"Isolation model" and the files in `base/network-policy/`. Controlled
egress (`40-allow-egress-controlled.yaml`) is skipped entirely, not
opened wide, until the Network/Security team supplies real CIDRs in
`config/policies.yaml` `network.allowedEgressCIDRs` -- fail-closed, never
fail-open.

## Namespace isolation

One namespace per request; RBAC, NetworkPolicy, ResourceQuota, and
LimitRange are all namespace-scoped and rendered per-request. Nothing in
this design allows one sandbox to reach into another's namespace, and
`scripts/delete-sandbox.sh` cannot act on a namespace outside this
automation's management (see below).

## Auditability

- Every namespace carries `sandbox.gosi/*` labels/annotations tracing it
  back to a Catalog ID, request ID, owner, creation time, and expiry
  (Section 12) -- never sensitive data.
- `scripts/delete-sandbox.sh` logs a structured audit line (catalog,
  owner, request ID, namespace, timestamp) on every deletion.
- `docs/RUNBOOK.md` "Audit" describes the end-to-end trace from a Remedy
  request ID to a running deployment and back.

## Supply-chain security

Covered under "Image provenance" above and `docs/ARCHITECTURE.md`. The
key structural control this repository provides is that **the deployment
path only ever accepts a Catalog ID**, never an image reference -- so even
a compromised or careless Remedy integration cannot cause an arbitrary
image to be pulled into a sandbox namespace; it can, at most, request a
Catalog ID that was never intended to be exposed (mitigated by the
`remedySelectable` check and server-side Catalog ID validation).

## Quay permissions

`config/registry.yaml` flags this as `IMPLEMENTATION_REQUIRED`: decide
whether sandbox namespaces share one read-only "sandbox-puller" Quay
robot account, or get per-namespace scoped robot accounts (stronger
isolation, more automation to build). Either way, the credential itself
is never stored in this repository -- only the OpenShift `Secret` *name*
(`config/registry.yaml` `registry.pullSecretName`) that must already
exist or be linked in each sandbox namespace.

## What this repository deliberately does NOT do

- It does not generate, store, or transmit any real secret value.
- It does not grant `cluster-admin`, a `ClusterRoleBinding`, or SCC
  escalation to any sandbox owner.
- It does not accept an image URL, registry, ServiceAccount, SCC,
  arbitrary environment variable set, or host mount from a requester.
- It does not treat a CLI approval flag as a substitute for real
  workflow-identity verification in production.
- It does not invent a specific commercial operator/product for the
  Catalog IDs marked `IMPLEMENTATION_REQUIRED` -- that decision, including
  its security review, belongs to the DevOps/Security teams.
