#!/bin/bash
#
# Quick Test Script for Workshop Provisioning
#

set -e

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Workshop Provisioning - Quick Test                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check project structure
if [ ! -f "$PROJECT_ROOT/ansible/playbooks/bootstrap.yml" ]; then
    echo "Error: Cannot find ansible/playbooks/bootstrap.yml"
    echo "Project root: $PROJECT_ROOT"
    exit 1
fi

# Check oc login
if ! oc whoami &> /dev/null; then
    echo "Error: Not logged in to OpenShift. Please run: oc login"
    exit 1
fi

echo "Current cluster: $(oc whoami --show-server)"
echo "Current user: $(oc whoami)"
echo ""

# Install Ansible collections
echo "Installing Ansible collections..."
ansible-galaxy collection install -r "$PROJECT_ROOT/ansible/requirements.yml" --force

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Step 1: Preflight Checks                                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

ansible-playbook "$PROJECT_ROOT/ansible/playbooks/bootstrap.yml" \
    -i "$PROJECT_ROOT/ansible/inventory/test/hosts.yml" \
    --tags preflight

echo ""
read -p "Preflight checks passed. Continue with provisioning? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Test cancelled."
    exit 0
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Step 2: Provisioning (2 users, no Solution Server)            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

ansible-playbook "$PROJECT_ROOT/ansible/playbooks/bootstrap.yml" \
    -i "$PROJECT_ROOT/ansible/inventory/test/hosts.yml" \
    -e solution_server_enabled=false \
    -e workshop_user_count=2

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Step 3: Verification                                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

"$PROJECT_ROOT/scripts/status-check.sh"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Test Complete!                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ -f "$PROJECT_ROOT/artifacts/workshop-users.csv" ]; then
    echo "User credentials:"
    cat "$PROJECT_ROOT/artifacts/workshop-users.csv"
    echo ""
fi

echo "Next steps:"
echo "  1. Generate user list: $PROJECT_ROOT/scripts/generate-user-list.sh html"
echo "  2. Monitor Applications: oc get applications -n openshift-gitops --watch"
echo "  3. Test user login: oc login -u user01 -p <password>"
echo "  4. Cleanup when done: $PROJECT_ROOT/scripts/cleanup-gitops.sh all"
echo ""

