#!/bin/bash
#
# Start Workshop Test - 2 Users
#

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Workshop Provisioning Test - 2 Users                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Repository: https://github.com/kamorisan/rhdl-workshop-provision"
echo "Cluster: $(oc whoami --show-server 2>/dev/null || echo 'Not logged in')"
echo "User: $(oc whoami 2>/dev/null || echo 'Not logged in')"
echo ""

# Check if logged in
if ! oc whoami &> /dev/null; then
    echo "❌ Error: Not logged in to OpenShift"
    echo "Please run: oc login"
    exit 1
fi

echo "✓ Connected to OpenShift"
echo ""
echo "Test Configuration:"
echo "  - Users: 2 (user01, user02)"
echo "  - Solution Server: Disabled"
echo "  - GitOps Repo: https://github.com/kamorisan/rhdl-workshop-provision.git"
echo ""

read -p "Start provisioning test? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Test cancelled."
    exit 0
fi

echo ""
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
echo "✓ Preflight checks passed"
echo ""
read -p "Continue with provisioning? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Test stopped after preflight."
    exit 0
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Step 2: Full Provisioning                                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "This will take 15-25 minutes..."
echo ""
echo "You can monitor progress in another terminal:"
echo "  watch -n 5 'oc get applications -n openshift-gitops'"
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

sleep 10  # Wait for resources to settle

./scripts/status-check.sh

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Provisioning Complete!                                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Display user credentials
if [ -f "artifacts/workshop-users.csv" ]; then
    echo "User Credentials:"
    cat artifacts/workshop-users.csv
    echo ""

    # Generate HTML user list
    echo "Generating user list..."
    ./scripts/generate-user-list.sh html
    echo "✓ User list: artifacts/workshop-user-list.html"
    echo ""
fi

# Display endpoints
GITOPS_URL=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not available")
DEVSPACES_URL=$(oc get route devspaces -n openshift-devspaces -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not available")

echo "Service Endpoints:"
echo "  GitOps Console:  https://$GITOPS_URL"
echo "  Dev Spaces:      https://$DEVSPACES_URL"
echo ""

echo "Next Steps:"
echo ""
echo "1. Test user login:"
echo "   oc login -u user01 -p <password-from-csv>"
echo "   oc get pods -n user01-dev"
echo ""
echo "2. Access Dev Spaces:"
echo "   open https://$DEVSPACES_URL"
echo ""
echo "3. Monitor Applications:"
echo "   oc get applications -n openshift-gitops"
echo ""
echo "4. Cleanup when done:"
echo "   ./scripts/cleanup-gitops.sh all"
echo ""
