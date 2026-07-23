#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVFILE_SOURCE="${SCRIPT_DIR}/../Gitea/coolstore-eap7/devfile.yaml"

# Check if devfile exists
if [ ! -f "$DEVFILE_SOURCE" ]; then
  echo "❌ Source devfile not found: $DEVFILE_SOURCE"
  exit 1
fi

# Get Gitea credentials
GITEA_ROUTE=$(oc get route gitea -n gitea -o jsonpath='{.spec.host}')
ADMIN_USER=$(oc get secret gitea-user-provisioning -n gitea -o jsonpath='{.data.admin-username}' | base64 -d)
ADMIN_PASS=$(oc get secret gitea-user-provisioning -n gitea -o jsonpath='{.data.admin-password}' | base64 -d)

echo "================================================"
echo "Update devfile.yaml in Gitea Repositories"
echo "================================================"
echo "Gitea: https://${GITEA_ROUTE}"
echo "Source: ${DEVFILE_SOURCE}"
echo ""

# Base64 encode devfile content
DEVFILE_B64=$(base64 -i "$DEVFILE_SOURCE")

USER_COUNT=${USER_COUNT:-10}
SUCCESS_COUNT=0
FAIL_COUNT=0

for i in $(seq -f "%02g" 1 ${USER_COUNT}); do
  USERNAME="user${i}"
  REPO="coolstore-eap7"

  echo "[${i}/${USER_COUNT}] Updating ${USERNAME}/${REPO}..."

  # Get current file SHA
  SHA=$(curl -fsS -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "https://${GITEA_ROUTE}/api/v1/repos/${USERNAME}/${REPO}/contents/devfile.yaml" \
    | jq -r '.sha' 2>/dev/null || echo "")

  if [ -z "$SHA" ]; then
    echo "  ⚠️  devfile.yaml not found in ${USERNAME}/${REPO}, skipping..."
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  # Update file via API
  RESPONSE=$(curl -fsS -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X PUT "https://${GITEA_ROUTE}/api/v1/repos/${USERNAME}/${REPO}/contents/devfile.yaml" \
    -H 'Content-Type: application/json' \
    -d "{
      \"message\": \"Update devfile.yaml with che-code endpoint\",
      \"content\": \"${DEVFILE_B64}\",
      \"sha\": \"${SHA}\"
    }" 2>&1)

  if echo "${RESPONSE}" | jq -e '.content.sha' >/dev/null 2>&1; then
    echo "  ✅ Updated successfully"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "  ❌ Update failed"
    echo "${RESPONSE}" | jq '.' 2>/dev/null || echo "${RESPONSE}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo "Success: ${SUCCESS_COUNT}/${USER_COUNT}"
echo "Failed: ${FAIL_COUNT}/${USER_COUNT}"
echo "================================================"

if [ $FAIL_COUNT -eq 0 ]; then
  echo "✅ All repositories updated successfully"
  exit 0
else
  echo "⚠️  Some repositories failed to update"
  exit 1
fi
