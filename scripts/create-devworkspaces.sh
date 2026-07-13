#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load configuration
USER_COUNT=${USER_COUNT:-10}
USERNAME_PREFIX=${USERNAME_PREFIX:-user}
NAMESPACE_SUFFIX=${NAMESPACE_SUFFIX:-devspaces}
DEMO_REPO=${DEMO_REPO:-https://github.com/kamorisan/spring-to-quarkus-sample}
DEMO_REVISION=${DEMO_REVISION:-main}

echo "Creating DevWorkspaces for ${USER_COUNT} users..."

for i in $(seq -f "%02g" 1 ${USER_COUNT}); do
  USERNAME="${USERNAME_PREFIX}${i}"
  NAMESPACE="${USERNAME}-${NAMESPACE_SUFFIX}"
  PASSWORD="${USER_PASSWORD:-openshift}"

  echo "Processing ${USERNAME}..."

  # Get user UID
  USER_UID=$(oc get user ${USERNAME} -o jsonpath='{.metadata.uid}' 2>/dev/null)

  if [ -z "$USER_UID" ]; then
    echo "  ⚠️  User ${USERNAME} not found, skipping..."
    continue
  fi

  echo "  User UID: ${USER_UID}"

  # Delete existing DevWorkspace if present (as admin)
  oc delete devworkspace spring-to-quarkus -n ${NAMESPACE} --ignore-not-found=true

  # Login as the user to create workspace with correct creator
  oc login --insecure-skip-tls-verify=true \
    https://api.cluster-59m78.59m78.sandbox1272.opentlc.com:6443 \
    -u ${USERNAME} -p ${PASSWORD} >/dev/null 2>&1

  # Create DevWorkspace - webhook will auto-set creator to current user UID
  cat <<EOF | oc apply -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: spring-to-quarkus
  namespace: ${NAMESPACE}
  labels:
    workshop.user: "${USERNAME}"
spec:
  started: false
  routingClass: che
  contributions:
    - name: editor
      uri: che-incubator/che-code/latest
  template:
    attributes:
      controller.devfile.io/storage-type: per-workspace
    projects:
      - name: spring-petclinic
        git:
          remotes:
            origin: ${DEMO_REPO}
          checkoutFrom:
            revision: ${DEMO_REVISION}
    components:
      - name: dev-tools
        container:
          image: quay.io/devfile/universal-developer-image:ubi8-latest
          memoryRequest: 2Gi
          memoryLimit: 4Gi
          cpuRequest: 500m
          cpuLimit: 2000m
          mountSources: true
          volumeMounts:
            - name: m2
              path: /home/user/.m2
          env:
            - name: MAVEN_OPTS
              value: "-Xmx1g"
      - name: m2
        volume:
          size: 10Gi
    commands:
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
EOF

  echo "  ✅ DevWorkspace created"
done

done

# Restore admin login
oc config use-context default/api-cluster-59m78-59m78-sandbox1272-opentlc-com:6443/kube:admin >/dev/null 2>&1

echo ""
echo "DevWorkspace creation completed!"
echo "Waiting for workspaces to initialize..."
sleep 10

echo ""
echo "Workspace Status:"
oc get devworkspace -A | grep spring-to-quarkus || echo "No workspaces found"
