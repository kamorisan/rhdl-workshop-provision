#!/bin/bash
set -e

# ソースSecret
SOURCE_NAMESPACE="openshift-mta"
SOURCE_SECRET="kai-api-keys"

# 対象ユーザー
USERS=("user01" "user02" "user03" "user04" "user05" "user06" "user07" "user08" "user09" "user10")

echo "📦 Copying MTA LLM credentials to user namespaces..."

for user in "${USERS[@]}"; do
  NAMESPACE="${user}-devspaces"

  echo ""
  echo "Processing ${user}..."

  # 名前空間が存在するか確認
  if ! oc get namespace "${NAMESPACE}" &>/dev/null; then
    echo "  ⚠️  Namespace ${NAMESPACE} does not exist, skipping..."
    continue
  fi

  # Secretを取得してコピー
  if oc get secret "${SOURCE_SECRET}" -n "${SOURCE_NAMESPACE}" &>/dev/null; then
    # Secretをエクスポートして、新しい名前空間に適用
    oc get secret "${SOURCE_SECRET}" -n "${SOURCE_NAMESPACE}" -o yaml \
      | sed "s/namespace: ${SOURCE_NAMESPACE}/namespace: ${NAMESPACE}/" \
      | grep -v 'uid:\|resourceVersion:\|creationTimestamp:\|selfLink:' \
      | oc apply -f -

    echo "  ✅ Secret copied to ${NAMESPACE}"
  else
    echo "  ⚠️  Source secret ${SOURCE_SECRET} not found in ${SOURCE_NAMESPACE}"
  fi
done

echo ""
echo "✅ Secret distribution complete!"
echo ""
echo "Verify:"
echo "  oc get secret mta-llm-credentials -n user01-devspaces"
