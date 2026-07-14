#!/bin/bash
#
# GitOps Applications Reset Script
# Cleans up and re-creates GitOps Applications
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

# Options
RESET_SCOPE="${1:-applications}"  # applications, full

# Logging
LOG_FILE="$ARTIFACTS_DIR/reset-gitops-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$ARTIFACTS_DIR"

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
echo "║  GitOps Applications Reset Script                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
if ! command -v oc &> /dev/null; then
    log_error "oc CLI not found. Please install OpenShift CLI."
    exit 1
fi

if ! oc whoami &> /dev/null; then
    log_error "Not logged in to OpenShift. Please run: oc login"
    exit 1
fi

if ! command -v ansible-playbook &> /dev/null; then
    log_error "ansible-playbook not found. Please install Ansible."
    exit 1
fi

log "Connected to OpenShift as: $(oc whoami)"
log "Cluster: $(oc whoami --show-server)"
log "Reset scope: $RESET_SCOPE"
echo ""

# Confirmation
echo -e "${YELLOW}This will:${NC}"
echo "  1. Delete existing GitOps Applications"
echo "  2. Wait for cleanup to complete"
case "$RESET_SCOPE" in
    applications)
        echo "  3. Re-create Applications via GitOps bootstrap"
        echo ""
        echo "Note: This keeps the GitOps Operator and re-uses existing Secrets."
        ;;
    full)
        echo "  3. Re-install GitOps Operator"
        echo "  4. Re-create Secrets (htpasswd, LLM, repository)"
        echo "  5. Re-bootstrap entire GitOps environment"
        echo ""
        echo -e "${RED}WARNING: Full reset will regenerate user passwords!${NC}"
        ;;
esac

echo ""
read -p "$(echo -e ${YELLOW}Do you want to proceed? Type 'yes' to confirm:${NC} )" -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    log "Reset cancelled by user."
    exit 0
fi

echo ""

# Step 1: Cleanup existing Applications
log "Step 1: Cleaning up existing GitOps Applications..."

if [ "$RESET_SCOPE" = "full" ]; then
    # Full cleanup including root
    "$SCRIPT_DIR/cleanup-gitops.sh" all <<< "yes" 2>&1 | tee -a "$LOG_FILE"
    export CLEANUP_ROOT=true
    "$SCRIPT_DIR/cleanup-gitops.sh" all <<< "yes" 2>&1 | tee -a "$LOG_FILE"
else
    # Application cleanup only
    "$SCRIPT_DIR/cleanup-gitops.sh" all <<< "yes" 2>&1 | tee -a "$LOG_FILE"
fi

log_success "Cleanup completed"
echo ""

# Wait for cleanup to settle
log "Waiting for cleanup to complete (30 seconds)..."
sleep 30

# Step 2: Re-install GitOps Operator (if full reset)
if [ "$RESET_SCOPE" = "full" ]; then
    log "Step 2: Re-installing GitOps Operator..."

    cd "$PROJECT_ROOT"

    if ansible-playbook ansible/playbooks/bootstrap.yml \
        -i "$INVENTORY" \
        --tags gitops \
        --ask-vault-pass 2>&1 | tee -a "$LOG_FILE"; then
        log_success "GitOps Operator re-installed"
    else
        log_error "GitOps Operator installation failed"
        exit 1
    fi

    echo ""
    log "Waiting for GitOps Operator to stabilize (60 seconds)..."
    sleep 60
fi

# Step 3: Re-create Secrets (if full reset)
if [ "$RESET_SCOPE" = "full" ]; then
    log "Step 3: Re-creating Secrets..."

    cd "$PROJECT_ROOT"

    # Re-create htpasswd users
    log "Re-creating htpasswd users..."
    if ansible-playbook ansible/playbooks/bootstrap.yml \
        -i "$INVENTORY" \
        --tags users \
        --ask-vault-pass 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Users re-created"
    else
        log_error "User creation failed"
        exit 1
    fi

    # Re-create LLM Secret
    log "Re-creating LLM Secret..."
    if ansible-playbook ansible/playbooks/bootstrap.yml \
        -i "$INVENTORY" \
        --tags llm \
        --ask-vault-pass 2>&1 | tee -a "$LOG_FILE"; then
        log_success "LLM Secret re-created"
    else
        log_error "LLM Secret creation failed"
        exit 1
    fi

    # Re-create repository Secret (if needed)
    if grep -q "demo_repository_private.*true" "$INVENTORY"; then
        log "Re-creating repository Secret..."
        if ansible-playbook ansible/playbooks/bootstrap.yml \
            -i "$INVENTORY" \
            --tags repository \
            --ask-vault-pass 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Repository Secret re-created"
        else
            log_warning "Repository Secret creation failed (may not be needed)"
        fi
    fi

    echo ""
fi

# Step 4: Bootstrap GitOps Applications
STEP_NUM=2
if [ "$RESET_SCOPE" = "full" ]; then
    STEP_NUM=4
fi

log "Step $STEP_NUM: Bootstrapping GitOps Applications..."

cd "$PROJECT_ROOT"

# Determine if we need vault password
VAULT_ARG=""
if [ "$RESET_SCOPE" = "full" ]; then
    VAULT_ARG="--ask-vault-pass"
fi

if ansible-playbook ansible/playbooks/bootstrap.yml \
    -i "$INVENTORY" \
    --tags bootstrap \
    $VAULT_ARG 2>&1 | tee -a "$LOG_FILE"; then
    log_success "GitOps Applications bootstrapped"
else
    log_error "GitOps bootstrap failed"
    exit 1
fi

echo ""

# Step 5: Wait for Applications to sync
STEP_NUM=$((STEP_NUM + 1))
log "Step $STEP_NUM: Waiting for Applications to sync..."

log "Monitoring Application sync status (this may take several minutes)..."
echo ""

MAX_WAIT=900  # 15 minutes
WAITED=0
ALL_SYNCED=false

while [ $WAITED -lt $MAX_WAIT ]; do
    # Get Application status
    APP_STATUS=$(oc get applications -n openshift-gitops -o json 2>/dev/null || echo '{"items":[]}')

    TOTAL_APPS=$(echo "$APP_STATUS" | jq -r '.items | length')
    if [ "$TOTAL_APPS" -eq 0 ]; then
        log "No Applications found yet, waiting..."
        sleep 10
        WAITED=$((WAITED + 10))
        continue
    fi

    SYNCED_APPS=$(echo "$APP_STATUS" | jq -r '[.items[] | select(.status.sync.status == "Synced")] | length')
    HEALTHY_APPS=$(echo "$APP_STATUS" | jq -r '[.items[] | select(.status.health.status == "Healthy")] | length')

    log "Applications: $SYNCED_APPS/$TOTAL_APPS Synced, $HEALTHY_APPS/$TOTAL_APPS Healthy"

    if [ "$SYNCED_APPS" -eq "$TOTAL_APPS" ]; then
        log_success "All Applications synced!"
        ALL_SYNCED=true
        break
    fi

    sleep 30
    WAITED=$((WAITED + 30))
done

if [ "$ALL_SYNCED" = "false" ]; then
    log_warning "Not all Applications synced within ${MAX_WAIT}s. Check status manually."
fi

echo ""

# Step 6: Display status
STEP_NUM=$((STEP_NUM + 1))
log "Step $STEP_NUM: Final status check..."

echo ""
log "GitOps Applications:"
oc get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>&1 | tee -a "$LOG_FILE"

echo ""

# Get endpoints
GITOPS_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not found")

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Reset Complete                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_success "GitOps Applications reset completed"
echo ""
echo "Service Endpoints:"
echo "  OpenShift GitOps: https://$GITOPS_ROUTE"
echo ""

if [ "$RESET_SCOPE" = "full" ]; then
    echo "User Credentials:"
    echo "  File: $ARTIFACTS_DIR/workshop-users.csv"
    echo ""
    log_warning "New user passwords have been generated. Distribute new credentials to participants."
    echo ""
fi

log "Reset log saved to: $LOG_FILE"
echo ""
echo "Next Steps:"
echo "  1. Monitor sync status: oc get applications -n openshift-gitops --watch"
echo "  2. Check Application details: oc describe application <app-name> -n openshift-gitops"
echo "  3. Run verification: make verify"
echo ""
