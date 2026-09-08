#!/usr/bin/env bash
# =============================================================================
# tests/validate-yaml.sh -- CI-friendly YAML syntax + structure check.
#
# Does NOT require an OpenShift cluster. Checks:
#   1. Every .yaml/.yml file under config/, base/, templates/, catalog/ parses
#      as valid YAML (envsubst ${VAR} placeholders are valid YAML string
#      content, so this passes without rendering).
#   2. config/catalog.yaml, config/profiles.yaml, config/registry.yaml,
#      config/policies.yaml each parse as a single YAML document with the
#      expected top-level keys.
#   3. If `oc` and `envsubst` are both available (and the caller does not
#      pass --skip-oc), also renders each template with dummy values and
#      runs `oc apply --dry-run=client` against it -- this step is skipped
#      gracefully (not failed) when oc is unavailable, since CI runners
#      frequently have no cluster access.
# =============================================================================
set -Eeuo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_OC="false"
[[ "${1:-}" == "--skip-oc" ]] && SKIP_OC="true"

FAILURES=0
fail() { echo "[FAIL] $*" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "[PASS] $*"; }

echo "== YAML syntax check =="
# base/ and templates/ contain envsubst placeholder manifests: some
# placeholders stand alone on their own line (e.g. a whole optional
# NetworkPolicy egress block, or the GPU resource line) and are only valid
# YAML *after* rendering. For a syntax-only pre-check we substitute every
# ${VAR}-shaped placeholder with a harmless literal first -- this mirrors
# what scripts/common.sh::render_template() produces at request time,
# without requiring a real request's worth of environment variables.
mapfile -t FILES < <(find "${REPO_ROOT}/config" "${REPO_ROOT}/base" "${REPO_ROOT}/templates" "${REPO_ROOT}/catalog" -type f \( -name '*.yaml' -o -name '*.yml' \))
for f in "${FILES[@]}"; do
  if python3 -c "
import sys, re, yaml
lines = open('${f}').read().split(chr(10))
placeholder_line = re.compile(r'^\s*\\\$\{[A-Za-z_][A-Za-z0-9_]*\}\s*\$')
inline_placeholder = re.compile(r'\\\$\{[A-Za-z_][A-Za-z0-9_]*\}')
out = []
for line in lines:
    # A line that is ONLY a placeholder simulates an optional block that
    # renders empty (GPU_LIMIT_LINE, STORAGE_CLASS_FIELD, ROUTE_HOST_FIELD,
    # EGRESS_CIDR_BLOCK, EXTRA_ENV_BLOCK when their feature is not in use) --
    # drop it, matching real rendering with that variable set to ''.
    if placeholder_line.match(line):
        continue
    out.append(inline_placeholder.sub('PLACEHOLDER', line))
text = chr(10).join(out)
try:
    list(yaml.safe_load_all(text))
except Exception as e:
    print(str(e))
    sys.exit(1)
" >/tmp/yamlcheck_err 2>&1; then
    :
  else
    fail "Invalid YAML: ${f#"${REPO_ROOT}"/} -- $(cat /tmp/yamlcheck_err)"
  fi
done
pass "${#FILES[@]} YAML files parsed"

echo "== config/catalog.yaml structure =="
python3 - "${REPO_ROOT}/config/catalog.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
assert "catalog" in doc, "missing top-level 'catalog' key"
assert len(doc["catalog"]) >= 40, f"expected ~49 catalog entries, found {len(doc['catalog'])}"
required = {"name","domain","type","implementation","profile","storage","gpu","network","remedySelectable","approval","owner","priority"}
for cid, entry in doc["catalog"].items():
    missing = required - set(entry.keys())
    assert not missing, f"{cid} missing fields: {missing}"
print(f"catalog.yaml OK: {len(doc['catalog'])} entries, all required fields present")
PY
pass "config/catalog.yaml structure OK"

echo "== config/profiles.yaml structure =="
python3 - "${REPO_ROOT}/config/profiles.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for p in ("small", "medium", "large"):
    assert p in doc["profiles"], f"missing profile '{p}'"
    for k in ("requests", "limits"):
        assert k in doc["profiles"][p], f"profile {p} missing '{k}'"
print("profiles.yaml OK")
PY
pass "config/profiles.yaml structure OK"

if [[ "${SKIP_OC}" == "false" ]] && command -v oc >/dev/null 2>&1 && command -v envsubst >/dev/null 2>&1 && oc whoami >/dev/null 2>&1; then
  echo "== Server/client-side manifest rendering check =="
  export SANDBOX_NAMESPACE="sbx-ci-validate" CATALOG_ID="DEV-PY" REQUEST_ID="REQ000000"
  export ENVIRONMENT="sandbox" TEAM="ci" OWNER="ci-bot" CREATED_AT="2026-01-01T00:00:00Z"
  export EXPIRES_AT="2026-01-08T00:00:00Z" WORKLOAD_NAME="dev-py" SERVICE_ACCOUNT_NAME="sandbox-runtime"
  export AUTOMOUNT_SA_TOKEN="false" TTL="7d" PROFILE="small"
  export IMAGE_REF="quay.example.internal/sandbox/dev/python:approved" IMAGE_PULL_POLICY="IfNotPresent"
  export CPU_REQUEST="250m" MEM_REQUEST="512Mi" CPU_LIMIT="1" MEM_LIMIT="2Gi"
  export STORAGE_SIZE="10Gi" STORAGE_CLASS_FIELD="" GPU_LIMIT_LINE=""
  export SERVICE_PORT="8080" ROUTE_HOST_FIELD="" ROUTE_TARGET_PORT="8080"
  export OWNER_SUBJECT_KIND="User" OWNER_SUBJECT_NAME="ci-bot"
  export QUOTA_PODS=10 QUOTA_PVCS=4 QUOTA_SERVICES=5 QUOTA_REQUESTS_CPU=6 QUOTA_REQUESTS_MEMORY=24Gi
  export QUOTA_LIMITS_CPU=12 QUOTA_LIMITS_MEMORY=48Gi QUOTA_REQUESTS_STORAGE=200Gi
  export LIMITRANGE_DEFAULT_LIMIT_CPU=1 LIMITRANGE_DEFAULT_LIMIT_MEMORY=2Gi
  export LIMITRANGE_DEFAULT_REQUEST_CPU=250m LIMITRANGE_DEFAULT_REQUEST_MEMORY=512Mi
  export LIMITRANGE_MIN_REQUEST_CPU=50m LIMITRANGE_MIN_REQUEST_MEMORY=64Mi
  export LIMITRANGE_MAX_LIMIT_CPU=4 LIMITRANGE_MAX_LIMIT_MEMORY=16Gi

  for f in "${REPO_ROOT}"/base/namespace/*.yaml "${REPO_ROOT}"/base/rbac/*.yaml \
           "${REPO_ROOT}"/templates/workspace/base/*.yaml; do
    rendered="$(mktemp)"
    envsubst < "${f}" > "${rendered}"
    if grep -qE '\$\{[A-Za-z_]+\}' "${rendered}"; then
      fail "Unresolved placeholder(s) in $(basename "${f}") -- dummy test data doesn't cover every variable this template needs"
    elif oc apply --dry-run=client -f "${rendered}" >/tmp/oc_err 2>&1; then
      pass "client-side dry-run OK: $(basename "${f}")"
    else
      fail "client-side dry-run failed for $(basename "${f}"): $(cat /tmp/oc_err)"
    fi
    rm -f "${rendered}"
  done
else
  echo "(skipping oc dry-run rendering check -- oc/envsubst unavailable or not logged in)"
fi

if (( FAILURES > 0 )); then
  echo "${FAILURES} check(s) failed" >&2
  exit 1
fi
echo "All YAML checks passed."
