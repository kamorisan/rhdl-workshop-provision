#!/bin/bash
#
# Test Without GitOps (Limited Test)
# GitOpsリポジトリが無い場合の限定的なテスト
#

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Workshop Provisioning - Limited Test (No GitOps)             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "⚠️  WARNING: This test skips GitOps functionality"
echo "    Only tests: Preflight + Users + Secrets"
echo "    Does NOT provision: Operators, Dev Spaces, MTA, Workspaces"
echo ""

read -p "Continue with limited test? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Test cancelled."
    exit 0
fi

# Check oc login
if ! oc whoami &> /dev/null; then
    echo "Error: Not logged in to OpenShift. Please run: oc login"
    exit 1
fi

echo ""
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
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Step 2: Create Users (htpasswd)                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

ansible-playbook ansible/playbooks/users.yml \
    -i ansible/inventory/test/hosts.yml

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Test Complete (Limited)                                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ -f "artifacts/workshop-users.csv" ]; then
    echo "✓ User credentials created:"
    cat artifacts/workshop-users.csv
    echo ""
fi

echo "✓ OAuth configured with workshop_htpasswd identity provider"
echo ""
echo "Verification:"
echo "  oc get oauth cluster -o yaml | grep workshop_htpasswd"
echo "  oc get secret workshop-htpasswd -n openshift-config"
echo ""
echo "Test user login:"
echo "  oc login -u user01 -p <password-from-csv>"
echo ""
echo "⚠️  Note: This test did NOT provision:"
echo "  - GitOps Operator"
echo "  - Dev Spaces Operator"
echo "  - MTA Operator"
echo "  - User Namespaces"
echo "  - Workspaces"
echo ""
echo "For full test, push to Git and run: ./TEST_QUICK_START.sh"
echo ""

# Cleanup option
read -p "Delete created users and OAuth config? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleaning up..."

    # Remove htpasswd identity provider from OAuth
    oc get oauth cluster -o json | \
        jq '.spec.identityProviders = [.spec.identityProviders[] | select(.name != "workshop_htpasswd")]' | \
        oc apply -f -

    # Delete secret
    oc delete secret workshop-htpasswd -n openshift-config --ignore-not-found

    echo "✓ Cleanup complete"
fi

echo ""
