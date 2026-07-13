#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
USER_COUNT=${USER_COUNT:-10}
USERNAME_PREFIX=${USERNAME_PREFIX:-user}
PASSWORD=${PASSWORD:-openshift}
API_URL="https://api.cluster-59m78.59m78.sandbox1272.opentlc.com:6443"
DEVFILE_REPO="https://github.com/kamorisan/rhdl-workshop-provision"

echo "=== DevWorkspace Auto-Creation from devfile.yaml ==="
echo "Target users: ${USERNAME_PREFIX}01 - ${USERNAME_PREFIX}$(printf '%02d' ${USER_COUNT})"
echo "Devfile repo: ${DEVFILE_REPO}"
echo ""

# Function to create DevWorkspace for a user
create_workspace() {
  local USERNAME=$1
  local NAMESPACE="${USERNAME}-devspaces"

  echo "--- ${USERNAME} ---"

  # Check if workspace already exists
  if oc get devworkspace -n ${NAMESPACE} -o name 2>/dev/null | grep -q .; then
    echo "  ⚠️  Workspace already exists, skipping"
    return 0
  fi

  # Login as user
  if ! oc login --insecure-skip-tls-verify=true "${API_URL}" \
    -u "${USERNAME}" -p "${PASSWORD}" >/dev/null 2>&1; then
    echo "  ❌ Login failed"
    return 1
  fi

  # Create DevWorkspace from devfile URL
  # Dev Spaces will automatically create the Editor template
  cat <<EOF | oc apply -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: spring-to-quarkus-workshop
  namespace: ${NAMESPACE}
  annotations:
    che.eclipse.org/devfile-source: |
      scm:
        repo: ${DEVFILE_REPO}
        fileName: devfile.yaml
      factory:
        params: url=${DEVFILE_REPO}
spec:
  started: false
  routingClass: che
  template:
    projects:
      - name: spring-petclinic
        git:
          remotes:
            origin: https://github.com/kamorisan/spring-to-quarkus-sample
          checkoutFrom:
            revision: main
    components:
      - name: dev-tools
        container:
          image: quay.io/devfile/universal-developer-image:ubi8-latest
          memoryRequest: 2Gi
          memoryLimit: 4Gi
          cpuRequest: 500m
          cpuLimit: 2000m
          mountSources: true
          sourceMapping: /projects
          volumeMounts:
            - name: m2
              path: /home/user/.m2
          env:
            - name: MAVEN_OPTS
              value: "-Xmx1g"
            - name: OCP_API_URL
              value: "${API_URL}"
            - name: HOST_USERS
              value: "true"
      - name: m2
        volume:
          size: 10Gi
    commands:
      - id: oc-auto-login
        exec:
          component: dev-tools
          commandLine: |
            #!/bin/bash
            set -e
            USERNAME=\$(echo "\${DEVWORKSPACE_NAMESPACE}" | sed 's/-devspaces$//')
            PASSWORD="openshift"
            echo "🔐 Auto-login to OpenShift as \${USERNAME}..."
            if oc login --insecure-skip-tls-verify=true "\${OCP_API_URL}" -u "\${USERNAME}" -p "\${PASSWORD}" >/dev/null 2>&1; then
              echo "✅ Logged in as \${USERNAME}"
              echo "   Current project: \$(oc project -q)"
              echo ""
              echo "You can now use 'oc' commands without manual login!"
            else
              echo "⚠️  Auto-login failed. You can manually login with:"
              echo "   oc login --insecure-skip-tls-verify=true \${OCP_API_URL} -u \${USERNAME} -p openshift"
            fi
          workingDir: \${PROJECT_SOURCE}
      - id: maven-build
        exec:
          component: dev-tools
          commandLine: mvn clean package -DskipTests
          workingDir: \${PROJECT_SOURCE}/spring-petclinic
      - id: maven-test
        exec:
          component: dev-tools
          commandLine: mvn test
          workingDir: \${PROJECT_SOURCE}/spring-petclinic
      - id: run-app
        exec:
          component: dev-tools
          commandLine: mvn spring-boot:run
          workingDir: \${PROJECT_SOURCE}/spring-petclinic
    events:
      postStart:
        - oc-auto-login
    attributes:
      controller.devfile.io/storage-type: per-workspace
      controller.devfile.io/scc: container-build
EOF

  if [ $? -eq 0 ]; then
    echo "  ✅ DevWorkspace created: spring-to-quarkus-workshop"
  else
    echo "  ❌ Failed to create DevWorkspace"
    return 1
  fi
}

# Create workspaces for all users
for i in $(seq -f "%02g" 1 ${USER_COUNT}); do
  USERNAME="${USERNAME_PREFIX}${i}"
  create_workspace "${USERNAME}"
  echo ""
done

# Restore admin context
oc config use-context default/api-cluster-59m78-59m78-sandbox1272-opentlc-com:6443/kube:admin >/dev/null 2>&1

echo "=== Summary ==="
echo ""
echo "Workspace Status:"
oc get devworkspace -A | grep -E "NAMESPACE|devspaces"

echo ""
echo "✅ Workspace creation completed!"
echo ""
echo "Users can access their workspaces at:"
echo "https://devspaces.apps.cluster-59m78.59m78.sandbox1272.opentlc.com"
echo ""
echo "Workspaces will auto-login to OpenShift on first terminal use!"
