# Catalog Domain: Integration

This directory documents the Catalog IDs in this domain and how each one is implemented. Full machine-readable detail lives in `config/catalog.yaml`; this file is the human-readable index. See `docs/CATALOG-MAPPING.md` for the complete cross-catalog table.

| Catalog ID | Offering | Type | Implementation | Approval | Priority |
|---|---|---|---|---|---|
| `INT-API` | API Development | workspace | workspace-template | auto | P1 |
| `INT-KAFKA` | Kafka | platform-service | operator-placeholder | review | P1 |
| `INT-KCONNECT` | Kafka Connect | platform-service | statefulset-template | review | P2 |
| `INT-MQ` | Message Broker | platform-service | operator-placeholder | review | P2 |

## Entries requiring an enterprise implementation decision

- **`INT-KAFKA`** (Kafka) -- see `catalog/integration/int-kafka/README.md`
- **`INT-MQ`** (Message Broker) -- see `catalog/integration/int-mq/README.md`

