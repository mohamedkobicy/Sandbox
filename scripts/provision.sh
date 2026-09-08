#!/usr/bin/env bash
# =============================================================================
# scripts/provision.sh -- provision a single Enterprise Sandbox Catalog
#                          request into an isolated OpenShift namespace.
#
# This is the script a Remedy-triggered automation (or a DevOps engineer,
# manually) calls with a Catalog ID and a handful of policy-bounded
# parameters. It NEVER accepts an arbitrary image URL, registry, SCC,
# ServiceAccount, host mount, or cluster role from the caller -- everything
# beyond the parameters below is resolved from config/catalog.yaml,
# config/profiles.yaml, config/registry.yaml and config/policies.yaml.
#
# Usage:
#   scripts/provision.sh --catalog DEV-PY --request-id REQ000123 \
#     --owner team-data [options]
#
# See `scripts/provision.sh --help` for the full option list, and
# examples/remedy-request.json / examples/manual-request.yaml for sample
# request payloads.
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# --- Defaults ----------------------------------------------------------------
CATALOG_ID=""
REQUEST_ID=""
OWNER=""
TEAM=""
ENVIRONMENT="sandbox"
TTL=""
STORAGE_SIZE_OVERRIDE=""
GPU_REQUESTED="false"
APPROVED="false"
DRY_RUN="false"
ENABLE_LIST=""
SECRET_REF=""
CONFIG_REF=""
OWNER_SUBJECT_KIND="User"
OWNER_SUBJECT_NAME=""

usage() {
  cat <<'EOF'
Usage: provision.sh --catalog <ID> --request-id <ID> --owner <owner> [options]

Required (this is the Remedy contract -- see examples/remedy-request.json):
  --catalog <ID>              Catalog ID from config/catalog.yaml (e.g. DEV-PY)
  --request-id <ID>           Remedy/tracking request identifier (e.g. REQ000123)
  --owner <owner>             Requesting user or team identifier

Policy-bounded optional parameters:
  --team <team>                Namespace team segment (default: sanitized --owner)
  --environment <env>          Default: sandbox
  --ttl <7d|12h>                Default: config/policies.yaml lifecycle.defaultTtl
  --storage-size <NNGi>         Override within config/policies.yaml storage.maxSize
                                (only valid if the catalog entry has storage.enabled)
  --gpu <true|false>            Default: false. Requires catalog gpu.supported=true.
  --approved <true|false>       Required true when the catalog's approval=review.
                                NOT a full security control by itself -- see
                                docs/SECURITY.md "Approval trust boundary".
  --enable <git,secrets,observability>
                                Comma-separated platform integrations to layer on
  --secret-ref <name>           Pre-existing Secret name (required with --enable secrets)
  --config-ref <name>           Pre-existing ConfigMap name (e.g. Kafka bootstrap for
                                INT-KCONNECT)
  --owner-subject-kind <User|Group>  Default: User
  --owner-subject-name <name>   RBAC subject name (default: --owner)
  --dry-run                     Render and client-side validate only; no cluster writes
  -h, --help                    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --catalog) CATALOG_ID="$2"; shift 2 ;;
    --request-id) REQUEST_ID="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --team) TEAM="$2"; shift 2 ;;
    --environment) ENVIRONMENT="$2"; shift 2 ;;
    --ttl) TTL="$2"; shift 2 ;;
    --storage-size) STORAGE_SIZE_OVERRIDE="$2"; shift 2 ;;
    --gpu) GPU_REQUESTED="$2"; shift 2 ;;
    --approved) APPROVED="$2"; shift 2 ;;
    --enable) ENABLE_LIST="$2"; shift 2 ;;
    --secret-ref) SECRET_REF="$2"; shift 2 ;;
    --config-ref) CONFIG_REF="$2"; shift 2 ;;
    --owner-subject-kind) OWNER_SUBJECT_KIND="$2"; shift 2 ;;
    --owner-subject-name) OWNER_SUBJECT_NAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) usage; exit "${EXIT_OK}" ;;
    *) log_error "Unknown argument: $1"; usage; exit "${EXIT_USAGE}" ;;
  esac
done

[[ -n "${CATALOG_ID}" ]] || { log_error "--catalog is required"; usage; exit "${EXIT_USAGE}"; }
[[ -n "${REQUEST_ID}" ]] || { log_error "--request-id is required"; usage; exit "${EXIT_USAGE}"; }
[[ -n "${OWNER}" ]] || { log_error "--owner is required"; usage; exit "${EXIT_USAGE}"; }

TEAM="${TEAM:-$(sanitize_dns_label "${OWNER}")}"
OWNER_SUBJECT_NAME="${OWNER_SUBJECT_NAME:-${OWNER}}"

# =============================================================================
# 1. Prerequisites
# =============================================================================
require_cmd oc yq jq envsubst
if [[ "${DRY_RUN}" != "true" ]]; then
  require_oc_login
elif oc whoami >/dev/null 2>&1; then
  require_oc_login
else
  log_warn "--dry-run without an active 'oc login': client-side validation of manifest structure only, no cluster context."
fi

# =============================================================================
# 2. Catalog validation (never trust the caller past the Catalog ID)
# =============================================================================
if ! catalog_id_exists "${CATALOG_ID}"; then
  fatal "${EXIT_CATALOG_ID_UNKNOWN}" "Unknown Catalog ID '${CATALOG_ID}'. See config/catalog.yaml for the approved list."
fi

METHOD="$(catalog_field "${CATALOG_ID}" '.implementation.method')"
if [[ "${METHOD}" == "none-base-image" ]]; then
  fatal "${EXIT_CATALOG_ID_UNKNOWN}" "'${CATALOG_ID}' is a base image, not an independently provisionable Catalog ID."
fi

REMEDY_SELECTABLE="$(catalog_field "${CATALOG_ID}" '.remedySelectable')"
if [[ "${REMEDY_SELECTABLE}" != "true" ]]; then
  log_warn "'${CATALOG_ID}' is not Remedy-selectable (remedySelectable=false). Proceeding as a direct DevOps-initiated provision; confirm this is intentional."
fi

# --- Approval gating ----------------------------------------------------------
APPROVAL_MODE="$(catalog_field "${CATALOG_ID}" '.approval')"
if [[ "${APPROVAL_MODE}" == "review" && "${APPROVED}" != "true" ]]; then
  fatal "${EXIT_APPROVAL_REQUIRED}" "'${CATALOG_ID}' requires Approval=Review. Re-run with --approved true only once the upstream Remedy/workflow approval has actually been granted. This flag is NOT itself a security control -- see docs/SECURITY.md 'Approval trust boundary'."
fi
if [[ "${APPROVAL_MODE}" == "review" ]]; then
  log_warn "Proceeding on Approval=Review with --approved true. In production, the caller's identity/workflow token must be independently verified server-side -- a CLI flag alone must never be trusted as authorization."
fi

# --- GPU gating -----------------------------------------------------------
GPU_SUPPORTED="$(catalog_field "${CATALOG_ID}" '.gpu.supported')"
if [[ "${GPU_REQUESTED}" == "true" ]]; then
  if [[ "${GPU_SUPPORTED}" != "true" ]]; then
    fatal "${EXIT_GPU_NOT_SUPPORTED}" "'${CATALOG_ID}' does not support GPU (gpu.supported=false)."
  fi
  GPU_RESOURCE_NAME="$(policy_field '.gpu.resourceName')"
  if [[ "${DRY_RUN}" != "true" ]] && oc whoami >/dev/null 2>&1; then
    # jsonpath uses '.' as the field separator, so a resource name like
    # "nvidia.com/gpu" (which itself contains dots) must have those dots
    # escaped to be treated as literal characters, not path separators.
    GPU_JSONPATH_KEY="${GPU_RESOURCE_NAME//./\\.}"
    if ! oc get nodes -o jsonpath="{.items[*].status.allocatable.${GPU_JSONPATH_KEY}}" 2>/dev/null | grep -qE '[1-9]'; then
      fatal "${EXIT_GPU_UNAVAILABLE}" "No cluster node currently advertises allocatable '${GPU_RESOURCE_NAME}'. Confirm the GPU Operator/device plugin is installed, or provision without --gpu true."
    fi
    log_info "Cluster capacity check passed for GPU resource '${GPU_RESOURCE_NAME}'"
  fi
fi

# --- Storage validation -----------------------------------------------------
STORAGE_ENABLED="$(catalog_field "${CATALOG_ID}" '.storage.enabled')"
STORAGE_SIZE="$(catalog_field "${CATALOG_ID}" '.storage.size')"
if [[ -n "${STORAGE_SIZE_OVERRIDE}" ]]; then
  if [[ "${STORAGE_ENABLED}" != "true" ]]; then
    log_warn "--storage-size given but '${CATALOG_ID}' has no storage; ignoring override."
  else
    PATTERN="$(policy_field '.storage.allowedSizesPattern')"
    [[ "${STORAGE_SIZE_OVERRIDE}" =~ ${PATTERN} ]] || fatal "${EXIT_STORAGE_INVALID}" "--storage-size '${STORAGE_SIZE_OVERRIDE}' is not a valid quantity (expected e.g. 20Gi)."
    MAX_SIZE_GI="$(policy_field '.storage.maxSize' | sed -E 's/Gi$//')"
    REQ_SIZE_GI="$(echo "${STORAGE_SIZE_OVERRIDE}" | sed -E 's/Gi$//')"
    if [[ "${STORAGE_SIZE_OVERRIDE}" == *Gi && "${REQ_SIZE_GI}" -gt "${MAX_SIZE_GI}" ]]; then
      fatal "${EXIT_STORAGE_INVALID}" "--storage-size ${STORAGE_SIZE_OVERRIDE} exceeds policy maximum $(policy_field '.storage.maxSize')."
    fi
    STORAGE_SIZE="${STORAGE_SIZE_OVERRIDE}"
  fi
fi

# =============================================================================
# 3. Compute request-scoped values
# =============================================================================
TTL="${TTL:-$(policy_field '.lifecycle.defaultTtl')}"
NAMESPACE="$(build_namespace_name "${TEAM}" "${REQUEST_ID}")"
[[ -n "${NAMESPACE}" ]] || fatal "${EXIT_NAMESPACE_INVALID}" "Computed namespace name is empty."
CREATED_AT="$(now_iso)"
EXPIRES_AT="$(expires_iso "${TTL}")"
WORKLOAD_NAME="$(sanitize_dns_label "${CATALOG_ID}")"
SERVICE_ACCOUNT_NAME="sandbox-runtime"
PROFILE="$(catalog_field "${CATALOG_ID}" '.profile')"

AUTOMOUNT_SA_TOKEN="$(catalog_field "${CATALOG_ID}" '.serviceAccount.automountToken')"
[[ "${AUTOMOUNT_SA_TOKEN}" == "true" ]] || AUTOMOUNT_SA_TOKEN="false"

log_info "Provisioning ${CATALOG_ID} -> namespace ${NAMESPACE} (request ${REQUEST_ID}, owner ${OWNER}, ttl ${TTL}, expires ${EXPIRES_AT}, dry-run=${DRY_RUN})"

# Export everything the envsubst-based templates reference.
export SANDBOX_NAMESPACE="${NAMESPACE}" CATALOG_ID REQUEST_ID ENVIRONMENT TEAM OWNER
export CREATED_AT EXPIRES_AT WORKLOAD_NAME SERVICE_ACCOUNT_NAME AUTOMOUNT_SA_TOKEN
export TTL PROFILE OWNER_SUBJECT_KIND OWNER_SUBJECT_NAME
export IMAGE_REF="" IMAGE_PULL_POLICY=""
export CPU_REQUEST MEM_REQUEST CPU_LIMIT MEM_LIMIT
export STORAGE_SIZE STORAGE_CLASS="${STORAGE_CLASS:-$(policy_field '.storage.defaultClass')}"
export STORAGE_CLASS_FIELD GPU_LIMIT_LINE
export SERVICE_PORT="" ROUTE_HOST_FIELD="" ROUTE_TARGET_PORT=""
export EGRESS_CIDR_BLOCK=""
export DECISION_NEEDED=""
export EXTRA_ENV_BLOCK=""
export SECRET_REF_NAME="${SECRET_REF}"

CPU_REQUEST="$(profile_field "${PROFILE}" '.requests.cpu')"
MEM_REQUEST="$(profile_field "${PROFILE}" '.requests.memory')"
CPU_LIMIT="$(profile_field "${PROFILE}" '.limits.cpu')"
MEM_LIMIT="$(profile_field "${PROFILE}" '.limits.memory')"
STORAGE_CLASS_FIELD="$(render_storage_class_field)"
GPU_LIMIT_LINE="$(render_gpu_limit_line "${GPU_REQUESTED}")"

ROUTE_ENABLED="$(catalog_field "${CATALOG_ID}" '.network.route.enabled')"
if [[ "${ROUTE_ENABLED}" == "true" ]]; then
  SERVICE_PORT="$(catalog_field "${CATALOG_ID}" '.network.route.port')"
  ROUTE_TARGET_PORT="${SERVICE_PORT}"
  ROUTE_HOST_FIELD="$(render_route_host_field "${WORKLOAD_NAME}" "${NAMESPACE}")"
else
  # statefulset-template entries still need SERVICE_PORT even with no Route.
  P="$(catalog_field "${CATALOG_ID}" '.network.route.port')"
  [[ "${P}" != "null" ]] && SERVICE_PORT="${P}"
fi

load_quota_vars
load_limitrange_vars

WORKDIR="$(mktemp -d)"
register_temp_file "${WORKDIR}"

render_and_apply() {
  local tmpl="$1"
  local out
  out="${WORKDIR}/$(basename "${tmpl}")"
  render_template "${tmpl}" "${out}"
  apply_manifest "${out}" "${DRY_RUN}"
}

# =============================================================================
# 4. Namespace + governance scaffolding (applies to every Catalog ID)
# =============================================================================
log_info "== Rendering namespace and governance scaffolding =="
render_and_apply "${BASE_DIR}/namespace/namespace.yaml"
render_and_apply "${BASE_DIR}/rbac/serviceaccount.yaml"
render_and_apply "${BASE_DIR}/rbac/role-binding.yaml"
render_and_apply "${BASE_DIR}/network-policy/00-default-deny-all.yaml"
render_and_apply "${BASE_DIR}/network-policy/10-allow-same-namespace.yaml"
render_and_apply "${BASE_DIR}/network-policy/20-allow-dns-egress.yaml"
if [[ "${ROUTE_ENABLED}" == "true" ]]; then
  render_and_apply "${BASE_DIR}/network-policy/30-allow-ingress-router.yaml"
fi
mapfile -t EGRESS_CIDRS < <(policy_field '.network.allowedEgressCIDRs[]' 2>/dev/null || true)
if (( ${#EGRESS_CIDRS[@]} > 0 )); then
  block=""
  for cidr in "${EGRESS_CIDRS[@]}"; do
    block+="    - to:"$'\n'"        - ipBlock:"$'\n'"            cidr: ${cidr}"$'\n'
  done
  EGRESS_CIDR_BLOCK="${block%$'\n'}"
  render_and_apply "${BASE_DIR}/network-policy/40-allow-egress-controlled.yaml"
else
  log_warn "config/policies.yaml network.allowedEgressCIDRs is empty -- controlled egress policy skipped (fail-closed; see IMPLEMENTATION_REQUIRED note in base/network-policy/40-allow-egress-controlled.yaml)"
fi
render_and_apply "${BASE_DIR}/resource-quota/resource-quota.yaml"
render_and_apply "${BASE_DIR}/limit-range/limit-range.yaml"

# =============================================================================
# 5. Workload rendering, branched by implementation.method
# =============================================================================
case "${METHOD}" in
  workspace-template)
    IMAGE_REF="$(resolve_image_ref "${CATALOG_ID}")"
    IMAGE_PULL_POLICY="$(catalog_field "${CATALOG_ID}" '.image.pullPolicy')"
    export IMAGE_REF IMAGE_PULL_POLICY
    if [[ "${STORAGE_ENABLED}" == "true" ]]; then
      render_and_apply "${TEMPLATES_DIR}/workspace/base/pvc.yaml"
      render_and_apply "${TEMPLATES_DIR}/workspace/base/deployment-with-storage.yaml"
    else
      render_and_apply "${TEMPLATES_DIR}/workspace/base/deployment.yaml"
    fi
    if [[ "${ROUTE_ENABLED}" == "true" ]]; then
      render_and_apply "${TEMPLATES_DIR}/workspace/base/service.yaml"
      render_and_apply "${TEMPLATES_DIR}/workspace/base/route.yaml"
    fi
    ;;

  service-template)
    IMAGE_REF="$(resolve_image_ref "${CATALOG_ID}")"
    IMAGE_PULL_POLICY="$(catalog_field "${CATALOG_ID}" '.image.pullPolicy')"
    export IMAGE_REF IMAGE_PULL_POLICY
    if [[ "${STORAGE_ENABLED}" == "true" ]]; then
      render_and_apply "${TEMPLATES_DIR}/service/base/pvc.yaml"
      render_and_apply "${TEMPLATES_DIR}/service/base/deployment-with-storage.yaml"
    else
      render_and_apply "${TEMPLATES_DIR}/service/base/deployment.yaml"
    fi
    render_and_apply "${TEMPLATES_DIR}/service/base/service.yaml"
    if [[ "${ROUTE_ENABLED}" == "true" ]]; then
      render_and_apply "${TEMPLATES_DIR}/service/base/route.yaml"
    fi
    ;;

  statefulset-template)
    IMAGE_REF="$(resolve_image_ref "${CATALOG_ID}")"
    IMAGE_PULL_POLICY="$(catalog_field "${CATALOG_ID}" '.image.pullPolicy')"
    export IMAGE_REF IMAGE_PULL_POLICY
    if [[ -n "${CONFIG_REF}" ]]; then
      if [[ "${DRY_RUN}" != "true" ]] && ! oc get configmap "${CONFIG_REF}" -n "${NAMESPACE}" >/dev/null 2>&1; then
        fatal "${EXIT_CATALOG_INVALID}" "--config-ref '${CONFIG_REF}' does not exist in namespace ${NAMESPACE}. Create it first (see catalog/integration/int-kconnect/README.md)."
      fi
      EXTRA_ENV_BLOCK="$(printf '            - name: KAFKA_BOOTSTRAP_SERVERS\n              valueFrom:\n                configMapKeyRef:\n                  name: %s\n                  key: bootstrapServers\n' "${CONFIG_REF}")"
      export EXTRA_ENV_BLOCK
    fi
    render_and_apply "${TEMPLATES_DIR}/platform-service/base/statefulset/statefulset.yaml"
    render_and_apply "${TEMPLATES_DIR}/platform-service/base/statefulset/service.yaml"
    ;;

  operator-placeholder|helm-placeholder)
    DECISION_NEEDED="$(catalog_field "${CATALOG_ID}" '.implementation.decisionNeeded')"
    export DECISION_NEEDED
    render_and_apply "${TEMPLATES_DIR}/platform-service/base/operator-placeholder/service-request-configmap.yaml"
    log_warn "=============================================================="
    log_warn " IMPLEMENTATION_REQUIRED: ${CATALOG_ID} has no deployable workload yet."
    log_warn " Decision needed: ${DECISION_NEEDED}"
    log_warn " Namespace ${NAMESPACE} and its governance scaffolding (RBAC,"
    log_warn " NetworkPolicy, ResourceQuota, LimitRange) were created and the"
    log_warn " request is recorded in ConfigMap/sandbox-service-request."
    log_warn " See docs/CATALOG-MAPPING.md and catalog/*/${CATALOG_ID,,}/README.md"
    log_warn "=============================================================="
    if [[ "${DRY_RUN}" != "true" ]]; then
      exit "${EXIT_IMPLEMENTATION_REQUIRED}"
    fi
    ;;

  platform-integration)
    case "${CATALOG_ID}" in
      SHARED-GIT) render_and_apply "${TEMPLATES_DIR}/integration/git/git-config-configmap.yaml" ;;
      SHARED-SECRETS) log_info "SHARED-SECRETS requested standalone: no workload to attach to. Use --enable secrets on a workspace request instead, or see templates/integration/secrets/README.md." ;;
      SHARED-OBS) log_info "SHARED-OBS requested standalone: no workload to attach to. Use --enable observability on a workspace request instead, or see templates/integration/observability/README.md." ;;
    esac
    ;;

  *)
    fatal "${EXIT_CATALOG_INVALID}" "Unhandled implementation.method '${METHOD}' for ${CATALOG_ID}."
    ;;
esac

# =============================================================================
# 6. Optional platform integrations layered onto the primary workload
# =============================================================================
if [[ -n "${ENABLE_LIST}" ]]; then
  IFS=',' read -ra ENABLES <<< "${ENABLE_LIST}"
  for feature in "${ENABLES[@]}"; do
    case "${feature}" in
      git)
        render_and_apply "${TEMPLATES_DIR}/integration/git/git-config-configmap.yaml"
        ;;
      secrets)
        [[ -n "${SECRET_REF}" ]] || fatal "${EXIT_USAGE}" "--enable secrets requires --secret-ref <existing-secret-name>"
        if [[ "${DRY_RUN}" != "true" ]] && ! oc get secret "${SECRET_REF}" -n "${NAMESPACE}" >/dev/null 2>&1; then
          fatal "${EXIT_CATALOG_INVALID}" "--secret-ref '${SECRET_REF}' does not exist in namespace ${NAMESPACE}. Create it out-of-band first (Governance: no embedded credentials)."
        fi
        PATCH_FILE="${WORKDIR}/secret-mount-patch.yaml"
        render_template "${TEMPLATES_DIR}/integration/secrets/secret-mount-patch.yaml" "${PATCH_FILE}"
        if [[ "${DRY_RUN}" != "true" ]]; then
          oc patch deployment "${WORKLOAD_NAME}" -n "${NAMESPACE}" --patch-file "${PATCH_FILE}" --type=strategic
        else
          log_info "[dry-run] would patch deployment/${WORKLOAD_NAME} with secret mount for '${SECRET_REF}'"
        fi
        ;;
      observability)
        PATCH_FILE="${WORKDIR}/observability-patch.yaml"
        render_template "${TEMPLATES_DIR}/integration/observability/observability-annotations-patch.yaml" "${PATCH_FILE}"
        if [[ "${DRY_RUN}" != "true" ]]; then
          oc patch deployment "${WORKLOAD_NAME}" -n "${NAMESPACE}" --patch-file "${PATCH_FILE}" --type=strategic
        else
          log_info "[dry-run] would patch deployment/${WORKLOAD_NAME} with observability annotations"
        fi
        ;;
      *)
        log_warn "Unknown --enable feature '${feature}', skipping"
        ;;
    esac
  done
fi

# =============================================================================
# 7. Summary
# =============================================================================
log_info "=============================================================="
log_info " Provisioning complete: ${CATALOG_ID} (${METHOD})"
log_info " Namespace:   ${NAMESPACE}"
log_info " Owner:       ${OWNER} (team: ${TEAM})"
log_info " Request ID:  ${REQUEST_ID}"
log_info " TTL:         ${TTL} (expires ${EXPIRES_AT})"
log_info " Dry-run:     ${DRY_RUN}"
log_info " Next:        scripts/health-check.sh --request-id ${REQUEST_ID}"
log_info "=============================================================="
exit "${EXIT_OK}"
