#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
USER_COUNT=${USER_COUNT:-10}
USERNAME_PREFIX=${USERNAME_PREFIX:-user}
PASSWORD=${PASSWORD:-openshift}
API_URL="https://api.cluster-59m78.59m78.sandbox1272.opentlc.com:6443"
DEVSPACES_URL="https://devspaces.apps.cluster-59m78.59m78.sandbox1272.opentlc.com"
DEVFILE_URL="https://raw.githubusercontent.com/kamorisan/rhdl-workshop-provision/main/devfile.yaml"

echo "=== DevWorkspace Creation via Dev Spaces API ==="
echo "Target users: ${USERNAME_PREFIX}01 - ${USERNAME_PREFIX}$(printf '%02d' ${USER_COUNT})"
echo "Devfile: ${DEVFILE_URL}"
echo ""

create_workspace_via_api() {
  local USERNAME=$1
  local NAMESPACE="${USERNAME}-devspaces"

  echo "--- ${USERNAME} ---"

  # Check if workspace already exists
  if oc get devworkspace -n ${NAMESPACE} -o name 2>/dev/null | grep -q .; then
    echo "  ⚠️  Workspace already exists, skipping"
    return 0
  fi

  # Login as user to get token
  if ! oc login --insecure-skip-tls-verify=true "${API_URL}" \
    -u "${USERNAME}" -p "${PASSWORD}" >/dev/null 2>&1; then
    echo "  ❌ Login failed"
    return 1
  fi

  # Get user token
  TOKEN=$(oc whoami -t)

  # Create workspace via Dev Spaces API
  # This mimics what the Dashboard does
  RESPONSE=$(curl -sSk -X POST \
    "${DEVSPACES_URL}/api/workspace/devfile?namespace=${NAMESPACE}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: text/yaml" \
    --data-binary @<(curl -sSk "${DEVFILE_URL}") \
    2>&1)

  if echo "$RESPONSE" | grep -q "id"; then
    echo "  ✅ Workspace created via API"
    # Wait a moment for resources to be created
    sleep 3
    return 0
  else
    echo "  ❌ API call failed:"
    echo "     ${RESPONSE}" | head -3
    return 1
  fi
}

# Create workspaces for all users
for i in $(seq -f "%02g" 1 ${USER_COUNT}); do
  USERNAME="${USERNAME_PREFIX}${i}"
  create_workspace_via_api "${USERNAME}"
  echo ""
done

# Restore admin context
oc config use-context default/api-cluster-59m78-59m78-sandbox1272-opentlc-com:6443/kube:admin >/dev/null 2>&1

echo "=== Summary ==="
echo ""
sleep 5
echo "Workspace Status:"
oc get devworkspace -A | grep -E "NAMESPACE|devspaces"

echo ""
echo "✅ Workspace creation completed!"
echo ""
echo "Users can access their workspaces at:"
echo "${DEVSPACES_URL}"
