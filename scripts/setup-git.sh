#!/bin/bash
#
# Setup Git Repository for Workshop Provisioning
#

set -e

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Git Repository Setup for GitOps                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Change to project root
cd "$PROJECT_ROOT"

# Check if already a git repo
if [ -d ".git" ]; then
    echo "This is already a git repository."
    echo "Remote: $(git remote get-url origin 2>/dev/null || echo 'No remote set')"
    echo ""
    read -p "Do you want to add/update remote and push? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo "Initializing git repository..."
    git init
fi

echo ""
echo "Enter your GitHub repository URL:"
echo "Example: https://github.com/kamorisan/workshop-provisioning.git"
read -p "Repository URL: " REPO_URL

if [ -z "$REPO_URL" ]; then
    echo "Error: Repository URL cannot be empty"
    exit 1
fi

echo ""
echo "Repository URL: $REPO_URL"
echo ""

# Set remote
if git remote get-url origin &> /dev/null; then
    echo "Updating remote 'origin'..."
    git remote set-url origin "$REPO_URL"
else
    echo "Adding remote 'origin'..."
    git remote add origin "$REPO_URL"
fi

# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    echo ""
    echo "Files to be committed:"
    git status --short
    echo ""
    read -p "Commit these changes? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add .
        git commit -m "Workshop provisioning automation

- Ansible-based bootstrap
- GitOps-based infrastructure management
- Dev Spaces + MTA + Developer Lightspeed
- 2-user test configuration
"
    fi
fi

# Push
echo ""
echo "Pushing to remote repository..."
git branch -M main

if git push -u origin main; then
    echo ""
    echo "✓ Successfully pushed to $REPO_URL"
else
    echo ""
    echo "Push failed. You may need to authenticate or create the repository first."
    echo ""
    echo "Steps:"
    echo "1. Create repository on GitHub: https://github.com/new"
    echo "2. Repository name: workshop-provisioning"
    echo "3. Make it Public or Private"
    echo "4. Do NOT initialize with README (already have files)"
    echo "5. Run this script again, or manually push:"
    echo "   git push -u origin main"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Git Setup Complete                                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Repository: $REPO_URL"
echo ""
echo "Next steps:"
echo "1. Update ansible/inventory/test/hosts.yml:"
echo "   gitops_repo_url: \"$REPO_URL\""
echo ""
echo "2. Run test:"
echo "   ./TEST_QUICK_START.sh"
echo ""
