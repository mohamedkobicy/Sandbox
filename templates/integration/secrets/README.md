# SHARED-SECRETS: Secrets Integration

**Catalog type:** `integration` -- **not** a standalone Deployment.
`Approval: Review` in the workbook, reflecting that secret access always
needs a human/security decision, not just automatic namespace scaffolding.

## Rule (Governance: "No embedded credentials")

No AI provider key (Claude, OpenAI, or any other LLM API key), Git token,
database credential, or certificate is ever:

- baked into a container image,
- committed to this Git repository,
- placed in a ConfigMap,
- or passed as a `scripts/provision.sh` command-line argument.

## How it is applied

`scripts/provision.sh --enable secrets --secret-ref <name> ...` does **not**
create secret material. It:

1. Validates that an OpenShift Secret named `<name>` (created out-of-band,
   by the owner or an enterprise Vault/External Secrets integration)
   already exists in the target namespace, or fails with a clear error.
2. Renders `secret-mount-patch.yaml`, which mounts that pre-existing Secret
   into the workspace container at `/var/run/secrets/sandbox/<name>` (or
   injects selected keys as environment variables via `envFrom`, per the
   catalog entry's documented needs).

Never does `provision.sh` (or any script in this repository) print, log,
or persist secret *values* -- only the Secret's *name* is ever handled.

## Recommended production path

- **OpenShift Secret** (used today): owner or an enterprise process
  pre-creates the Secret in the sandbox namespace; provisioning only
  references it by name.
- **External Secrets Operator / enterprise Vault integration** (future,
  approved): a `SecretStore`/`ExternalSecret`-shaped resource syncs the
  real secret from the enterprise vault into the namespace automatically.
  Not implemented in this repository -- flagged as
  `IMPLEMENTATION_REQUIRED` pending a Security-approved Vault integration.

## AI provider keys specifically

`AI-AGENT` and `AI-LLMTOOLS` (Notes: "No API keys embedded" /
"Provider credentials injected at runtime") use exactly this mechanism:
the requester supplies `--secret-ref <preexisting-secret>` referencing a
Secret they created (or that Security provisioned for them) containing
their Claude/OpenAI/etc. key, and it is mounted at runtime only.
