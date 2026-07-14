#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration from environment or defaults
USER_COUNT=${USER_COUNT:-10}
USERNAME_PREFIX=${USERNAME_PREFIX:-user}
NAMESPACE_SUFFIX=${NAMESPACE_SUFFIX:--dev}
USER_PASSWORD=${USER_PASSWORD:-openshift}
DEVFILE_URL=${DEVFILE_URL:-https://raw.githubusercontent.com/kamorisan/rhdl-workshop-provision/main/devfile.yaml}

# Auto-detect cluster API URL
OCP_API_URL=$(oc whoami --show-server 2>/dev/null)
if [ -z "$OCP_API_URL" ]; then
  echo "❌ Not logged in to OpenShift cluster"
  exit 1
fi

echo "================================================"
echo "Workshop DevWorkspace Bulk Creation"
echo "================================================"
echo ""
echo "Cluster: $OCP_API_URL"
echo "Users: $USER_COUNT (${USERNAME_PREFIX}01-${USERNAME_PREFIX}$(printf '%02d' $USER_COUNT))"
echo "Namespace suffix: $NAMESPACE_SUFFIX"
echo "Devfile URL: $DEVFILE_URL"
echo ""

# Run as cluster-admin (must be logged in with sufficient permissions)

echo "Creating DevWorkspaces for all users..."
echo ""

for i in $(seq 1 ${USER_COUNT}); do
  USERNAME=$(printf "${USERNAME_PREFIX}%02d" $i)
  NAMESPACE="${USERNAME}${NAMESPACE_SUFFIX}"

  echo "[$i/$USER_COUNT] Processing ${USERNAME}..."

  # Check namespace exists
  if ! oc get namespace "${NAMESPACE}" &>/dev/null; then
    echo "  ⚠️  Namespace ${NAMESPACE} does not exist, skipping..."
    continue
  fi

  # Delete existing DevWorkspace (as cluster-admin)
  oc delete devworkspace spring-to-quarkus-workshop -n ${NAMESPACE} --ignore-not-found=true &>/dev/null 2>&1

  # Create DevWorkspace (minimal structure like Dev Spaces UI creates)
  cat <<EOF | oc apply -f - >/dev/null 2>&1
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: spring-to-quarkus-workshop
  namespace: ${NAMESPACE}
  labels:
    workshop.user: "${USERNAME}"
    workshop.type: "developer-lightspeed"
spec:
  started: false
  routingClass: che
  template: {}
  contributions:
    - name: ide
      kubernetes:
        name: che-code-developer-lightspeed
EOF

  if [ $? -eq 0 ]; then
    echo "  ✅ DevWorkspace created"
  else
    echo "  ❌ Failed to create DevWorkspace"
  fi
done

echo ""
echo "================================================"
echo "✅ DevWorkspace creation complete!"
echo "================================================"
echo ""
echo "Verify:"
echo "  oc get devworkspace -n user01${NAMESPACE_SUFFIX}"
echo ""
echo "Access Dev Spaces dashboard to start workspaces"
