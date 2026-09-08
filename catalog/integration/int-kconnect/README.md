# `INT-KCONNECT` -- Kafka Connect

**Implementation:** `statefulset-template` (direct approved image
`sandbox/integration/kafka-connect`, `templates/platform-service/base/statefulset`)
-- unlike most Platform Service entries, this one ships as a concrete image
rather than requiring an operator, so it deploys the same way DB-VALKEY does.

## Dependency: `INT-KAFKA`

Kafka Connect is only useful once it can reach a Kafka bootstrap endpoint.
It does **not** bundle or provision its own Kafka cluster. Before
provisioning `INT-KCONNECT`:

1. An `INT-KAFKA` platform service must exist (either in the same sandbox
   namespace, or a shared/enterprise Kafka cluster the requester is
   authorized to use).
2. The requester supplies the bootstrap servers via
   `--config-ref <configmap-name>` to `scripts/provision.sh`, referencing a
   pre-created `ConfigMap` with a `bootstrapServers` key.
3. `scripts/provision.sh` validates that ConfigMap exists in the target
   namespace before rendering `statefulset.yaml`'s `${EXTRA_ENV_BLOCK}` with
   a `KAFKA_BOOTSTRAP_SERVERS` environment variable sourced from it
   (`configMapKeyRef`) -- never a hardcoded or inline value.

Since `INT-KAFKA` itself is `operator-placeholder`
(`IMPLEMENTATION_REQUIRED`, see `catalog/integration/int-kafka/README.md`),
`INT-KCONNECT` is functionally blocked in a fresh environment until that
decision is made and a real Kafka cluster is reachable. The
namespace/RBAC/quota scaffolding for `INT-KCONNECT` still provisions
normally.
