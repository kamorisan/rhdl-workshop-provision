#!/bin/bash
#
# Complete Workshop Workspace Setup Script
# Creates che-code templates, sets user permissions, and creates DevWorkspaces for all users
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================"
echo "Complete Workshop Workspace Setup"
echo "================================================"
echo ""

# Step 1: Setup user permissions
echo "Step 1/3: Setting up user permissions..."
"${SCRIPT_DIR}/setup-user-permissions.sh"

echo ""

# Step 2: Create che-code templates
echo "Step 2/3: Creating che-code templates..."
"${SCRIPT_DIR}/setup-che-code-templates.sh"

echo ""

# Step 3: Create DevWorkspaces
echo "Step 3/3: Creating DevWorkspaces..."
"${SCRIPT_DIR}/create-all-workspaces.sh"

echo ""
echo "================================================"
echo "✅ Complete workshop workspace setup finished!"
echo "================================================"
echo ""
echo "All users can now access their workspaces from Dev Spaces dashboard"
echo ""
echo "To verify:"
echo "  oc get devworkspace --all-namespaces | grep spring-to-quarkus"
echo ""
