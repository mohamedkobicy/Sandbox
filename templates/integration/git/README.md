# SHARED-GIT: Git Integration

**Catalog type:** `integration` (Section 3 "Shared Capabilities") --
**not** a standalone Deployment. Git integration is a runtime capability
layered onto a Workspace (e.g. `DEV-PY`, `AI-FULL`) rather than something
provisioned by itself.

## How it is applied

`scripts/provision.sh --enable git ...` (or a request whose primary
`--catalog` is `SHARED-GIT`, which provisions the namespace scaffolding
plus this component only, no workload) renders `git-config-configmap.yaml`
into the sandbox namespace and mounts it into the workspace container at
`/etc/sandbox/git/config`.

## What it contains

Only **non-secret** enterprise Git configuration: trusted CA bundle
reference, allowed remotes/hosts, and any `.gitconfig` fragment needed for
enterprise repositories (e.g. `http.sslCAInfo`, `url.insteadOf` rewrites
for internal mirrors). It never contains credentials.

## Credentials

Authentication (SSH deploy key, HTTPS PAT/token, or a GitOps app
credential) is supplied exclusively through `templates/integration/secrets`
as a separate OpenShift Secret, mounted read-only, and referenced by the
enterprise Git host's normal credential-helper mechanism -- never
committed to this repository, never placed in this ConfigMap, and never
passed as a `provision.sh` command-line argument (Governance: "No embedded
credentials").

## IMPLEMENTATION_REQUIRED

The DevOps team must supply the real enterprise Git host(s), CA bundle,
and any URL rewrite rules in `git-config-configmap.yaml` before this
component is functional. Placeholders below are illustrative only.
