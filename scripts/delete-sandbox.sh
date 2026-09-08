#!/usr/bin/env bash
# =============================================================================
# scripts/delete-sandbox.sh -- tear down a sandbox namespace by request ID.
#
# SAFETY: this script will NEVER delete a namespace that does not carry the
# label sandbox.gosi/managed-by=sandbox-automation, regardless of what
# namespace name is supplied or computed. There is no override flag for
# this check -- if you need to delete a namespace this automation did not
# create, do it manually with full awareness of what you are removing.
#
# Usage:
#   scripts/delete-sandbox.sh --request-id REQ000123 [--team team-data] [--force] [--dry-run]
#
# If --team is omitted, the script searches for a namespace whose
# sandbox.gosi/request-id label matches --request-id (there should be
# exactly one).
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

REQUEST_ID=""
TEAM=""
NAMESPACE_OVERRIDE=""
FORCE="false"
DRY_RUN="false"

usage() {
  cat <<'EOF'
Usage: delete-sandbox.sh --request-id <ID> [options]

  --request-id <ID>   Remedy/request identifier (required)
  --team <team>        Team segment, if known (speeds up namespace lookup)
  --namespace <name>   Explicit namespace name (still must be
                        sandbox-automation-managed and still must match
                        --request-id's label -- this is a lookup
                        convenience, not a bypass)
  --force              Skip the interactive confirmation prompt
  --dry-run            Show what would be deleted, delete nothing
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --request-id) REQUEST_ID="$2"; shift 2 ;;
    --team) TEAM="$2"; shift 2 ;;
    --namespace) NAMESPACE_OVERRIDE="$2"; shift 2 ;;
    --force) FORCE="true"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) usage; exit "${EXIT_OK}" ;;
    *) log_error "Unknown argument: $1"; usage; exit "${EXIT_USAGE}" ;;
  esac
done

[[ -n "${REQUEST_ID}" ]] || { log_error "--request-id is required"; usage; exit "${EXIT_USAGE}"; }

require_cmd oc jq
require_oc_login

# --- Resolve the namespace --------------------------------------------------
if [[ -n "${NAMESPACE_OVERRIDE}" ]]; then
  NAMESPACE="${NAMESPACE_OVERRIDE}"
elif [[ -n "${TEAM}" ]]; then
  NAMESPACE="$(build_namespace_name "${TEAM}" "${REQUEST_ID}")"
else
  NAMESPACE="$(oc get namespaces -l "sandbox.gosi/request-id=${REQUEST_ID},sandbox.gosi/managed-by=sandbox-automation" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  MATCH_COUNT="$(oc get namespaces -l "sandbox.gosi/request-id=${REQUEST_ID},sandbox.gosi/managed-by=sandbox-automation" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w | tr -d ' ')"
  if [[ "${MATCH_COUNT}" -gt 1 ]]; then
    fatal "${EXIT_NAMESPACE_INVALID}" "Multiple namespaces match request-id '${REQUEST_ID}'. Re-run with --namespace to disambiguate."
  fi
fi

[[ -n "${NAMESPACE}" ]] || fatal "${EXIT_NAMESPACE_INVALID}" "Could not resolve a namespace for request-id '${REQUEST_ID}'. Nothing to delete."

if ! oc get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  log_warn "Namespace '${NAMESPACE}' does not exist. Nothing to do."
  exit "${EXIT_OK}"
fi

# --- The one non-negotiable safety check ------------------------------------
if ! is_sandbox_managed_namespace "${NAMESPACE}"; then
  fatal "${EXIT_NAMESPACE_NOT_MANAGED}" "Refusing to delete '${NAMESPACE}': it is not labeled sandbox.gosi/managed-by=sandbox-automation. This is never bypassed."
fi

NS_REQUEST_ID="$(oc get namespace "${NAMESPACE}" -o jsonpath='{.metadata.labels.sandbox\.gosi/request-id}' 2>/dev/null || true)"
if [[ "${NS_REQUEST_ID}" != "${REQUEST_ID}" ]]; then
  fatal "${EXIT_NAMESPACE_NOT_MANAGED}" "Namespace '${NAMESPACE}' is sandbox-managed but its request-id label ('${NS_REQUEST_ID}') does not match '${REQUEST_ID}'. Refusing to delete a mismatched namespace."
fi

CATALOG_ID_LABEL="$(oc get namespace "${NAMESPACE}" -o jsonpath='{.metadata.labels.sandbox\.gosi/catalog-id}' 2>/dev/null || echo unknown)"
OWNER_ANN="$(oc get namespace "${NAMESPACE}" -o jsonpath='{.metadata.annotations.sandbox\.gosi/owner}' 2>/dev/null || echo unknown)"

log_info "About to delete sandbox namespace:"
log_info "  Namespace:   ${NAMESPACE}"
log_info "  Catalog ID:  ${CATALOG_ID_LABEL}"
log_info "  Owner:       ${OWNER_ANN}"
log_info "  Request ID:  ${REQUEST_ID}"

if [[ "${DRY_RUN}" == "true" ]]; then
  log_info "[dry-run] would delete namespace '${NAMESPACE}' and everything in it"
  exit "${EXIT_OK}"
fi

if [[ "${FORCE}" != "true" ]]; then
  read -r -p "Type the namespace name to confirm deletion: " CONFIRM
  if [[ "${CONFIRM}" != "${NAMESPACE}" ]]; then
    fatal "${EXIT_USAGE}" "Confirmation did not match namespace name. Aborting."
  fi
fi

log_info "Deleting namespace ${NAMESPACE} ..."
oc delete namespace "${NAMESPACE}" --wait=false
log_info "Deletion requested. OpenShift will finalize resource cleanup asynchronously."
log_info "Note: PersistentVolumes reclaimed depend on the StorageClass reclaim policy."
log_info "Audit: retain this log line for the decommissioning record -- catalog=${CATALOG_ID_LABEL} owner=${OWNER_ANN} request=${REQUEST_ID} namespace=${NAMESPACE} deleted_at=$(now_iso)"
exit "${EXIT_OK}"
