# CI/CD Recommendations (Section 28)

Optional pipeline design for this repository. None of these tools are
assumed to already exist in your organization -- treat this as a starting
recommendation, not a requirement, and substitute your organization's
standard equivalents where they differ.

## What to validate on every change

| Check | Suggested tool | Command |
|---|---|---|
| YAML syntax | Python `yaml` (already used by `tests/validate-yaml.sh`) | `tests/validate-yaml.sh --skip-oc` |
| Shell script lint | [ShellCheck](https://www.shellcheck.net/) | `shellcheck -x scripts/*.sh tests/*.sh` |
| Catalog/config structural consistency | This repo's own `scripts/validate.sh` | `scripts/validate.sh` |
| Kubernetes/OpenShift schema validation | `oc apply --dry-run=server` (needs a real or ephemeral test cluster), or [`kubeconform`](https://github.com/yannh/kubeconform) with the OpenShift CRD schema set for offline checks | `tests/validate-yaml.sh` (runs `--dry-run=client` when `oc` + login are available) |
| Prohibited privileged settings | `grep`/`yq` assertions, or a policy engine like [`conftest`](https://www.conftest.dev/)/OPA if already adopted | See "Prohibited-pattern check" below |
| Prohibited image registries | Same as above -- assert every rendered `image:` matches `config/registry.yaml` `registry.hostname` | See below |
| Secrets accidentally committed | [`gitleaks`](https://github.com/gitleaks/gitleaks) or your organization's standard secret scanner | `gitleaks detect --source . --no-git` |
| Catalog/image mapping consistency | This repo's own reconciliation logic (`docs/CATALOG-MAPPING.md` was generated this way) | Re-run the generator against a refreshed workbook and diff |

## Prohibited-pattern check (no new tool required)

A simple `grep`-based CI gate that needs nothing beyond what's already in
this repository:

```bash
# Fail if any manifest requests privileged mode, host namespaces, or a
# fixed non-root-safe UID outside the documented defaults.
! grep -RIn --include='*.yaml' -E 'privileged:\s*true|hostNetwork:\s*true|hostPID:\s*true|hostPath:' base/ templates/ catalog/

# Fail if any manifest hardcodes a registry hostname other than the
# envsubst placeholder or the documented example.
! grep -RIn --include='*.yaml' -E '(docker\.io|ghcr\.io|quay\.io)/' base/ templates/ catalog/
```

## Suggested pipeline stages

1. **Lint** -- ShellCheck + YAML syntax (`tests/validate-yaml.sh --skip-oc`).
2. **Validate** -- `scripts/validate.sh` (catalog/profile/policy
   consistency; runs without cluster access unless `--server-side` is
   passed).
3. **Secret scan** -- `gitleaks` or equivalent, on every PR.
4. **(Optional, needs a test cluster) Server-side dry-run** --
   `tests/validate-yaml.sh` with `oc` logged in against a disposable
   test/dev cluster, or `tests/smoke-test.sh` for a full provision/
   health-check/delete cycle against a real Catalog ID.
5. **Prohibited-pattern gate** -- the `grep` checks above, or a
   `conftest`/OPA policy set if your organization already runs one.

## What this repository does NOT assume

- No specific CI platform (GitHub Actions, GitLab CI, Jenkins, Tekton) is
  assumed -- the checks above are plain scripts that run identically
  under any of them.
- No policy-engine dependency (OPA/Conftest, Kyverno) is required; the
  `grep`-based gate is deliberately dependency-free. Adopt a policy
  engine if your organization already standardizes on one -- it is a
  strict improvement over `grep`, not a replacement for a different
  control.
- `tests/smoke-test.sh` requires a real (ideally disposable/dev)
  OpenShift cluster and should not run against production on every PR --
  gate it behind a manual trigger or a scheduled job.
