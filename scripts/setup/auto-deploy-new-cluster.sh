#!/bin/bash
#
# Automated Workshop Deployment for New Cluster
# Complete end-to-end deployment without manual intervention
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
INVENTORY_DIR="$ANSIBLE_DIR/inventory/production"
VAULT_FILE="$ANSIBLE_DIR/group_vars/vault.yml"
ALL_VARS_FILE="$ANSIBLE_DIR/group_vars/all.yml"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"

# Create directories
mkdir -p "$INVENTORY_DIR"
mkdir -p "$ARTIFACTS_DIR"

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] ✓${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠${NC} $1"
}

# Banner
cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║  Developer Lightspeed Workshop - New Cluster Deployment   ║
║  Fully Automated Setup with Ansible + GitOps + Scripts    ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo ""

# ============================================================
# Step 1: Prerequisites Check
# ============================================================
log "Step 1/8: Checking prerequisites..."

if ! command -v oc &> /dev/null; then
    log_error "oc CLI not found - install from https://mirror.openshift.com/pub/openshift-v4/clients/ocp/"
    exit 1
fi
log_success "oc CLI found"

if ! command -v ansible-playbook &> /dev/null; then
    log_error "ansible-playbook not found - install with: pip install ansible"
    exit 1
fi
log_success "Ansible found: $(ansible --version | head -1 | awk '{print $2}')"

if ! oc whoami &> /dev/null; then
    log_error "Not logged in to OpenShift cluster"
    log "Please run: oc login <api-url>"
    exit 1
fi

CURRENT_USER=$(oc whoami)
CLUSTER_API=$(oc whoami --show-server)
CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "unknown")

log_success "Connected as: $CURRENT_USER"
log_success "Cluster API: $CLUSTER_API"
log_success "Cluster Domain: $CLUSTER_DOMAIN"

if ! oc auth can-i '*' '*' --all-namespaces &> /dev/null; then
    log_error "cluster-admin permissions required for $CURRENT_USER"
    exit 1
fi
log_success "cluster-admin permissions verified"

echo ""

# ============================================================
# Step 2: Auto-generate Inventory
# ============================================================
log "Step 2/8: Generating inventory configuration..."

cat > "$INVENTORY_DIR/hosts.yml" <<EOFINV
---
all:
  hosts:
    localhost:
      ansible_connection: local
      ansible_python_interpreter: "{{ ansible_playbook_python }}"

  vars:
    # Auto-detected cluster information
    openshift_cluster_api: "$CLUSTER_API"
    openshift_cluster_domain: "$CLUSTER_DOMAIN"
    cluster_api_url: "$CLUSTER_API"
    cluster_validate_certs: false

    # Workshop configuration
    workshop_user_count: 10
    workshop_username_prefix: user
    workshop_user_password: openshift

    # Demo application
    demo_repository_url: https://github.com/kamorisan/coolstore-eap7
    demo_repository_revision: main

    # GitOps (CRITICAL: Root Application depends on this)
    gitops_repo_url: https://github.com/kamorisan/rhdl-workshop-provision.git
    gitops_repo_revision: main
    gitops:
      repo_url: https://github.com/kamorisan/rhdl-workshop-provision.git
      repo_revision: main

    # Operators
    gitops_operator_channel: latest
    devspaces_operator_channel: stable
    mta_operator_channel: stable-v8.1

    # MTA Configuration
    mta_namespace: openshift-mta
    mta_solution_server_enabled: true
EOFINV

log_success "Inventory created: $INVENTORY_DIR/hosts.yml"

echo ""

# ============================================================
# Step 3: Auto-generate Vault (Unencrypted for now)
# ============================================================
log "Step 3/8: Generating vault configuration..."

cat > "$VAULT_FILE" <<EOFVAULT
---
# Workshop User Credentials
vault_workshop_user_password: openshift

# LLM Configuration for MTA Solution Server
vault_llm_api_key: sk-k6yUFWReBsfsLzDmPWFn9w
vault_llm_provider: ChatOpenAI
vault_llm_model: gpt-oss-120b
vault_llm_api_base: https://maas-rhdp.apps.maas.redhatworkshops.io/v1

# Git Credentials (if private repos)
vault_git_username: ""
vault_git_token: ""

# Additional Secrets
vault_htpasswd_secret: ""  # Will be auto-generated
EOFVAULT

log_success "Vault created: $VAULT_FILE (unencrypted)"
log_warning "Remember to encrypt with: ansible-vault encrypt $VAULT_FILE"

echo ""

# ============================================================
# Step 3.5: Update all.yml with cluster information
# ============================================================
log "Step 3.5/8: Updating all.yml with cluster information..."

# Backup original all.yml
cp "$ALL_VARS_FILE" "$ALL_VARS_FILE.bak"

# Update cluster_api_url and gitops repo_url
sed -i.tmp "s|cluster_api_url: \"\"|cluster_api_url: \"$CLUSTER_API\"|g" "$ALL_VARS_FILE"
sed -i.tmp "s|repo_url: \"\"|repo_url: \"https://github.com/kamorisan/rhdl-workshop-provision.git\"|g" "$ALL_VARS_FILE"
sed -i.tmp "s|demo_repository_url: \"https://github.com/kamorisan/spring-to-quarkus-sample\"|demo_repository_url: \"https://github.com/kamorisan/coolstore-eap7\"|g" "$ALL_VARS_FILE"
rm -f "$ALL_VARS_FILE.tmp"

log_success "all.yml updated with cluster information"

echo ""

# ============================================================
# Step 4: Install Ansible Collections
# ============================================================
log "Step 4/8: Installing Ansible collections..."

if [ -f "$ANSIBLE_DIR/requirements.yml" ]; then
    ansible-galaxy collection install -r "$ANSIBLE_DIR/requirements.yml" > /dev/null 2>&1
    log_success "Ansible collections installed"
else
    log_warning "requirements.yml not found, skipping"
fi

echo ""

# ============================================================
# Step 5: Run Ansible Deployment
# ============================================================
log "Step 5/8: Running Ansible deployment (this takes ~20-30 minutes)..."
log "Check progress in: $ARTIFACTS_DIR/deployment-*.log"
echo ""

if [ -f "$SCRIPT_DIR/deploy-workshop.sh" ]; then
    VAULT_PASSWORD="workshop" "$SCRIPT_DIR/deploy-workshop.sh"
else
    log_error "deploy-workshop.sh not found"
    exit 1
fi

echo ""

# ============================================================
# Step 6: Wait for Operators to be Ready
# ============================================================
log "Step 6/8: Waiting for operators to be ready..."

wait_for_operator() {
    local namespace=$1
    local name=$2
    local timeout=600
    local elapsed=0

    log "Waiting for $name in $namespace..."

    while [ $elapsed -lt $timeout ]; do
        if oc get csv -n "$namespace" 2>/dev/null | grep -q "$name.*Succeeded"; then
            log_success "$name is ready"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done

    log_warning "$name did not become ready within ${timeout}s"
    return 1
}

# Wait for GitOps
if oc get namespace openshift-gitops &> /dev/null; then
    wait_for_operator openshift-gitops openshift-gitops-operator
fi

# Wait for Dev Spaces
if oc get namespace openshift-devspaces &> /dev/null; then
    wait_for_operator openshift-operators devspaces
fi

# Wait for MTA
if oc get namespace openshift-mta &> /dev/null; then
    wait_for_operator openshift-mta mta-operator
fi

echo ""

# ============================================================
# Step 7: Wait for Argo CD Applications to Sync
# ============================================================
log "Step 7/8: Waiting for Argo CD Applications to sync..."

if oc get namespace openshift-gitops &> /dev/null; then
    log "Waiting for Applications to be created..."
    sleep 30

    APPS=$(oc get applications -n openshift-gitops -o name 2>/dev/null | wc -l)
    log_success "Found $APPS Argo CD Applications"

    if [ "$APPS" -gt 0 ]; then
        log "Triggering sync for all applications..."
        for app in $(oc get applications -n openshift-gitops -o name 2>/dev/null); do
            oc patch "$app" -n openshift-gitops --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}' &> /dev/null || true
        done

        log "Waiting 60 seconds for sync to complete..."
        sleep 60
    fi
fi

echo ""

# ============================================================
# Step 8: Create DevWorkspaces
# ============================================================
log "Step 8/8: Creating DevWorkspaces for all users..."

if [ -f "$PROJECT_ROOT/scripts/workspace/setup-all-workspaces.sh" ]; then
    cd "$PROJECT_ROOT"
    ./scripts/workspace/setup-all-workspaces.sh
    log_success "DevWorkspaces created for 10 users"
else
    log_warning "Workspace creation script not found"
fi

echo ""

# ============================================================
# Deployment Summary
# ============================================================

GITOPS_URL=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "not-deployed")
DEVSPACES_URL=$(oc get route devspaces -n openshift-devspaces -o jsonpath='{.spec.host}' 2>/dev/null || echo "not-deployed")
MTA_URL=$(oc get route tackle -n openshift-mta -o jsonpath='{.spec.host}' 2>/dev/null || echo "not-deployed")
CONSOLE_URL="console-openshift-console.apps.$CLUSTER_DOMAIN"

cat << EOF

╔═══════════════════════════════════════════════════════════╗
║  Deployment Complete!                                     ║
╚═══════════════════════════════════════════════════════════╝

Cluster Information:
  ├─ API:            $CLUSTER_API
  ├─ Domain:         $CLUSTER_DOMAIN
  └─ Console:        https://$CONSOLE_URL

Workshop Endpoints:
  ├─ GitOps:         https://$GITOPS_URL
  ├─ Dev Spaces:     https://$DEVSPACES_URL
  └─ MTA Hub:        https://$MTA_URL

Workshop Users:
  ├─ Count:          10 (user01 - user10)
  ├─ Password:       openshift
  └─ Namespaces:     userXX-dev, userXX-devspaces

Access:
  1. Login to Dev Spaces: https://$DEVSPACES_URL
  2. Username: user01 (or user02, user03, ... user10)
  3. Password: openshift
  4. Your workspace will be available in the dashboard

Configuration Files:
  ├─ Inventory:      $INVENTORY_DIR/hosts.yml
  ├─ Vault:          $VAULT_FILE
  └─ Artifacts:      $ARTIFACTS_DIR/

Verification:
  # Check Argo CD Applications
  oc get applications -n openshift-gitops

  # Check DevWorkspaces
  oc get devworkspace -n user01-devspaces

  # Check user namespaces
  oc get namespaces | grep user

Next Steps (Optional):
  1. Encrypt vault: ansible-vault encrypt $VAULT_FILE
  2. Check status: ./scripts/ops/status-check.sh
  3. Generate user list: ./scripts/user/generate-user-list.sh

EOF

log_success "Automated deployment completed successfully!"
log "Workshop is ready for participants"
