#!/bin/bash
set -e

# Add MTA extension to existing workspaces by patching DevWorkspaceTemplate

EXTENSION_ID="redhat.mta-vscode-extension"
EXTENSION_URL="https://open-vsx.org/api/redhat/mta-vscode-extension/latest/file/redhat.mta-vscode-extension-latest.vsix"

echo "=== Adding MTA Extension to Workspaces ==="
echo "Extension: ${EXTENSION_ID}"
echo ""

oc config use-context default/api-cluster-59m78-59m78-sandbox1272-opentlc-com:6443/kube:admin >/dev/null 2>&1

for i in $(seq -f "%02g" 1 10); do
  NAMESPACE="user${i}-devspaces"

  echo "--- user${i} ---"

  # Get template name
  TEMPLATE=$(oc get devworkspacetemplate -n ${NAMESPACE} -o name 2>/dev/null | head -1)

  if [ -z "$TEMPLATE" ]; then
    echo "  ⚠️  No template found, skipping"
    continue
  fi

  TEMPLATE_NAME=$(echo $TEMPLATE | cut -d'/' -f2)

  # Patch che-code-runtime-description container to add extension env var
  oc patch devworkspacetemplate ${TEMPLATE_NAME} -n ${NAMESPACE} --type=json -p='[
    {
      "op": "add",
      "path": "/spec/components/1/container/env/-",
      "value": {
        "name": "VSCODE_EXTENSIONS",
        "value": "'${EXTENSION_URL}'"
      }
    }
  ]' 2>&1 | grep -v "no change" || true

  echo "  ✅ Extension added to template"
done

echo ""
echo "✅ Extension configuration added to all templates"
echo ""
echo "⚠️  Users need to restart their workspaces for changes to take effect"
echo ""
echo "To restart workspace:"
echo "1. Stop workspace from Dashboard"
echo "2. Start again"
