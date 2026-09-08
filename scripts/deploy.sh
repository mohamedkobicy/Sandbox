#!/usr/bin/env bash
# =============================================================================
# scripts/deploy.sh -- install/update the Enterprise Sandbox Catalog
#                       provisioning FRAMEWORK itself (cluster-scoped and
#                       control-plane resources). Run once per cluster by a
#                       platform admin, and again whenever base/rbac or
#                       config/*.yaml change.
#
# This script does NOT provision an individual sandbox -- that is
# scripts/provision.sh. deploy.sh only:
#   1. Validates the framework configuration (scripts/validate.sh).
#   2. Applies the cluster-scoped sandbox-workspace-edit ClusterRole (never
#      cluster-admin -- see base/rbac/cluster-role.yaml).
#   3. Creates/updates a control-plane namespace holding a mirror of
#      config/*.yaml as ConfigMaps, for visibility and for future
#      Ansible/API consumers that prefer reading from the cluster.
#
# Idempotent: safe to re-run; uses `oc apply` throughout.
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

CONTROL_NAMESPACE="sandbox-system"
DRY_RUN="false"

usage() {
  cat <<'EOF'
Usage: deploy.sh [--control-namespace sandbox-system] [--dry-run]

Installs/updates the sandbox provisioning framework:
  - base/rbac/cluster-role.yaml (cluster-scoped, never cluster-admin)
  - a control-plane namespace mirroring config/*.yaml as ConfigMaps

Requires: cluster permissions to create ClusterRoles and Namespaces
(a platform/cluster admin action -- distinct from the namespace-scoped
permissions every sandbox owner gets via scripts/provision.sh).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --control-namespace) CONTROL_NAMESPACE="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) usage; exit "${EXIT_OK}" ;;
    *) log_error "Unknown argument: $1"; usage; exit "${EXIT_USAGE}" ;;
  esac
done

require_cmd oc yq jq envsubst
require_oc_login

log_info "== Step 1/3: validating framework configuration =="
"${SCRIPT_DIR}/validate.sh"

log_info "== Step 2/3: applying cluster-scoped RBAC (sandbox-workspace-edit ClusterRole) =="
apply_manifest "${BASE_DIR}/rbac/cluster-role.yaml" "${DRY_RUN}"

log_info "== Step 3/3: creating control-plane namespace '${CONTROL_NAMESPACE}' and config mirror =="
NS_MANIFEST="$(mktemp)"
register_temp_file "${NS_MANIFEST}"
cat > "${NS_MANIFEST}" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${CONTROL_NAMESPACE}
  labels:
    sandbox.gosi/managed-by: "sandbox-automation"
    sandbox.gosi/role: "control-plane"
EOF
apply_manifest "${NS_MANIFEST}" "${DRY_RUN}"

CM_MANIFEST="$(mktemp)"
register_temp_file "${CM_MANIFEST}"
if [[ "${DRY_RUN}" == "true" ]]; then
  oc create configmap sandbox-catalog-config \
    --namespace "${CONTROL_NAMESPACE}" \
    --from-file=catalog.yaml="${CATALOG_FILE}" \
    --from-file=profiles.yaml="${PROFILES_FILE}" \
    --from-file=registry.yaml="${REGISTRY_FILE}" \
    --from-file=policies.yaml="${POLICIES_FILE}" \
    --dry-run=client -o yaml > "${CM_MANIFEST}"
  log_info "[dry-run] would apply control-plane ConfigMap sandbox-catalog-config"
  oc apply --dry-run=client -f "${CM_MANIFEST}" >/dev/null
else
  oc create configmap sandbox-catalog-config \
    --namespace "${CONTROL_NAMESPACE}" \
    --from-file=catalog.yaml="${CATALOG_FILE}" \
    --from-file=profiles.yaml="${PROFILES_FILE}" \
    --from-file=registry.yaml="${REGISTRY_FILE}" \
    --from-file=policies.yaml="${POLICIES_FILE}" \
    --dry-run=client -o yaml | oc apply -f -
fi

log_info "Framework deployment complete. Control namespace: ${CONTROL_NAMESPACE}"
log_info "Next: scripts/provision.sh --catalog <ID> --request-id <ID> --owner <owner>"
exit "${EXIT_OK}"
