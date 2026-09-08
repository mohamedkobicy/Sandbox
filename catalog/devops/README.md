# Catalog Domain: DevOps & Platform

This directory documents the Catalog IDs in this domain and how each one is implemented. Full machine-readable detail lives in `config/catalog.yaml`; this file is the human-readable index. See `docs/CATALOG-MAPPING.md` for the complete cross-catalog table.

| Catalog ID | Offering | Type | Implementation | Approval | Priority |
|---|---|---|---|---|---|
| `OPS-ANSIBLE` | Ansible Automation | workspace | workspace-template | review | P1 |
| `OPS-CICD` | CI/CD Builder | workspace | workspace-template | review | P1 |
| `OPS-HELM` | Helm/Kustomize Dev | workspace | workspace-template | auto | P1 |
| `OPS-IAC` | IaC Tools | workspace | workspace-template | review | P1 |
| `OPS-OC` | OpenShift Tools | workspace | workspace-template | review | P0 |

## `OPS-OC` note

`OPS-OC` (Notes: "No cluster-admin") is the only Catalog ID in this
repository whose `serviceAccount.automountToken` is `true` in
`config/catalog.yaml` -- it is the only workspace whose entire purpose
requires calling the OpenShift API from inside the pod (`oc`, `kubectl`,
Helm, Kustomize). It still only ever gets the same namespace-scoped
`RoleBinding` to `sandbox-workspace-edit` as every other workspace --
never `cluster-admin`, never a `ClusterRoleBinding`. See
`docs/SECURITY.md` "Least privilege".

