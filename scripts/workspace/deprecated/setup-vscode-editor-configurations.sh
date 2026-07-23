#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration from environment or defaults
USER_COUNT=${USER_COUNT:-10}
USERNAME_PREFIX=${USERNAME_PREFIX:-user}
NAMESPACE_SUFFIX=${NAMESPACE_SUFFIX:--devspaces}

# Auto-detect cluster API URL
OCP_API_URL=$(oc whoami --show-server 2>/dev/null || true)
if [ -z "$OCP_API_URL" ]; then
  echo "❌ Not logged in to OpenShift cluster"
  exit 1
fi

echo "================================================"
echo "VS Code Editor Configurations Setup"
echo "================================================"
echo ""
echo "Cluster: $OCP_API_URL"
echo "Users: $USER_COUNT (${USERNAME_PREFIX}01-${USERNAME_PREFIX}$(printf '%02d' $USER_COUNT))"
echo "Namespace suffix: $NAMESPACE_SUFFIX"
echo ""
echo "Creating vscode-editor-configurations ConfigMaps..."
echo ""

SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

for i in $(seq -f "%02g" 1 ${USER_COUNT}); do
  USERNAME="${USERNAME_PREFIX}${i}"
  NAMESPACE="${USERNAME}${NAMESPACE_SUFFIX}"

  echo "[$i/$USER_COUNT] Creating ConfigMap in ${NAMESPACE}..."

  # Check namespace exists
  if ! oc get namespace "${NAMESPACE}" &>/dev/null; then
    echo "  ⚠️  Namespace ${NAMESPACE} does not exist, skipping..."
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Create ConfigMap
  cat <<EOF | oc apply -f - >/dev/null 2>&1
apiVersion: v1
kind: ConfigMap
metadata:
  name: vscode-editor-configurations
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/part-of: che.eclipse.org
    workshop.user: "${USERNAME}"
data:
  settings.json: |
    {
      "terminal.integrated.profiles.linux": {
        "bash": {
          "path": "/bin/bash",
          "args": [
            "--login"
          ]
        }
      },
      "terminal.integrated.defaultProfile.linux": "bash",
      "terminal.integrated.inheritEnv": true
    }
EOF

  if [ $? -eq 0 ]; then
    echo "  ✅ ConfigMap created/updated"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "  ❌ Failed to create ConfigMap"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo "Success: ${SUCCESS_COUNT}/${USER_COUNT}"
echo "Skipped: ${SKIP_COUNT}/${USER_COUNT}"
echo "Failed: ${FAIL_COUNT}/${USER_COUNT}"
echo "================================================"

if [ $FAIL_COUNT -eq 0 ]; then
  echo "✅ VS Code editor configurations setup complete!"
  echo ""
  echo "⚠️  Important: Workspaces must be restarted for settings to take effect"
  echo ""
  echo "Restart command for each workspace:"
  echo "  oc patch devworkspace <workspace-name> -n ${USERNAME_PREFIX}XX${NAMESPACE_SUFFIX} --type=merge -p '{\"spec\":{\"started\":false}}'"
  echo "  oc patch devworkspace <workspace-name> -n ${USERNAME_PREFIX}XX${NAMESPACE_SUFFIX} --type=merge -p '{\"spec\":{\"started\":true}}'"
  exit 0
else
  echo "⚠️  Some ConfigMaps failed to create"
  exit 1
fi
