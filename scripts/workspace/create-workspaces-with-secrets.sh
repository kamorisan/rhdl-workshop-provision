#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
USER_COUNT=${USER_COUNT:-10}
USERNAME_PREFIX=${USERNAME_PREFIX:-user}
NAMESPACE_SUFFIX=${NAMESPACE_SUFFIX:-devspaces}
DEVFILE_REPO=${DEVFILE_REPO:-https://github.com/kamorisan/rhdl-workshop-provision}
DEVFILE_REVISION=${DEVFILE_REVISION:-main}
OCP_API_URL=${OCP_API_URL:-https://api.cluster-59m78.59m78.sandbox1272.opentlc.com:6443}
SOURCE_SECRET_NAMESPACE=${SOURCE_SECRET_NAMESPACE:-openshift-mta}
SOURCE_SECRET_NAME=${SOURCE_SECRET_NAME:-kai-api-keys}

echo "================================================"
echo "Workshop DevWorkspace Provisioning with Secrets"
echo "================================================"
echo ""
echo "Step 1: Copy Secrets to user namespaces..."
echo ""

for i in $(seq -f "%02g" 1 ${USER_COUNT}); do
  USERNAME="${USERNAME_PREFIX}${i}"
  NAMESPACE="${USERNAME}-${NAMESPACE_SUFFIX}"

  echo "Processing ${USERNAME}..."

  # Check namespace exists
  if ! oc get namespace "${NAMESPACE}" &>/dev/null; then
    echo "  ⚠️  Namespace ${NAMESPACE} does not exist, skipping..."
    continue
  fi

  # Copy Secret from openshift-mta to user namespace
  if oc get secret "${SOURCE_SECRET_NAME}" -n "${SOURCE_SECRET_NAMESPACE}" &>/dev/null; then
    oc get secret "${SOURCE_SECRET_NAME}" -n "${SOURCE_SECRET_NAMESPACE}" -o yaml \
      | sed "s/namespace: ${SOURCE_SECRET_NAMESPACE}/namespace: ${NAMESPACE}/" \
      | grep -v 'uid:\|resourceVersion:\|creationTimestamp:\|selfLink:' \
      | oc apply -f - &>/dev/null

    echo "  ✅ Secret ${SOURCE_SECRET_NAME} copied to ${NAMESPACE}"
  else
    echo "  ⚠️  Source secret ${SOURCE_SECRET_NAME} not found in ${SOURCE_SECRET_NAMESPACE}"
  fi
done

echo ""
echo "Step 2: Create DevWorkspaces with Secret references..."
echo ""

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

  # Delete existing DevWorkspace
  oc delete devworkspace spring-to-quarkus-workshop -n ${NAMESPACE} --ignore-not-found=true &>/dev/null

  # Login as the user
  if ! oc login --insecure-skip-tls-verify=true \
    "${OCP_API_URL}" \
    -u ${USERNAME} -p ${PASSWORD} >/dev/null 2>&1; then
    echo "  ⚠️  Login failed for ${USERNAME}, skipping..."
    continue
  fi

  # Create DevWorkspace with devfileUrl and Secret override
  cat <<EOF | oc apply -f -
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
  template:
    attributes:
      controller.devfile.io/storage-type: per-workspace
      controller.devfile.io/devworkspace-config-name: devworkspace-config
    components:
      # Override dev-tools environment variables with Secret references
      - name: dev-tools
        attributes:
          controller.devfile.io/merge-contribution: true
        container:
          env:
            # Override MTA_LLM_BASE_URL from Secret
            - name: MTA_LLM_BASE_URL
              valueFrom:
                secretKeyRef:
                  name: ${SOURCE_SECRET_NAME}
                  key: OPENAI_API_BASE
            # Override MTA_LLM_API_KEY from Secret
            - name: MTA_LLM_API_KEY
              valueFrom:
                secretKeyRef:
                  name: ${SOURCE_SECRET_NAME}
                  key: OPENAI_API_KEY
  contributions:
    - name: ide
      kubernetes:
        name: che-code-developer-lightspeed
EOF

  # Apply devfile from repository
  oc patch devworkspace spring-to-quarkus-workshop -n ${NAMESPACE} --type=merge -p "{
    \"spec\": {
      \"template\": {
        \"\$ref\": \"${DEVFILE_REPO}/raw/${DEVFILE_REVISION}/devfile.yaml\"
      }
    }
  }" &>/dev/null || true

  echo "  ✅ DevWorkspace created with Secret references"
done

# Restore admin context
oc config use-context default/api-cluster-59m78-59m78-sandbox1272-opentlc-com:6443/kube:admin >/dev/null 2>&1 || true

echo ""
echo "================================================"
echo "✅ Provisioning Complete!"
echo "================================================"
echo ""
echo "Verify Secrets:"
echo "  oc get secret ${SOURCE_SECRET_NAME} -n user01-devspaces"
echo ""
echo "Verify Workspaces:"
echo "  oc get devworkspace -n user01-devspaces"
echo ""
echo "Check environment variables in running workspace:"
echo "  echo \$MTA_LLM_API_KEY"
