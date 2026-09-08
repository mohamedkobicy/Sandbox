#!/usr/bin/env bash
# =============================================================================
# scripts/health-check.sh -- first-line diagnostic report for a sandbox
#                             namespace.
#
# Usage:
#   scripts/health-check.sh --request-id REQ000123 [--team team-data]
#   scripts/health-check.sh --namespace sbx-team-data-req000123
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

REQUEST_ID=""
TEAM=""
NAMESPACE=""

usage() {
  cat <<'EOF'
Usage: health-check.sh (--request-id <ID> [--team <team>] | --namespace <name>)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --request-id) REQUEST_ID="$2"; shift 2 ;;
    --team) TEAM="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    -h|--help) usage; exit "${EXIT_OK}" ;;
    *) log_error "Unknown argument: $1"; usage; exit "${EXIT_USAGE}" ;;
  esac
done

require_cmd oc jq
require_oc_login

if [[ -z "${NAMESPACE}" ]]; then
  [[ -n "${REQUEST_ID}" ]] || fatal "${EXIT_USAGE}" "Provide --namespace or --request-id."
  if [[ -n "${TEAM}" ]]; then
    NAMESPACE="$(build_namespace_name "${TEAM}" "${REQUEST_ID}")"
  else
    NAMESPACE="$(oc get namespaces -l "sandbox.gosi/request-id=${REQUEST_ID}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi
fi

[[ -n "${NAMESPACE}" ]] || fatal "${EXIT_NAMESPACE_INVALID}" "Could not resolve a namespace."

if ! oc get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  fatal "${EXIT_NAMESPACE_INVALID}" "Namespace '${NAMESPACE}' does not exist."
fi

section() { printf '\n=== %s ===\n' "$1"; }

section "Namespace"
oc get namespace "${NAMESPACE}" -o jsonpath='{.metadata.labels}{"\n"}{.metadata.annotations}{"\n"}' 2>/dev/null
echo

section "Pods"
oc get pods -n "${NAMESPACE}" -o wide || true

section "PersistentVolumeClaims"
oc get pvc -n "${NAMESPACE}" || true

section "Services"
oc get svc -n "${NAMESPACE}" || true

section "Routes"
oc get route -n "${NAMESPACE}" 2>/dev/null || echo "(no Routes in this namespace)"

section "ResourceQuota"
oc get resourcequota -n "${NAMESPACE}" -o wide || true

section "Recent Events (last 20)"
oc get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' 2>/dev/null | tail -n 20 || true

# --- Automated condition detection ------------------------------------------
section "Diagnostic Findings"
FOUND_ISSUE="false"

mapfile -t POD_LINES < <(oc get pods -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{range .status.containerStatuses[*]}{.state.waiting.reason}{" "}{end}{"\n"}{end}' 2>/dev/null || true)
for line in "${POD_LINES[@]:-}"; do
  [[ -z "${line}" ]] && continue
  name="$(echo "${line}" | cut -f1)"
  phase="$(echo "${line}" | cut -f2)"
  reasons="$(echo "${line}" | cut -f3)"
  if [[ "${reasons}" == *CrashLoopBackOff* ]]; then
    echo "[ISSUE] Pod '${name}' is in CrashLoopBackOff -- check: oc logs -n ${NAMESPACE} ${name} --previous"
    FOUND_ISSUE="true"
  fi
  if [[ "${reasons}" == *ImagePullBackOff* || "${reasons}" == *ErrImagePull* ]]; then
    echo "[ISSUE] Pod '${name}' cannot pull its image -- check Quay pull secret/robot account and config/registry.yaml. See docs/TROUBLESHOOTING.md 'ImagePullBackOff'."
    FOUND_ISSUE="true"
  fi
  if [[ "${phase}" == "Pending" ]]; then
    echo "[ISSUE] Pod '${name}' is Pending -- check: oc describe pod -n ${NAMESPACE} ${name} (often quota, scheduling, or an unschedulable node)."
    FOUND_ISSUE="true"
  fi
done

mapfile -t PVC_LINES < <(oc get pvc -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}' 2>/dev/null || true)
for line in "${PVC_LINES[@]:-}"; do
  [[ -z "${line}" ]] && continue
  name="$(echo "${line}" | cut -f1)"
  phase="$(echo "${line}" | cut -f2)"
  if [[ "${phase}" == "Pending" ]]; then
    echo "[ISSUE] PVC '${name}' is Pending -- check StorageClass availability/quota. See docs/TROUBLESHOOTING.md 'PVC Pending'."
    FOUND_ISSUE="true"
  fi
done

if oc get events -n "${NAMESPACE}" 2>/dev/null | grep -qi "exceeded quota"; then
  echo "[ISSUE] ResourceQuota exceeded -- check: oc describe resourcequota -n ${NAMESPACE}"
  FOUND_ISSUE="true"
fi
if oc get events -n "${NAMESPACE}" 2>/dev/null | grep -qi "FailedMount"; then
  echo "[ISSUE] A volume failed to mount -- check: oc describe pod -n ${NAMESPACE} <pod>"
  FOUND_ISSUE="true"
fi
if oc get events -n "${NAMESPACE}" 2>/dev/null | grep -qiE "Unhealthy|Readiness probe failed|Liveness probe failed"; then
  echo "[ISSUE] A readiness/liveness probe is failing -- check: oc describe pod -n ${NAMESPACE} <pod>"
  FOUND_ISSUE="true"
fi
if oc get events -n "${NAMESPACE}" 2>/dev/null | grep -qi "FailedScheduling"; then
  echo "[ISSUE] A pod is unschedulable -- check: oc describe pod -n ${NAMESPACE} <pod> (node capacity, taints, or affinity)"
  FOUND_ISSUE="true"
fi

if [[ "${FOUND_ISSUE}" == "false" ]]; then
  echo "No known issue signatures detected. If something still looks wrong, see docs/TROUBLESHOOTING.md."
fi

section "Expiry"
EXPIRES_AT="$(oc get namespace "${NAMESPACE}" -o jsonpath='{.metadata.annotations.sandbox\.gosi/expires-at}' 2>/dev/null || true)"
if [[ -n "${EXPIRES_AT}" ]]; then
  echo "Expires at: ${EXPIRES_AT}"
  NOW_EPOCH="$(date -u +%s)"
  EXP_EPOCH="$(date -u -d "${EXPIRES_AT}" +%s 2>/dev/null || echo 0)"
  if [[ "${EXP_EPOCH}" -gt 0 && "${NOW_EPOCH}" -gt "${EXP_EPOCH}" ]]; then
    echo "[NOTICE] This sandbox has PASSED its TTL expiry. Consider: scripts/delete-sandbox.sh --request-id <ID>"
  fi
else
  echo "No expiry annotation found."
fi

exit "${EXIT_OK}"
