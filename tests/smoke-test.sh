#!/usr/bin/env bash
# =============================================================================
# tests/smoke-test.sh -- end-to-end smoke test against a REAL OpenShift
#                         cluster. Requires `oc login` with permission to
#                         create namespaces (or a pre-run scripts/deploy.sh
#                         by a platform admin).
#
# Provisions a small, cheap Catalog ID (WEB-NGINX by default) into a
# disposable namespace, waits for the pod to become Ready, runs
# scripts/health-check.sh, then tears it down with scripts/delete-sandbox.sh.
#
# Usage: tests/smoke-test.sh [CATALOG_ID]
# =============================================================================
set -Eeuo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="${REPO_ROOT}/scripts"

CATALOG_ID="${1:-WEB-NGINX}"
REQUEST_ID="smoketest$(date -u +%s)"
OWNER="ci-smoke-test"
TIMEOUT_SECONDS=180

echo "== Smoke test: ${CATALOG_ID} (request ${REQUEST_ID}) =="

cleanup() {
  echo "== Cleanup: deleting sandbox for ${REQUEST_ID} =="
  "${SCRIPTS}/delete-sandbox.sh" --request-id "${REQUEST_ID}" --force || true
}
trap cleanup EXIT

echo "-- Provisioning --"
"${SCRIPTS}/provision.sh" \
  --catalog "${CATALOG_ID}" \
  --request-id "${REQUEST_ID}" \
  --owner "${OWNER}" \
  --ttl 1h

NAMESPACE="$(oc get namespaces -l "sandbox.gosi/request-id=${REQUEST_ID}" -o jsonpath='{.items[0].metadata.name}')"
[[ -n "${NAMESPACE}" ]] || { echo "Could not resolve namespace for ${REQUEST_ID}" >&2; exit 1; }
echo "Namespace: ${NAMESPACE}"

echo "-- Waiting up to ${TIMEOUT_SECONDS}s for pods to become Ready --"
if ! oc wait --for=condition=Ready pod --all -n "${NAMESPACE}" --timeout="${TIMEOUT_SECONDS}s"; then
  echo "Pods did not become Ready in time; dumping health-check for diagnosis:" >&2
  "${SCRIPTS}/health-check.sh" --namespace "${NAMESPACE}" || true
  exit 1
fi

echo "-- Health check --"
"${SCRIPTS}/health-check.sh" --namespace "${NAMESPACE}"

echo "== Smoke test PASSED for ${CATALOG_ID} =="
