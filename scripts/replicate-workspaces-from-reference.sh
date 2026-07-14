#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
USER_COUNT=${USER_COUNT:-10}
USERNAME_PREFIX=${USERNAME_PREFIX:-user}
PASSWORD=${PASSWORD:-openshift}
API_URL="https://api.cluster-59m78.59m78.sandbox1272.opentlc.com:6443"

# Reference workspace (user01)
REFERENCE_USER="user01"
REFERENCE_NAMESPACE="${REFERENCE_USER}-devspaces"

echo "=== DevWorkspace Replication from Reference ==="
echo "Reference: ${REFERENCE_USER}"
echo "Target: ${USERNAME_PREFIX}02 - ${USERNAME_PREFIX}$(printf '%02d' ${USER_COUNT})"
echo ""

# Step 1: Export reference workspace and template
echo "Step 1: Exporting reference workspace..."

REFERENCE_WORKSPACE=$(oc get devworkspace -n ${REFERENCE_NAMESPACE} -o name 2>/dev/null | head -1)
if [ -z "$REFERENCE_WORKSPACE" ]; then
  echo "❌ No DevWorkspace found in ${REFERENCE_NAMESPACE}"
  exit 1
fi

WORKSPACE_NAME=$(echo $REFERENCE_WORKSPACE | cut -d'/' -f2)
echo "  Workspace: ${WORKSPACE_NAME}"

# Get template name from workspace
TEMPLATE_NAME=$(oc get devworkspace ${WORKSPACE_NAME} -n ${REFERENCE_NAMESPACE} \
  -o jsonpath='{.spec.contributions[?(@.name=="editor")].kubernetes.name}')

if [ -z "$TEMPLATE_NAME" ]; then
  echo "❌ No editor template found"
  exit 1
fi

echo "  Template: ${TEMPLATE_NAME}"

# Export clean versions
oc get devworkspace ${WORKSPACE_NAME} -n ${REFERENCE_NAMESPACE} -o yaml | \
  grep -v "resourceVersion:\|uid:\|creationTimestamp:\|generation:\|managedFields:\|ownerReferences:\|last-applied-configuration\|selfLink:\|finalizers:\|che.eclipse.org/last-updated-timestamp\|controller.devfile.io/started-at" > /tmp/clean-workspace.yaml

oc get devworkspacetemplate ${TEMPLATE_NAME} -n ${REFERENCE_NAMESPACE} -o yaml | \
  grep -v "resourceVersion:\|uid:\|creationTimestamp:\|generation:\|managedFields:\|ownerReferences:\|last-applied-configuration\|selfLink:" > /tmp/clean-template.yaml

echo "  ✅ Templates exported"

# Step 2: Create workspaces for user02-userN
echo ""
echo "Step 2: Creating workspaces..."

for i in $(seq -f "%02g" 2 ${USER_COUNT}); do
  TARGET_USER="${USERNAME_PREFIX}${i}"
  TARGET_NAMESPACE="${TARGET_USER}-devspaces"

  echo ""
  echo "--- ${TARGET_USER} ---"

  # Check if workspace already exists
  if oc get devworkspace -n ${TARGET_NAMESPACE} -o name 2>/dev/null | grep -q .; then
    echo "  ⚠️  Workspace already exists, skipping"
    continue
  fi

  # Login as target user
  if ! oc login --insecure-skip-tls-verify=true "${API_URL}" \
    -u ${TARGET_USER} -p ${PASSWORD} >/dev/null 2>&1; then
    echo "  ❌ Login failed"
    continue
  fi

  # Generate names
  NEW_WORKSPACE_NAME="${WORKSPACE_NAME}"
  NEW_TEMPLATE_NAME="${TEMPLATE_NAME}-u${i}"

  # Create DevWorkspaceTemplate first
  sed "s|name: ${TEMPLATE_NAME}|name: ${NEW_TEMPLATE_NAME}|g; \
       s|namespace: ${REFERENCE_NAMESPACE}|namespace: ${TARGET_NAMESPACE}|g; \
       /controller.devfile.io\/creator/d" /tmp/clean-template.yaml | \
    oc apply -f - >/dev/null 2>&1

  if [ $? -eq 0 ]; then
    echo "  ✅ Template: ${NEW_TEMPLATE_NAME}"
  else
    echo "  ❌ Template creation failed"
    continue
  fi

  # Create DevWorkspace (stopped state)
  sed "s|name: ${WORKSPACE_NAME}|name: ${NEW_WORKSPACE_NAME}|g; \
       s|namespace: ${REFERENCE_NAMESPACE}|namespace: ${TARGET_NAMESPACE}|g; \
       s|kubernetes:\n      name: ${TEMPLATE_NAME}|kubernetes:\n      name: ${NEW_TEMPLATE_NAME}|g; \
       s|started: true|started: false|g; \
       /controller.devfile.io\/creator/d" /tmp/clean-workspace.yaml | \
    oc apply -f - >/dev/null 2>&1

  if [ $? -eq 0 ]; then
    echo "  ✅ Workspace: ${NEW_WORKSPACE_NAME} (Stopped)"
  else
    echo "  ❌ Workspace creation failed"
  fi
done

# Restore admin context
oc config use-context default/api-cluster-59m78-59m78-sandbox1272-opentlc-com:6443/kube:admin >/dev/null 2>&1

echo ""
echo "=== Summary ==="
echo ""
sleep 3
echo "Workspace Status:"
oc get devworkspace -A | grep -E "NAMESPACE|devspaces"

echo ""
echo "✅ Workspace replication completed!"
echo ""
echo "Users can access their workspaces at:"
echo "https://devspaces.apps.cluster-59m78.59m78.sandbox1272.opentlc.com"
