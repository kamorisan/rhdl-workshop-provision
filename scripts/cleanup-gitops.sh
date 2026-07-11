#!/bin/bash
#
# GitOps Applications Cleanup Script
# Removes all workshop GitOps Applications and optionally the Root Application
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
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"

# Options
CLEANUP_ROOT="${CLEANUP_ROOT:-false}"
CLEANUP_SCOPE="${1:-all}"  # all, users, platform

# Logging
LOG_FILE="$ARTIFACTS_DIR/cleanup-gitops-$(date +%Y%m%d-%H%M%S).log"
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
echo "║  GitOps Applications Cleanup Script                            ║"
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

log "Connected to OpenShift as: $(oc whoami)"
log "Cluster: $(oc whoami --show-server)"
log "Cleanup scope: $CLEANUP_SCOPE"
log "Cleanup root: $CLEANUP_ROOT"
echo ""

# Check if openshift-gitops namespace exists
if ! oc get namespace openshift-gitops &> /dev/null; then
    log_warning "openshift-gitops namespace not found. Nothing to clean up."
    exit 0
fi

# List current Applications
log "Current GitOps Applications:"
oc get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>&1 | tee -a "$LOG_FILE"
echo ""

# Confirmation
echo -e "${RED}WARNING: This will delete GitOps Applications and their managed resources.${NC}"
echo ""
echo "Cleanup scope: $CLEANUP_SCOPE"
case "$CLEANUP_SCOPE" in
    users)
        echo "  - workshop-resources (DevWorkspaces, RBAC)"
        echo "  - workshop-namespaces (user namespaces)"
        ;;
    platform)
        echo "  - workshop-resources"
        echo "  - workshop-namespaces"
        echo "  - workshop-platform-instances (Dev Spaces, MTA instances)"
        echo "  - workshop-platform-namespaces"
        ;;
    all)
        echo "  - All workshop Applications"
        echo "  - workshop-operators"
        echo "  - workshop-cluster-config"
        ;;
esac

if [ "$CLEANUP_ROOT" = "true" ]; then
    echo "  - workshop-root (Root Application)"
fi

echo ""
read -p "$(echo -e ${YELLOW}Are you sure you want to proceed? Type 'yes' to confirm:${NC} )" -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    log "Cleanup cancelled by user."
    exit 0
fi

echo ""

# Helper function to delete Application and wait
delete_application() {
    local app_name=$1
    local max_wait=${2:-300}

    if oc get application "$app_name" -n openshift-gitops &> /dev/null; then
        log "Deleting Application: $app_name"
        oc delete application "$app_name" -n openshift-gitops --wait=false 2>&1 | tee -a "$LOG_FILE"

        # Wait for deletion
        local waited=0
        while oc get application "$app_name" -n openshift-gitops &> /dev/null; do
            if [ $waited -ge $max_wait ]; then
                log_warning "Application $app_name still exists after ${max_wait}s"
                break
            fi
            echo -n "."
            sleep 5
            waited=$((waited + 5))
        done
        echo ""

        if ! oc get application "$app_name" -n openshift-gitops &> /dev/null; then
            log_success "Application $app_name deleted"
        else
            log_warning "Application $app_name may still be deleting"
        fi
    else
        log "Application $app_name not found, skipping"
    fi
}

# Delete Applications based on scope
case "$CLEANUP_SCOPE" in
    users)
        log "Cleaning up user resources..."
        delete_application "workshop-resources" 600
        delete_application "workshop-namespaces" 600
        ;;

    platform)
        log "Cleaning up platform and user resources..."
        delete_application "workshop-resources" 600
        delete_application "workshop-namespaces" 600
        delete_application "workshop-platform-instances" 600
        delete_application "workshop-platform-namespaces" 300
        ;;

    all)
        log "Cleaning up all workshop Applications..."
        delete_application "workshop-resources" 600
        delete_application "workshop-namespaces" 600
        delete_application "workshop-platform-instances" 600
        delete_application "workshop-platform-namespaces" 300
        delete_application "workshop-cluster-config" 300
        delete_application "workshop-operators" 600
        ;;

    *)
        log_error "Unknown cleanup scope: $CLEANUP_SCOPE"
        echo "Usage: $0 [users|platform|all]"
        exit 1
        ;;
esac

# Delete Root Application if requested
if [ "$CLEANUP_ROOT" = "true" ]; then
    log "Deleting Root Application..."
    delete_application "workshop-root" 900
fi

echo ""

# Check remaining Applications
log "Remaining GitOps Applications:"
oc get applications -n openshift-gitops 2>&1 | tee -a "$LOG_FILE" || log "No Applications found"

echo ""

# Check for stuck namespaces
log "Checking for stuck namespaces..."
STUCK_NS=$(oc get namespaces --field-selector=status.phase=Terminating -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$STUCK_NS" ]; then
    log_warning "Found stuck namespaces in Terminating state: $STUCK_NS"
    echo ""
    read -p "$(echo -e ${YELLOW}Do you want to force cleanup stuck namespaces? [y/N]:${NC} )" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for ns in $STUCK_NS; do
            if [[ $ns == user*-dev ]] || [[ $ns == openshift-devspaces ]] || [[ $ns == openshift-mta ]] || [[ $ns == workshop-system ]]; then
                log "Removing finalizers from namespace: $ns"
                oc patch namespace "$ns" -p '{"metadata":{"finalizers":null}}' --type=merge 2>&1 | tee -a "$LOG_FILE" || true
            fi
        done
    fi
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Cleanup Complete                                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_success "GitOps Applications cleanup completed"
log "Cleanup log saved to: $LOG_FILE"
echo ""
echo "Next Steps:"
echo "  1. Verify Applications are deleted: oc get applications -n openshift-gitops"
echo "  2. Check for remaining resources: oc get namespaces | grep -E 'user.*-dev|openshift-mta|openshift-devspaces'"
echo "  3. To re-setup GitOps, run: scripts/reset-gitops.sh"
echo ""
