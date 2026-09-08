#!/usr/bin/env bash
# =============================================================================
# scripts/common.sh -- shared functions for the Enterprise Sandbox Catalog
#                       provisioning framework.
#
# Sourced by every other script in scripts/. Never executed directly.
# =============================================================================
set -Eeuo pipefail

# --- Paths --------------------------------------------------------------
COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${COMMON_SH_DIR}/.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/config"
BASE_DIR="${REPO_ROOT}/base"
TEMPLATES_DIR="${REPO_ROOT}/templates"
CATALOG_FILE="${CONFIG_DIR}/catalog.yaml"
PROFILES_FILE="${CONFIG_DIR}/profiles.yaml"
REGISTRY_FILE="${CONFIG_DIR}/registry.yaml"
POLICIES_FILE="${CONFIG_DIR}/policies.yaml"

# --- Exit codes (stable, meant to be consumed by callers / Remedy) -------
export EXIT_OK=0
export EXIT_USAGE=2
export EXIT_PREREQ_MISSING=10
export EXIT_NOT_LOGGED_IN=11
export EXIT_CATALOG_INVALID=20
export EXIT_CATALOG_ID_UNKNOWN=21
export EXIT_NOT_REMEDY_SELECTABLE=22
export EXIT_APPROVAL_REQUIRED=23
export EXIT_GPU_NOT_SUPPORTED=24
export EXIT_GPU_UNAVAILABLE=25
export EXIT_STORAGE_INVALID=26
export EXIT_NAMESPACE_INVALID=27
export EXIT_NAMESPACE_NOT_MANAGED=28
export EXIT_VALIDATION_FAILED=30
export EXIT_APPLY_FAILED=40
export EXIT_IMPLEMENTATION_REQUIRED=70   # namespace scaffolding created, but
                                          # the platform-service workload is
                                          # pending an operator/chart decision

# --- Logging --------------------------------------------------------------
_ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log_info()  { printf '%s [INFO]  %s\n'  "$(_ts)" "$*" >&2; }
log_warn()  { printf '%s [WARN]  %s\n'  "$(_ts)" "$*" >&2; }
log_error() { printf '%s [ERROR] %s\n'  "$(_ts)" "$*" >&2; }
log_fatal() { printf '%s [FATAL] %s\n'  "$(_ts)" "$*" >&2; }

fatal() {
  local code="$1"; shift
  log_fatal "$*"
  exit "${code}"
}

# --- Cleanup / trap scaffolding --------------------------------------------
# register_temp_file accepts either a file or a directory (e.g. a
# `mktemp -d` working directory) -- cleanup below removes either.
_CLEANUP_FILES=()
register_temp_file() { _CLEANUP_FILES+=("$1"); }
_cleanup_temp_files() {
  # Save/restore the real exit code: this function runs as an EXIT trap, and
  # without doing so its own last command's status (e.g. false when the
  # loop below has nothing to clean up) would silently become the script's
  # final exit code instead of the one that actually triggered the trap.
  local status=$?
  local f
  if (( ${#_CLEANUP_FILES[@]} > 0 )); then
    for f in "${_CLEANUP_FILES[@]}"; do
      [[ -n "${f}" && -e "${f}" ]] && rm -rf "${f}"
    done
  fi
  return "${status}"
}
trap _cleanup_temp_files EXIT

# --- Prerequisite checks ----------------------------------------------------
require_cmd() {
  local missing=()
  local c
  for c in "$@"; do
    command -v "${c}" >/dev/null 2>&1 || missing+=("${c}")
  done
  if (( ${#missing[@]} > 0 )); then
    fatal "${EXIT_PREREQ_MISSING}" "Missing required tool(s): ${missing[*]}. See docs/RUNBOOK.md 'Prerequisites'."
  fi
}

require_oc_login() {
  if ! oc whoami >/dev/null 2>&1; then
    fatal "${EXIT_NOT_LOGGED_IN}" "Not logged in to an OpenShift cluster. Run 'oc login' first."
  fi
  log_info "oc session: $(oc whoami) @ $(oc whoami --show-server 2>/dev/null || echo unknown)"
}

# --- YAML access helpers (yq v4, mikefarah/yq syntax) ----------------------
yq_get() {
  # yq_get <file> <expression>
  local file="$1" expr="$2"
  yq eval "${expr}" "${file}"
}

catalog_field() {
  # catalog_field <CATALOG_ID> <yq-path-under-the-entry, e.g. .profile>
  local id="$1" path="$2"
  yq eval ".catalog[\"${id}\"]${path}" "${CATALOG_FILE}"
}

catalog_id_exists() {
  local id="$1"
  local v
  v="$(yq eval ".catalog[\"${id}\"] // \"\"" "${CATALOG_FILE}")"
  [[ -n "${v}" && "${v}" != "null" ]]
}

profile_field() {
  # profile_field <small|medium|large> <yq-path, e.g. .requests.cpu>
  local profile="$1" path="$2"
  yq eval ".profiles[\"${profile}\"]${path}" "${PROFILES_FILE}"
}

policy_field() {
  local path="$1"
  yq eval "${path}" "${POLICIES_FILE}"
}

registry_field() {
  local path="$1"
  yq eval "${path}" "${REGISTRY_FILE}"
}

# --- Registry resolution (env vars override config/registry.yaml) ----------
resolve_registry_hostname() {
  echo "${QUAY_REGISTRY:-$(registry_field '.registry.hostname')}"
}
resolve_registry_org() {
  echo "${QUAY_ORGANIZATION:-$(registry_field '.registry.organization')}"
}

# Build the final image reference for a Catalog ID.
# Honors an image.digest if one has been pinned in config/catalog.yaml;
# otherwise falls back to the floating "approved" (or configured) tag.
resolve_image_ref() {
  local id="$1"
  local repo digest tag hostname org
  repo="$(catalog_field "${id}" '.image.repository')"
  digest="$(catalog_field "${id}" '.image.digest')"
  tag="$(catalog_field "${id}" '.image.tag')"
  hostname="$(resolve_registry_hostname)"
  org="$(resolve_registry_org)"

  if [[ -z "${repo}" || "${repo}" == "null" ]]; then
    fatal "${EXIT_CATALOG_INVALID}" "Catalog ID ${id} has no direct image repository (implementation.method is likely operator/helm placeholder)."
  fi

  if [[ -n "${digest}" && "${digest}" != "null" ]]; then
    echo "${hostname}/${org}/${repo}@${digest}"
  else
    if [[ "$(policy_field '.images.warnOnFloatingTag')" == "true" ]]; then
      log_warn "Catalog ID ${id} is deployed by floating tag ':${tag}', not an immutable digest. See config/registry.yaml 'imagePromotion'."
    fi
    echo "${hostname}/${org}/${repo}:${tag}"
  fi
}

# --- Namespace naming / RFC1123 sanitization -------------------------------
sanitize_dns_label() {
  # Lowercase, replace invalid chars with '-', collapse repeats, trim to 63,
  # strip leading/trailing '-'.
  local s="$1"
  s="$(echo "${s}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g')"
  s="${s#-}"; s="${s%-}"
  echo "${s:0:63}"
}

build_namespace_name() {
  local team="$1" request_id="$2"
  local prefix
  prefix="$(policy_field '.namespace.prefix')"
  sanitize_dns_label "${prefix}-${team}-${request_id}"
}

is_sandbox_managed_namespace() {
  # Refuses to operate on any namespace not created by this automation.
  # This is the ONLY safety check standing between delete-sandbox.sh and an
  # arbitrary namespace string -- never bypass it.
  local ns="$1"
  local managed_by
  managed_by="$(oc get namespace "${ns}" -o jsonpath='{.metadata.labels.sandbox\.gosi/managed-by}' 2>/dev/null || true)"
  [[ "${managed_by}" == "sandbox-automation" ]]
}

# --- Rendering (envsubst) ---------------------------------------------------
# render_template <template-file> <output-file>
# Relies on the caller having exported every ${VAR} the template references.
# After substitution, fail loudly if any ${...}-shaped placeholder survives
# (an unset/unexported variable is left untouched by envsubst rather than
# blanked, so this catches a missed export instead of shipping literal
# "${FOO}" into a manifest).
render_template() {
  local tmpl="$1" out="$2"
  if [[ ! -f "${tmpl}" ]]; then
    fatal "${EXIT_APPLY_FAILED}" "Template not found: ${tmpl}"
  fi
  envsubst < "${tmpl}" > "${out}"
  if grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "${out}"; then
    log_error "Unresolved placeholder(s) remain after rendering $(basename "${tmpl}"):"
    grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "${out}" >&2 || true
    fatal "${EXIT_APPLY_FAILED}" "Rendering failed for ${tmpl} (missing exported variable)."
  fi
}

# Build the storage class YAML fragment: empty string = omit the field
# entirely (use the cluster default StorageClass), never storageClassName: ""
render_storage_class_field() {
  local sc="${STORAGE_CLASS:-$(policy_field '.storage.defaultClass')}"
  if [[ -z "${sc}" || "${sc}" == "null" ]]; then
    echo ""
  else
    echo "  storageClassName: ${sc}"
  fi
}

# Build the Route host YAML fragment: empty = let OpenShift auto-generate
# the host from the cluster's default wildcard domain.
render_route_host_field() {
  local workload="$1" namespace="$2"
  if [[ -n "${DEFAULT_DOMAIN:-}" ]]; then
    echo "  host: ${workload}-${namespace}.${DEFAULT_DOMAIN}"
  else
    echo ""
  fi
}

# Build the GPU limit line for a Deployment's resources.limits block, or an
# empty string when GPU was not requested. Never auto-requested (Section 11).
render_gpu_limit_line() {
  local want_gpu="$1"
  if [[ "${want_gpu}" == "true" ]]; then
    local resource_name count
    resource_name="$(policy_field '.gpu.resourceName')"
    count="$(policy_field '.gpu.defaultRequestCount')"
    printf '              %s: "%s"\n' "${resource_name}" "${count}"
  else
    echo ""
  fi
}

# --- Quota / LimitRange variable loading (from config/policies.yaml) -------
load_quota_vars() {
  export QUOTA_PODS QUOTA_PVCS QUOTA_SERVICES QUOTA_REQUESTS_CPU
  export QUOTA_REQUESTS_MEMORY QUOTA_LIMITS_CPU QUOTA_LIMITS_MEMORY
  export QUOTA_REQUESTS_STORAGE
  QUOTA_PODS="$(policy_field '.quota.pods')"
  QUOTA_PVCS="$(policy_field '.quota.persistentvolumeclaims')"
  QUOTA_SERVICES="$(policy_field '.quota.services')"
  QUOTA_REQUESTS_CPU="$(policy_field '.quota.requestsCpu')"
  QUOTA_REQUESTS_MEMORY="$(policy_field '.quota.requestsMemory')"
  QUOTA_LIMITS_CPU="$(policy_field '.quota.limitsCpu')"
  QUOTA_LIMITS_MEMORY="$(policy_field '.quota.limitsMemory')"
  QUOTA_REQUESTS_STORAGE="$(policy_field '.quota.requestsStorage')"
}

load_limitrange_vars() {
  export LIMITRANGE_DEFAULT_LIMIT_CPU LIMITRANGE_DEFAULT_LIMIT_MEMORY
  export LIMITRANGE_DEFAULT_REQUEST_CPU LIMITRANGE_DEFAULT_REQUEST_MEMORY
  export LIMITRANGE_MIN_REQUEST_CPU LIMITRANGE_MIN_REQUEST_MEMORY
  export LIMITRANGE_MAX_LIMIT_CPU LIMITRANGE_MAX_LIMIT_MEMORY
  LIMITRANGE_DEFAULT_LIMIT_CPU="$(policy_field '.limitRange.defaultLimitCpu')"
  LIMITRANGE_DEFAULT_LIMIT_MEMORY="$(policy_field '.limitRange.defaultLimitMemory')"
  LIMITRANGE_DEFAULT_REQUEST_CPU="$(policy_field '.limitRange.defaultRequestCpu')"
  LIMITRANGE_DEFAULT_REQUEST_MEMORY="$(policy_field '.limitRange.defaultRequestMemory')"
  LIMITRANGE_MIN_REQUEST_CPU="$(policy_field '.limitRange.minRequestCpu')"
  LIMITRANGE_MIN_REQUEST_MEMORY="$(policy_field '.limitRange.minRequestMemory')"
  LIMITRANGE_MAX_LIMIT_CPU="$(policy_field '.limitRange.maxLimitCpu')"
  LIMITRANGE_MAX_LIMIT_MEMORY="$(policy_field '.limitRange.maxLimitMemory')"
}

# --- TTL / timestamp helpers -------------------------------------------------
ttl_to_seconds() {
  # Accepts <N>d / <N>h (e.g. 7d, 12h). No other unit is supported.
  local ttl="$1"
  local n unit
  [[ "${ttl}" =~ ^([0-9]+)([dh])$ ]] || fatal "${EXIT_USAGE}" "Invalid TTL '${ttl}' (expected e.g. 7d or 12h)."
  n="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]}"
  case "${unit}" in
    d) echo $(( n * 86400 )) ;;
    h) echo $(( n * 3600 )) ;;
  esac
}

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
expires_iso() {
  local ttl="$1" secs
  secs="$(ttl_to_seconds "${ttl}")"
  date -u -d "+${secs} seconds" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -v+"${secs}"S +"%Y-%m-%dT%H:%M:%SZ"   # BSD/macOS date fallback
}

# --- Dry-run helper ----------------------------------------------------------
# apply_manifest <file> <dry_run: true|false>
apply_manifest() {
  local file="$1" dry_run="$2"
  if [[ "${dry_run}" == "true" ]]; then
    log_info "[dry-run] would apply: ${file}"
    oc apply --dry-run=client -f "${file}" >/dev/null
    log_info "[dry-run] client-side validation OK: $(basename "${file}")"
  else
    oc apply -f "${file}"
  fi
}
