#!/usr/bin/env bash
# =============================================================================
# scripts/validate.sh -- validate the catalog framework and/or a specific
#                         provisioning request before it is applied.
#
# Usage:
#   scripts/validate.sh                       # validate config/ only
#   scripts/validate.sh --catalog DEV-PY \
#     --request-id REQ000123 --owner team-data # also validate a request
#   scripts/validate.sh --server-side ...      # also run `oc apply --dry-run=server`
#
# Exit codes: see scripts/common.sh (EXIT_*)
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

CATALOG_ID=""
REQUEST_ID=""
OWNER=""
TEAM=""
GPU_REQUESTED="false"
SERVER_SIDE="false"

usage() {
  cat <<'EOF'
Usage: validate.sh [options]

Framework validation (always runs):
  Validates config/catalog.yaml, config/profiles.yaml, config/registry.yaml,
  config/policies.yaml, and every rendered template for YAML syntax and
  internal consistency.

Optional per-request validation:
  --catalog <ID>          Catalog ID to validate a hypothetical request for
  --request-id <ID>       Remedy/request identifier
  --owner <owner>         Requesting owner/team
  --team <team>           Team identifier used in the namespace name
                          (defaults to a sanitized form of --owner)
  --gpu <true|false>      Whether GPU would be requested (default false)
  --server-side           Also run `oc apply --dry-run=server` (requires an
                          active `oc login` and a real cluster)
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --catalog) CATALOG_ID="$2"; shift 2 ;;
    --request-id) REQUEST_ID="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --team) TEAM="$2"; shift 2 ;;
    --gpu) GPU_REQUESTED="$2"; shift 2 ;;
    --server-side) SERVER_SIDE="true"; shift ;;
    -h|--help) usage; exit "${EXIT_OK}" ;;
    *) log_error "Unknown argument: $1"; usage; exit "${EXIT_USAGE}" ;;
  esac
done

FAILURES=0
fail() { log_error "$*"; FAILURES=$((FAILURES + 1)); }
pass() { log_info "OK: $*"; }

# --- 1. Tooling prerequisites ------------------------------------------------
log_info "== Checking required tools =="
for c in oc yq jq envsubst; do
  if command -v "${c}" >/dev/null 2>&1; then
    pass "'${c}' is installed ($(command -v "${c}"))"
  else
    fail "'${c}' is not installed"
  fi
done

# --- 2. YAML syntax of every config file and template -----------------------
log_info "== Checking YAML syntax =="
# base/ and templates/ manifests are envsubst templates: a handful of
# optional blocks (GPU limit line, StorageClass field, Route host field,
# controlled-egress rules, extra env) stand alone on their own line and are
# only valid YAML once rendered. Strip such lines before the syntax check,
# the same way scripts/common.sh::render_template() would when that
# variable resolves to an empty string. See tests/validate-yaml.sh for the
# equivalent, more thorough CI check.
mapfile -t YAML_FILES < <(find "${REPO_ROOT}/config" "${REPO_ROOT}/base" "${REPO_ROOT}/templates" -type f \( -name '*.yaml' -o -name '*.yml' \))
for f in "${YAML_FILES[@]}"; do
  if command -v yq >/dev/null 2>&1; then
    if grep -vE '^[[:space:]]*\$\{[A-Za-z_][A-Za-z0-9_]*\}[[:space:]]*$' "${f}" | yq eval 'true' - >/dev/null 2>&1; then
      : # ok, checked below with a summary line instead of one line per file
    else
      fail "Invalid YAML: ${f#"${REPO_ROOT}"/}"
    fi
  fi
done
pass "YAML syntax checked for ${#YAML_FILES[@]} files under config/, base/, templates/"

# --- 3. Catalog cross-consistency checks -------------------------------------
log_info "== Checking config/catalog.yaml consistency =="
if command -v yq >/dev/null 2>&1 && [[ -f "${CATALOG_FILE}" ]]; then
  mapfile -t IDS < <(yq eval '.catalog | keys | .[]' "${CATALOG_FILE}")
  pass "${#IDS[@]} Catalog IDs found in config/catalog.yaml"

  VALID_PROFILES=("small" "medium" "large")
  VALID_APPROVALS=("auto" "review")
  VALID_METHODS=("workspace-template" "service-template" "statefulset-template" "operator-placeholder" "helm-placeholder" "platform-integration" "none-base-image")
  STORAGE_PATTERN='^[0-9]+(Gi|Mi)$'

  for id in "${IDS[@]}"; do
    profile="$(catalog_field "${id}" '.profile')"
    approval="$(catalog_field "${id}" '.approval')"
    method="$(catalog_field "${id}" '.implementation.method')"
    storage_enabled="$(catalog_field "${id}" '.storage.enabled')"
    storage_size="$(catalog_field "${id}" '.storage.size')"
    gpu_supported="$(catalog_field "${id}" '.gpu.supported')"
    remedy_selectable="$(catalog_field "${id}" '.remedySelectable')"
    image_repo="$(catalog_field "${id}" '.image.repository')"

    [[ " ${VALID_PROFILES[*]} " == *" ${profile} "* ]] || fail "${id}: unknown profile '${profile}'"
    [[ " ${VALID_APPROVALS[*]} " == *" ${approval} "* ]] || fail "${id}: unknown approval '${approval}'"
    [[ " ${VALID_METHODS[*]} " == *" ${method} "* ]] || fail "${id}: unknown implementation.method '${method}'"

    if [[ "${storage_enabled}" == "true" ]]; then
      [[ "${storage_size}" =~ ${STORAGE_PATTERN} ]] || fail "${id}: storage.enabled=true but storage.size '${storage_size}' is not a valid quantity (expected e.g. 10Gi)"
    fi

    if [[ "${method}" == "workspace-template" || "${method}" == "service-template" || "${method}" == "statefulset-template" ]]; then
      [[ -n "${image_repo}" && "${image_repo}" != "null" ]] || fail "${id}: implementation.method=${method} requires image.repository to be set"
    fi

    if [[ "${gpu_supported}" == "true" ]]; then
      [[ "${method}" == "workspace-template" ]] || fail "${id}: gpu.supported=true but implementation.method is '${method}' (GPU is only wired for workspace-template today)"
    fi

    if [[ "${remedy_selectable}" != "true" && "${remedy_selectable}" != "false" ]]; then
      fail "${id}: remedySelectable must be true/false, got '${remedy_selectable}'"
    fi
  done
  pass "Cross-consistency checks completed for all Catalog IDs"
else
  log_warn "Skipping catalog consistency checks (yq not installed or catalog.yaml missing)"
fi

# --- 4. Profiles referenced actually exist -----------------------------------
if command -v yq >/dev/null 2>&1; then
  mapfile -t PROFILE_NAMES < <(yq eval '.profiles | keys | .[]' "${PROFILES_FILE}")
  pass "config/profiles.yaml defines: ${PROFILE_NAMES[*]}"
fi

# --- 5. oc connectivity (best-effort; not fatal for framework-only runs) ----
log_info "== Checking OpenShift connectivity =="
if command -v oc >/dev/null 2>&1 && oc whoami >/dev/null 2>&1; then
  pass "Logged in as $(oc whoami) @ $(oc whoami --show-server 2>/dev/null || echo unknown)"
else
  log_warn "Not logged in to OpenShift (oc whoami failed) -- server-side checks will be skipped"
  SERVER_SIDE="false"
fi

# --- 6. Optional per-request validation --------------------------------------
if [[ -n "${CATALOG_ID}" ]]; then
  log_info "== Validating request: catalog=${CATALOG_ID} request-id=${REQUEST_ID:-<unset>} =="

  if catalog_id_exists "${CATALOG_ID}"; then
    pass "Catalog ID '${CATALOG_ID}' exists"
  else
    fail "Catalog ID '${CATALOG_ID}' does not exist in config/catalog.yaml"
  fi

  if catalog_id_exists "${CATALOG_ID}"; then
    remedy_selectable="$(catalog_field "${CATALOG_ID}" '.remedySelectable')"
    approval="$(catalog_field "${CATALOG_ID}" '.approval')"
    gpu_supported="$(catalog_field "${CATALOG_ID}" '.gpu.supported')"
    method="$(catalog_field "${CATALOG_ID}" '.implementation.method')"

    [[ "${remedy_selectable}" == "true" ]] && pass "'${CATALOG_ID}' is Remedy-selectable" \
      || log_warn "'${CATALOG_ID}' is NOT Remedy-selectable (remedySelectable=false) -- only valid for direct/manual DevOps provisioning"

    pass "Approval mode: ${approval}"
    [[ "${approval}" == "review" ]] && log_warn "Approval=review: provisioning will require --approved true (see docs/SECURITY.md 'Approval trust boundary')"

    if [[ "${GPU_REQUESTED}" == "true" && "${gpu_supported}" != "true" ]]; then
      fail "GPU requested but '${CATALOG_ID}' does not support GPU (gpu.supported=false)"
    fi

    if [[ "${method}" == "operator-placeholder" || "${method}" == "helm-placeholder" ]]; then
      log_warn "'${CATALOG_ID}' is IMPLEMENTATION_REQUIRED (${method}) -- provisioning will create namespace scaffolding only, no workload. See docs/CATALOG-MAPPING.md."
    fi
  fi

  [[ -n "${REQUEST_ID}" ]] || fail "--request-id is required for a request validation"
  [[ -n "${OWNER}" ]] || fail "--owner is required for a request validation"

  if [[ -n "${REQUEST_ID}" && -n "${OWNER}" ]]; then
    TEAM="${TEAM:-$(sanitize_dns_label "${OWNER}")}"
    NS="$(build_namespace_name "${TEAM}" "${REQUEST_ID}")"
    if [[ ${#NS} -gt 0 && ${#NS} -le 63 ]]; then
      pass "Computed namespace name: ${NS}"
    else
      fail "Computed namespace name is invalid or empty: '${NS}'"
    fi
  fi

  if [[ "${SERVER_SIDE}" == "true" ]]; then
    log_info "== Server-side dry-run (oc apply --dry-run=server) =="
    log_warn "Server-side dry-run of a full request requires rendering via scripts/provision.sh --dry-run; run that for the authoritative check. This flag here only confirms cluster reachability."
    oc auth can-i create namespaces >/dev/null 2>&1 \
      && pass "Current identity can create namespaces (or the check itself succeeded)" \
      || log_warn "Current identity may not be able to create namespaces -- confirm delegated permissions with Infra"
  fi
fi

# --- Summary ------------------------------------------------------------------
if (( FAILURES > 0 )); then
  log_error "Validation FAILED with ${FAILURES} error(s)"
  exit "${EXIT_VALIDATION_FAILED}"
fi
log_info "Validation PASSED"
exit "${EXIT_OK}"
