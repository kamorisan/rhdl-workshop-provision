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

# Ensure admin context
oc config use-context default/api-cluster-59m78-59m78-sandbox1272-opentlc-com:6443/kube:admin >/dev/null 2>&1

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

# Export to temp files
oc get devworkspace ${WORKSPACE_NAME} -n ${REFERENCE_NAMESPACE} -o yaml > /tmp/ref-workspace.yaml
oc get devworkspacetemplate ${TEMPLATE_NAME} -n ${REFERENCE_NAMESPACE} -o yaml > /tmp/ref-template.yaml

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
  NEW_TEMPLATE_NAME="${TEMPLATE_NAME}-${TARGET_USER}"

  # Create DevWorkspaceTemplate
  cat /tmp/ref-template.yaml | \
    awk -v tpl="${TEMPLATE_NAME}" -v new_tpl="${NEW_TEMPLATE_NAME}" -v ns="${TARGET_NAMESPACE}" '
      BEGIN { skip_owner=0 }
      /^  ownerReferences:/ { skip_owner=1; next }
      skip_owner && /^  [a-z]/ { skip_owner=0 }
      skip_owner { next }
      /resourceVersion:|uid:|creationTimestamp:|generation:|managedFields:|last-applied-configuration|selfLink:/ { next }
      /^  name:/ && !done_name { print "  name: " new_tpl; done_name=1; next }
      /^  namespace:/ && !done_ns { print "  namespace: " ns; done_ns=1; next }
      { print }
    ' | oc apply -f - >/dev/null 2>&1

  if [ $? -eq 0 ]; then
    echo "  ✅ Template: ${NEW_TEMPLATE_NAME}"
  else
    echo "  ❌ Template creation failed"
    continue
  fi

  # Create DevWorkspace
  cat /tmp/ref-workspace.yaml | \
    awk -v ws="${WORKSPACE_NAME}" -v ns="${TARGET_NAMESPACE}" -v tpl="${TEMPLATE_NAME}" -v new_tpl="${NEW_TEMPLATE_NAME}" '
      BEGIN { skip_owner=0; skip_finalizers=0 }
      /^  ownerReferences:/ { skip_owner=1; next }
      skip_owner && /^  [a-z]/ { skip_owner=0 }
      skip_owner { next }
      /^  finalizers:/ { skip_finalizers=1; next }
      skip_finalizers && /^  [a-z]/ { skip_finalizers=0 }
      skip_finalizers { next }
      /resourceVersion:|uid:|creationTimestamp:|generation:|managedFields:|last-applied-configuration|selfLink:|che.eclipse.org\/last-updated-timestamp|controller.devfile.io\/started-at|controller.devfile.io\/creator/ { next }
      /^  name:/ && !done_name { print "  name: " ws; done_name=1; next }
      /^  namespace:/ && !done_ns { print "  namespace: " ns; done_ns=1; next }
      /^  started:/ { print "  started: false"; next }
      /^      name: '"${TEMPLATE_NAME}"'$/ { print "      name: " new_tpl; next }
      { print }
    ' | oc apply -f - >/dev/null 2>&1

  if [ $? -eq 0 ]; then
    echo "  ✅ Workspace: ${WORKSPACE_NAME} (Stopped)"
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
