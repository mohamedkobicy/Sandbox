# Catalog Domain: Security

This directory documents the Catalog IDs in this domain and how each one is implemented. Full machine-readable detail lives in `config/catalog.yaml`; this file is the human-readable index. See `docs/CATALOG-MAPPING.md` for the complete cross-catalog table.

| Catalog ID | Offering | Type | Implementation | Approval | Priority |
|---|---|---|---|---|---|
| `SEC-NET` | Network Diagnostic | workspace | workspace-template | review | P1 |
| `SEC-SAST` | Secure Code Analysis | workspace | workspace-template | review | P1 |

## `SEC-NET` note

Notes column: "Restricted capabilities". `SEC-NET` uses the same
`templates/workspace/base` shape as every other workspace -- it does
**not** get `NET_ADMIN`, `NET_RAW`, or any capability added back
(`capabilities.drop: ["ALL"]`, `config/policies.yaml`
`security.allowedCapabilitiesAdd: []` apply identically here). Its
network diagnostic tooling (curl/dig/openssl/traceroute-equivalents) must
work within an unprivileged, capability-dropped container; anything
requiring an added capability is a documented security exception that
does not exist in this repository today, and would need explicit
Security sign-off before being added for this one Catalog ID.

## `SEC-SAST` note

Notes column: "Tool licensing may apply". Confirm licensing/entitlement
for any non-OSS SAST/SCA/secret-scanning CLI bundled into this image
before publication (Governance: "Entitlement") -- tracked as an
image-build-time concern, not something `scripts/provision.sh` validates
at request time.

