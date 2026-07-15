#!/bin/bash
set -e

# Configuration
USER_COUNT=${USER_COUNT:-10}
USERNAME_PREFIX=${USERNAME_PREFIX:-user}
NAMESPACE_SUFFIX=${NAMESPACE_SUFFIX:--devspaces}

OCP_API_URL=$(oc whoami --show-server 2>/dev/null)
if [ -z "$OCP_API_URL" ]; then
  echo "❌ Not logged in to OpenShift cluster"
  exit 1
fi

echo "================================================"
echo "Setup Che-Code Templates for All Users"
echo "================================================"
echo ""

for i in $(seq 1 ${USER_COUNT}); do
  USERNAME=$(printf "${USERNAME_PREFIX}%02d" $i)
  NAMESPACE="${USERNAME}${NAMESPACE_SUFFIX}"

  echo "[$i/$USER_COUNT] Creating che-code template in ${NAMESPACE}..."

  if ! oc get namespace "${NAMESPACE}" &>/dev/null; then
    echo "  ⚠️  Namespace ${NAMESPACE} does not exist, skipping..."
    continue
  fi

  # Create DevWorkspaceTemplate for che-code editor
  cat <<'EOF' | sed "s/NAMESPACE_PLACEHOLDER/${NAMESPACE}/g" | oc apply -f - >/dev/null 2>&1
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspaceTemplate
metadata:
  name: che-code-coolstore-modernization-workshop
  namespace: NAMESPACE_PLACEHOLDER
spec:
  commands:
    - id: init-container-command
      apply:
        component: che-code-injector
    - id: init-che-code-command
      exec:
        component: che-code-runtime
        commandLine: nohup /checode/entrypoint-volume.sh > /checode/entrypoint-logs.txt 2>&1 &
  components:
    - name: che-code-injector
      container:
        image: registry.redhat.io/devspaces/code-rhel8:latest
        command:
          - /entrypoint-init-container.sh
        volumeMounts:
          - name: checode
            path: /checode
    - name: che-code-runtime
      attributes:
        app.kubernetes.io/component: che-code-runtime
        app.kubernetes.io/part-of: che-code.eclipse.org
        controller.devfile.io/container-contribution: true
        che-code.eclipse.org/vscode-extensions:
          - https://open-vsx.org/api/redhat/mta-core/1.5.0/file/redhat.mta-core-1.5.0.vsix
          - https://open-vsx.org/api/redhat/vscode-java/1.33.0/file/redhat.vscode-java-1.33.0.vsix
          - https://open-vsx.org/api/redhat/vscode-xml/0.27.0/file/redhat.vscode-xml-0.27.0.vsix
      container:
        image: registry.redhat.io/devspaces/udi-rhel9:latest
        cpuRequest: 100m
        cpuLimit: 1000m
        memoryRequest: 512Mi
        memoryLimit: 2Gi
        sourceMapping: /projects
        volumeMounts:
          - name: checode
            path: /checode
        env:
          - name: OPENVSX_REGISTRY_URL
            value: "https://open-vsx.org"
        endpoints:
          - name: che-code
            attributes:
              type: main
              cookiesAuthEnabled: true
              discoverable: false
              urlRewriteSupported: true
            targetPort: 3100
            exposure: public
            protocol: https
            secure: true
          - name: code-redirect-1
            targetPort: 13131
            exposure: public
            protocol: https
          - name: code-redirect-2
            targetPort: 13132
            exposure: public
            protocol: https
          - name: code-redirect-3
            targetPort: 13133
            exposure: public
            protocol: https
    - name: checode
      volume:
        ephemeral: true
  events:
    preStart:
      - init-container-command
    postStart:
      - init-che-code-command
EOF

  if [ $? -eq 0 ]; then
    echo "  ✅ Template created"
  else
    echo "  ❌ Failed to create template"
  fi
done

echo ""
echo "================================================"
echo "✅ Che-Code templates setup complete!"
echo "================================================"
