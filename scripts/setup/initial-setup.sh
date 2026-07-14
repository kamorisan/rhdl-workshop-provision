#!/bin/bash
#
# Initial Workshop Setup Script
# Performs complete initial provisioning of the workshop environment
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INVENTORY="${INVENTORY:-$PROJECT_ROOT/ansible/inventory/production/hosts.yml}"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"

# Logging
LOG_FILE="$ARTIFACTS_DIR/initial-setup-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $1" | tee -a "$LOG_FILE"
}

# Banner
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  OpenShift Dev Spaces + Developer Lightspeed Workshop         ║"
echo "║  Initial Setup Script                                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Create artifacts directory
mkdir -p "$ARTIFACTS_DIR"

log "Starting initial workshop setup..."
log "Project root: $PROJECT_ROOT"
log "Inventory: $INVENTORY"
log "Log file: $LOG_FILE"
echo ""

# Step 1: Check prerequisites
log "Step 1/7: Checking prerequisites..."

if ! command -v oc &> /dev/null; then
    log_error "oc CLI not found. Please install OpenShift CLI."
    exit 1
fi
log_success "oc CLI found: $(oc version --client -o yaml | grep gitVersion | awk '{print $2}')"

if ! command -v ansible-playbook &> /dev/null; then
    log_error "ansible-playbook not found. Please install Ansible."
    exit 1
fi
log_success "Ansible found: $(ansible --version | head -1)"

if ! command -v htpasswd &> /dev/null; then
    log_warning "htpasswd not found. It will be needed for user creation."
fi

# Check OpenShift connectivity
if ! oc whoami &> /dev/null; then
    log_error "Not logged in to OpenShift. Please run: oc login"
    exit 1
fi
log_success "Connected to OpenShift as: $(oc whoami)"
log "Cluster: $(oc whoami --show-server)"

# Check cluster-admin
if ! oc auth can-i '*' '*' --all-namespaces &> /dev/null; then
    log_error "Current user does not have cluster-admin permissions."
    exit 1
fi
log_success "User has cluster-admin permissions"

echo ""

# Step 2: Verify configuration
log "Step 2/7: Verifying configuration..."

if [ ! -f "$INVENTORY" ]; then
    log_error "Inventory file not found: $INVENTORY"
    log "Please copy ansible/inventory/example/hosts.yml to ansible/inventory/production/hosts.yml and configure it."
    exit 1
fi
log_success "Inventory file found"

if [ ! -f "$PROJECT_ROOT/ansible/group_vars/vault.yml" ]; then
    log_error "Vault file not found: $PROJECT_ROOT/ansible/group_vars/vault.yml"
    log "Please copy ansible/group_vars/vault.example.yml to ansible/group_vars/vault.yml, configure it, and encrypt with ansible-vault."
    exit 1
fi
log_success "Vault file found"

# Check if vault is encrypted
if grep -q "vault_llm_api_key:" "$PROJECT_ROOT/ansible/group_vars/vault.yml" 2>/dev/null; then
    log_warning "Vault file appears to be unencrypted. It is recommended to encrypt it with: ansible-vault encrypt ansible/group_vars/vault.yml"
fi

echo ""

# Step 3: Display configuration summary
log "Step 3/7: Configuration Summary"

CLUSTER_URL=$(grep "cluster_api_url:" "$INVENTORY" | awk '{print $2}' | tr -d '"' || echo "NOT SET")
USER_COUNT=$(grep "workshop_user_count:" "$INVENTORY" | awk '{print $2}' || echo "10")
DEMO_REPO=$(grep "demo_repository_url:" "$INVENTORY" | awk '{print $2}' | tr -d '"' || echo "NOT SET")

echo ""
echo "  Cluster API URL:       $CLUSTER_URL"
echo "  Workshop User Count:   $USER_COUNT"
echo "  Demo Repository:       $DEMO_REPO"
echo "  Current User:          $(oc whoami)"
echo ""

# Confirmation
read -p "$(echo -e ${YELLOW}Do you want to proceed with the setup? [y/N]:${NC} )" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Setup cancelled by user."
    exit 0
fi

echo ""

# Step 4: Install Ansible collections
log "Step 4/7: Installing Ansible collections..."

cd "$PROJECT_ROOT"
ansible-galaxy collection install -r ansible/requirements.yml --force 2>&1 | tee -a "$LOG_FILE"
log_success "Ansible collections installed"

echo ""

# Step 5: Run preflight checks
log "Step 5/7: Running preflight checks..."

if ansible-playbook ansible/playbooks/bootstrap.yml \
    -i "$INVENTORY" \
    --tags preflight \
    --ask-vault-pass 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Preflight checks passed"
else
    log_error "Preflight checks failed. Please review the errors above."
    exit 1
fi

echo ""

# Step 6: Provision workshop environment
log "Step 6/7: Provisioning workshop environment..."
log "This may take 15-30 minutes depending on cluster performance..."

if ansible-playbook ansible/playbooks/bootstrap.yml \
    -i "$INVENTORY" \
    --ask-vault-pass 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Workshop environment provisioned successfully"
else
    log_error "Provisioning failed. Please review the errors above."
    exit 1
fi

echo ""

# Step 7: Run verification
log "Step 7/7: Running verification checks..."

if ansible-playbook ansible/playbooks/verify.yml \
    -i "$INVENTORY" 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Verification checks passed"
else
    log_warning "Some verification checks failed. Please review above."
fi

echo ""

# Get endpoints
log "Retrieving service endpoints..."

GITOPS_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not found")
DEVSPACES_ROUTE=$(oc get route devspaces -n openshift-devspaces -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not found")

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Setup Complete!                                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_success "Workshop environment is ready!"
echo ""
echo "Service Endpoints:"
echo "  OpenShift GitOps:  https://$GITOPS_ROUTE"
echo "  Dev Spaces:        https://$DEVSPACES_ROUTE"
echo ""
echo "User Credentials:"
echo "  File: $ARTIFACTS_DIR/workshop-users.csv"
echo ""
log "Setup log saved to: $LOG_FILE"
echo ""
echo "Next Steps:"
echo "  1. Review user credentials: cat $ARTIFACTS_DIR/workshop-users.csv"
echo "  2. Access GitOps Console: https://$GITOPS_ROUTE"
echo "  3. Monitor Application sync status: oc get applications -n openshift-gitops"
echo "  4. Distribute credentials to workshop participants"
echo ""
log "Setup completed successfully at $(date)"
