#!/bin/bash
#
# Workshop Deployment Script
# Reproducible deployment using Ansible Playbooks
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"
INVENTORY="${INVENTORY:-$ANSIBLE_DIR/inventory/production/hosts.yml}"
VAULT_FILE="$ANSIBLE_DIR/group_vars/vault.yml"
ALL_VARS_FILE="$ANSIBLE_DIR/group_vars/all.yml"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"

# Vault password
VAULT_PASSWORD_FILE="${VAULT_PASSWORD_FILE:-}"
VAULT_PASSWORD="${VAULT_PASSWORD:-workshop}"

# Playbooks
PREFLIGHT_PLAYBOOK="$ANSIBLE_DIR/playbooks/preflight.yml"
BOOTSTRAP_PLAYBOOK="$ANSIBLE_DIR/playbooks/bootstrap.yml"

# Logging
mkdir -p "$ARTIFACTS_DIR"
LOG_FILE="$ARTIFACTS_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] ✓${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ✗${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠${NC} $1" | tee -a "$LOG_FILE"
}

# Banner
cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║  Developer Lightspeed Workshop Deployment                 ║
║  Reproducible Ansible-based Provisioning                  ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo ""

log "Starting workshop deployment..."
log "Project root: $PROJECT_ROOT"
log "Inventory: $INVENTORY"
log "Log file: $LOG_FILE"
echo ""

# ============================================================
# Prerequisites Check
# ============================================================
log "Step 1/6: Checking prerequisites..."

if ! command -v oc &> /dev/null; then
    log_error "oc CLI not found"
    exit 1
fi
log_success "oc CLI found"

if ! command -v ansible-playbook &> /dev/null; then
    log_error "ansible-playbook not found"
    exit 1
fi
log_success "Ansible found: $(ansible --version | head -1 | awk '{print $2}')"

if ! oc whoami &> /dev/null; then
    log_error "Not logged in to OpenShift"
    exit 1
fi
log_success "Connected as: $(oc whoami)"

if ! oc auth can-i '*' '*' --all-namespaces &> /dev/null; then
    log_error "cluster-admin permissions required"
    exit 1
fi
log_success "cluster-admin permissions verified"

echo ""

# ============================================================
# Configuration Check
# ============================================================
log "Step 2/6: Verifying configuration..."

if [ ! -f "$INVENTORY" ]; then
    log_error "Inventory not found: $INVENTORY"
    exit 1
fi
log_success "Inventory file exists"

if [ ! -f "$VAULT_FILE" ]; then
    log_error "Vault file not found: $VAULT_FILE"
    exit 1
fi
log_success "Vault file exists"

if [ ! -f "$ALL_VARS_FILE" ]; then
    log_error "all.yml not found: $ALL_VARS_FILE"
    exit 1
fi
log_success "all.yml file exists"

# Check if vault is encrypted
if head -1 "$VAULT_FILE" | grep -q "ANSIBLE_VAULT"; then
    log_success "Vault file is encrypted"
else
    log_warning "Vault file is NOT encrypted (plaintext)"
fi

echo ""

# ============================================================
# Ansible Collections Check
# ============================================================
log "Step 3/6: Checking Ansible collections..."

if ! ansible-galaxy collection list | grep -q "kubernetes.core"; then
    log_warning "kubernetes.core collection not found, installing..."
    ansible-galaxy collection install -r "$ANSIBLE_DIR/requirements.yml" >> "$LOG_FILE" 2>&1
fi
log_success "Ansible collections ready"

echo ""

# ============================================================
# Preflight Checks (Optional - skip if fails)
# ============================================================
log "Step 4/6: Running preflight checks..."

if [ -f "$PREFLIGHT_PLAYBOOK" ]; then
    echo "$VAULT_PASSWORD" | ansible-playbook \
        -i "$INVENTORY" \
        "$PREFLIGHT_PLAYBOOK" \
        --vault-password-file=/dev/stdin \
        -e @"$VAULT_FILE" \
        >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        log_success "Preflight checks passed"
    else
        log_warning "Preflight checks had issues, but continuing..."
    fi
else
    log_warning "Preflight playbook not found, skipping"
fi

echo ""

# ============================================================
# Main Deployment
# ============================================================
log "Step 5/6: Deploying workshop environment..."
log "This will take approximately 20-30 minutes..."
echo ""

START_TIME=$(date +%s)

echo "$VAULT_PASSWORD" | ansible-playbook \
    -i "$INVENTORY" \
    "$BOOTSTRAP_PLAYBOOK" \
    --vault-password-file=/dev/stdin \
    -e @"$VAULT_FILE" \
    2>&1 | tee -a "$LOG_FILE"

ANSIBLE_EXIT_CODE=${PIPESTATUS[0]}
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""

if [ $ANSIBLE_EXIT_CODE -eq 0 ]; then
    log_success "Deployment completed in $(($DURATION / 60))m $(($DURATION % 60))s"
else
    log_error "Deployment failed after $(($DURATION / 60))m $(($DURATION % 60))s"
    log "Check log file: $LOG_FILE"
    exit 1
fi

echo ""

# ============================================================
# Post-Deployment Info
# ============================================================
log "Step 6/6: Gathering deployment information..."

# Get cluster info
CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "unknown")

# Get endpoints
GITOPS_URL=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "not deployed")
DEVSPACES_URL=$(oc get route devspaces -n openshift-devspaces -o jsonpath='{.spec.host}' 2>/dev/null || echo "not deployed")
MTA_URL=$(oc get route mta -n openshift-mta -o jsonpath='{.spec.host}' 2>/dev/null || echo "not deployed")

# Display summary
cat << EOF

╔═══════════════════════════════════════════════════════════╗
║  Deployment Summary                                       ║
╚═══════════════════════════════════════════════════════════╝

Cluster Domain: $CLUSTER_DOMAIN

Endpoints:
  ├─ GitOps Console:  https://$GITOPS_URL
  ├─ Dev Spaces:      https://$DEVSPACES_URL
  └─ MTA Hub:         https://$MTA_URL

User Credentials:
  └─ File: $ARTIFACTS_DIR/workshop-users.csv

Logs:
  └─ Deployment: $LOG_FILE

Next Steps:
  1. Create MTA Secret:
     ./scripts/setup/create-mta-secret.sh

  2. Create Workspaces:
     ./scripts/workspace/create-workspaces-with-secrets.sh

  3. Verify Deployment:
     ./scripts/ops/status-check.sh

  4. Generate User List:
     ./scripts/user/generate-user-list.sh html

EOF

log_success "Workshop deployment completed!"
