#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/devworkspace-template.yaml"

# Configuration from environment or defaults
USER_COUNT=${USER_COUNT:-10}
USERNAME_PREFIX=${USERNAME_PREFIX:-user}
NAMESPACE_SUFFIX=${NAMESPACE_SUFFIX:--devspaces}

# Auto-detect cluster API URL
OCP_API_URL=$(oc whoami --show-server 2>/dev/null)
if [ -z "$OCP_API_URL" ]; then
  echo "❌ Not logged in to OpenShift cluster"
  exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "❌ Template file not found: $TEMPLATE_FILE"
  exit 1
fi

echo "================================================"
echo "Workshop DevWorkspace Bulk Creation"
echo "================================================"
echo ""
echo "Cluster: $OCP_API_URL"
echo "Users: $USER_COUNT (${USERNAME_PREFIX}01-${USERNAME_PREFIX}$(printf '%02d' $USER_COUNT))"
echo "Namespace suffix: $NAMESPACE_SUFFIX"
echo "Template: $TEMPLATE_FILE"
echo ""

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

  # Delete existing DevWorkspace
  oc delete devworkspace spring-to-quarkus-workshop -n ${NAMESPACE} --ignore-not-found=true &>/dev/null 2>&1

  # Create DevWorkspace from template with substitution
  sed -e "s/NAMESPACE_PLACEHOLDER/${NAMESPACE}/g" \
      -e "s/USERNAME_PLACEHOLDER/${USERNAME}/g" \
      "$TEMPLATE_FILE" | oc apply -f - >/dev/null 2>&1

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
