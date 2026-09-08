# Enterprise Sandbox Catalog -- OpenShift Provisioning Framework

Turns a BMC Remedy service catalog request -- a **Catalog ID** and a
handful of policy-bounded parameters -- into a governed, isolated
OpenShift sandbox namespace running an approved Quay image, operator, or
template. Requesters never submit an arbitrary container image URL.

```
Remedy Service Request -> Catalog ID -> scripts/provision.sh -> OpenShift
    -> Approved Quay Image / Operator / Template -> Sandbox Namespace
```

Source of truth for what can be provisioned: `Sandbox_Image_Catalog.xlsx`
(the `Catalog`, `Remedy Catalog View`, `Family Summary`, and `Governance`
sheets), transcribed into `config/catalog.yaml` -- see
`docs/CATALOG-MAPPING.md` for the full 49-entry mapping and a field-by-
field reconciliation report against the workbook.

## Start here

| If you are... | Read |
|---|---|
| Deploying this framework for the first time | `docs/RUNBOOK.md` "Initial Installation" |
| Reviewing the design | `docs/ARCHITECTURE.md` |
| Doing a security review | `docs/SECURITY.md` |
| Looking up how a specific Catalog ID is implemented | `docs/CATALOG-MAPPING.md` |
| Debugging a broken sandbox | `docs/TROUBLESHOOTING.md`, then `scripts/health-check.sh` |
| Integrating Remedy | `examples/remedy-request.json`, `docs/RUNBOOK.md` "Provision a Sandbox" |
| Setting up CI | `docs/CI-CD.md` |

## Quick start

```bash
oc login https://api.<cluster-domain>:6443

scripts/validate.sh          # validate config/ (no cluster writes)
scripts/deploy.sh             # one-time framework install (platform admin)

scripts/provision.sh \
  --catalog DEV-PY --request-id REQ000123 --owner team-data

scripts/health-check.sh --request-id REQ000123

scripts/delete-sandbox.sh --request-id REQ000123
```

## Repository layout

```
openshift-sandbox-catalog/
├── config/            Central machine-readable catalog, profiles, registry, policy config
├── base/              Namespace/RBAC/NetworkPolicy/ResourceQuota/LimitRange envsubst templates
├── catalog/            Per-domain documentation + genuine overrides (operator placeholders, etc.)
├── templates/          Reusable workload templates: workspace, service, platform-service, integration
├── scripts/            deploy.sh, provision.sh, delete-sandbox.sh, validate.sh, health-check.sh, common.sh
├── examples/           Sample Remedy and manual request payloads
├── docs/                RUNBOOK, ARCHITECTURE, CATALOG-MAPPING, SECURITY, TROUBLESHOOTING
└── tests/               validate-yaml.sh (CI, no cluster needed), smoke-test.sh (real cluster)
```

## Design principles this framework enforces

(See `docs/ARCHITECTURE.md` and `docs/SECURITY.md` for detail on each.)

- **Only approved images, only from the internal Quay registry.** No
  requester-supplied image URL is ever accepted.
- **No arbitrary YAML, ServiceAccount, SCC, or cluster role from a
  requester.** `scripts/provision.sh` accepts a Catalog ID and a fixed,
  policy-validated parameter set; everything else comes from
  `config/*.yaml`.
- **No `cluster-admin`, anywhere, for any sandbox owner** -- namespace-
  scoped `RoleBinding`s only.
- **No embedded credentials.** Secrets are pre-created out-of-band and
  referenced by name; never generated, stored, or logged by this
  repository.
- **Non-root, `restricted-v2`-compatible containers** -- no privileged
  workloads, no fixed UIDs, no `hostNetwork`/`hostPID`/`hostPath` without
  a documented exception (none exist today).
- **Databases, Kafka, Spark, Airflow, and similar platform services are
  never raw Deployments** -- they use StatefulSets (where a direct
  approved image is safe to run that way), or a documented
  operator/Helm placeholder pending an enterprise decision (see
  `docs/CATALOG-MAPPING.md` "IMPLEMENTATION_REQUIRED summary" -- 9
  Catalog IDs today).
- **Auto vs. Review approval**, matching the workbook exactly, with the
  CLI's `--approved true` flag explicitly documented as plumbing, not a
  security control (`docs/SECURITY.md` "Approval trust boundary").
- **GPU is opt-in only** (`--gpu true`), validated against both the
  catalog entry and actual cluster capacity -- never auto-requested.
- **Idempotent, `oc apply`-based automation** with `--dry-run` support
  throughout.

## Requirements you must supply before production use

None of the following are guessed or hardcoded -- see
`docs/RUNBOOK.md` "Configuration" for exactly where each one goes:

- Real internal Quay hostname and pull-secret/robot-account strategy
  (`config/registry.yaml`).
- A StorageClass name, or confirmation that a cluster default exists
  (`config/policies.yaml` `storage.defaultClass`).
- Real internal egress CIDRs for controlled egress
  (`config/policies.yaml` `network.allowedEgressCIDRs` -- empty today,
  fail-closed).
- The real GPU resource name if it differs from `nvidia.com/gpu`
  (`config/policies.yaml` `gpu.resourceName`).
- Operator/Helm chart selections for the 9 `IMPLEMENTATION_REQUIRED`
  Platform Service Catalog IDs (`docs/CATALOG-MAPPING.md`).
- A real trusted-issuer identity for the Approval=Review workflow once
  this sits behind an API (`docs/SECURITY.md` "Approval trust
  boundary").
