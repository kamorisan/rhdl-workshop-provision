#!/bin/bash
#
# Quick Test Script for Workshop Provisioning
#

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Workshop Provisioning - Quick Test                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check current directory
if [ ! -f "ansible/playbooks/bootstrap.yml" ]; then
    echo "Error: Please run this script from workshop-provisioning directory"
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
ansible-galaxy collection install -r ansible/requirements.yml --force

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Step 1: Preflight Checks                                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

ansible-playbook ansible/playbooks/bootstrap.yml \
    -i ansible/inventory/test/hosts.yml \
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

ansible-playbook ansible/playbooks/bootstrap.yml \
    -i ansible/inventory/test/hosts.yml \
    -e solution_server_enabled=false \
    -e workshop_user_count=2

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Step 3: Verification                                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

./scripts/status-check.sh

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Test Complete!                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ -f "artifacts/workshop-users.csv" ]; then
    echo "User credentials:"
    cat artifacts/workshop-users.csv
    echo ""
fi

echo "Next steps:"
echo "  1. Generate user list: ./scripts/generate-user-list.sh html"
echo "  2. Monitor Applications: oc get applications -n openshift-gitops --watch"
echo "  3. Test user login: oc login -u user01 -p <password>"
echo "  4. Cleanup when done: ./scripts/cleanup-gitops.sh all"
echo ""

