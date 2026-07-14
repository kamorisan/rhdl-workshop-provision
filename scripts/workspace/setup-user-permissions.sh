#!/bin/bash
set -e

# Configuration from environment or defaults
USER_COUNT=${USER_COUNT:-10}
USERNAME_PREFIX=${USERNAME_PREFIX:-user}

OCP_API_URL=$(oc whoami --show-server 2>/dev/null)
if [ -z "$OCP_API_URL" ]; then
  echo "❌ Not logged in to OpenShift cluster"
  exit 1
fi

echo "================================================"
echo "Workshop User Permissions Setup"
echo "================================================"
echo ""
echo "Cluster: $OCP_API_URL"
echo "Users: $USER_COUNT (${USERNAME_PREFIX}01-${USERNAME_PREFIX}$(printf '%02d' $USER_COUNT))"
echo ""

for i in $(seq 1 ${USER_COUNT}); do
  USERNAME=$(printf "${USERNAME_PREFIX}%02d" $i)
  DEV_NS="${USERNAME}-dev"
  DEVSPACES_NS="${USERNAME}-devspaces"

  echo "[$i/$USER_COUNT] Setting up permissions for ${USERNAME}..."

  # Grant view and edit roles to user in their namespaces
  if oc get namespace "${DEV_NS}" &>/dev/null; then
    oc adm policy add-role-to-user view ${USERNAME} -n ${DEV_NS} 2>/dev/null || true
    oc adm policy add-role-to-user edit ${USERNAME} -n ${DEV_NS} 2>/dev/null || true
  fi

  if oc get namespace "${DEVSPACES_NS}" &>/dev/null; then
    oc adm policy add-role-to-user view ${USERNAME} -n ${DEVSPACES_NS} 2>/dev/null || true
    oc adm policy add-role-to-user edit ${USERNAME} -n ${DEVSPACES_NS} 2>/dev/null || true
  fi

  # Grant view role to devspaces namespace
  oc adm policy add-role-to-user view ${USERNAME} -n openshift-devspaces 2>/dev/null || true

  echo "  ✅ Permissions configured"
done

echo ""
echo "================================================"
echo "✅ User permissions setup complete!"
echo "================================================"
