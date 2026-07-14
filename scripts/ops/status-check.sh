#!/bin/bash
#
# Workshop Status Check Script
# Quick status overview of the workshop environment
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Workshop Environment Status Check                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
if ! command -v oc &> /dev/null; then
    echo -e "${RED}✗ oc CLI not found${NC}"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    echo -e "${RED}✗ Not logged in to OpenShift${NC}"
    exit 1
fi

echo -e "${BLUE}Cluster:${NC} $(oc whoami --show-server)"
echo -e "${BLUE}User:${NC} $(oc whoami)"
echo ""

# GitOps Operator
echo "═══ GitOps Operator ═══"
if oc get namespace openshift-gitops &> /dev/null; then
    CSV=$(oc get csv -n openshift-gitops-operator -o jsonpath='{.items[?(@.metadata.name~"openshift-gitops-operator")].status.phase}' 2>/dev/null || echo "Not found")
    if [ "$CSV" = "Succeeded" ]; then
        echo -e "${GREEN}✓${NC} GitOps Operator: Ready"
    else
        echo -e "${YELLOW}⚠${NC} GitOps Operator: $CSV"
    fi

    ARGOCD_PHASE=$(oc get argocd openshift-gitops -n openshift-gitops -o jsonpath='{.status.phase}' 2>/dev/null || echo "Not found")
    if [ "$ARGOCD_PHASE" = "Available" ]; then
        echo -e "${GREEN}✓${NC} Argo CD Instance: Available"
        GITOPS_URL=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null)
        echo "  URL: https://$GITOPS_URL"
    else
        echo -e "${YELLOW}⚠${NC} Argo CD Instance: $ARGOCD_PHASE"
    fi
else
    echo -e "${RED}✗${NC} GitOps not installed"
fi
echo ""

# GitOps Applications
echo "═══ GitOps Applications ═══"
if oc get namespace openshift-gitops &> /dev/null; then
    APPS=$(oc get applications -n openshift-gitops -o json 2>/dev/null || echo '{"items":[]}')
    TOTAL=$(echo "$APPS" | jq -r '.items | length')

    if [ "$TOTAL" -gt 0 ]; then
        SYNCED=$(echo "$APPS" | jq -r '[.items[] | select(.status.sync.status == "Synced")] | length')
        HEALTHY=$(echo "$APPS" | jq -r '[.items[] | select(.status.health.status == "Healthy")] | length')

        echo "Total Applications: $TOTAL"
        echo -e "Synced: ${GREEN}$SYNCED${NC}/$TOTAL"
        echo -e "Healthy: ${GREEN}$HEALTHY${NC}/$TOTAL"
        echo ""
        echo "Application Details:"
        oc get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
    else
        echo -e "${YELLOW}⚠${NC} No Applications found"
    fi
else
    echo -e "${RED}✗${NC} GitOps not installed"
fi
echo ""

# Dev Spaces Operator
echo "═══ Dev Spaces ═══"
if oc get namespace openshift-devspaces &> /dev/null; then
    CSV=$(oc get csv -n openshift-devspaces -o jsonpath='{.items[?(@.metadata.name~"devspaces")].status.phase}' 2>/dev/null || echo "Not found")
    if [ "$CSV" = "Succeeded" ]; then
        echo -e "${GREEN}✓${NC} Dev Spaces Operator: Ready"
    else
        echo -e "${YELLOW}⚠${NC} Dev Spaces Operator: $CSV"
    fi

    CHE_PHASE=$(oc get checluster devspaces -n openshift-devspaces -o jsonpath='{.status.chePhase}' 2>/dev/null || echo "Not found")
    if [ "$CHE_PHASE" = "Active" ] || [ "$CHE_PHASE" = "Available" ]; then
        echo -e "${GREEN}✓${NC} Dev Spaces Instance: $CHE_PHASE"
        DEVSPACES_URL=$(oc get checluster devspaces -n openshift-devspaces -o jsonpath='{.status.cheURL}' 2>/dev/null || oc get route devspaces -n openshift-devspaces -o jsonpath='{.spec.host}' 2>/dev/null)
        echo "  URL: https://$DEVSPACES_URL"
    else
        echo -e "${YELLOW}⚠${NC} Dev Spaces Instance: $CHE_PHASE"
    fi
else
    echo -e "${RED}✗${NC} Dev Spaces not installed"
fi
echo ""

# MTA Operator
echo "═══ MTA ═══"
if oc get namespace openshift-mta &> /dev/null; then
    CSV=$(oc get csv -n openshift-mta -o jsonpath='{.items[?(@.metadata.name~"mta-operator")].status.phase}' 2>/dev/null || echo "Not found")
    if [ "$CSV" = "Succeeded" ]; then
        echo -e "${GREEN}✓${NC} MTA Operator: Ready"
    else
        echo -e "${YELLOW}⚠${NC} MTA Operator: $CSV"
    fi

    if oc get tackle mta -n openshift-mta &> /dev/null; then
        echo -e "${GREEN}✓${NC} MTA Instance: Created"

        # Check Solution Server
        SOLUTION_PODS=$(oc get pods -n openshift-mta -l app.kubernetes.io/component=solution-server --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$SOLUTION_PODS" -gt 0 ]; then
            SOLUTION_READY=$(oc get pods -n openshift-mta -l app.kubernetes.io/component=solution-server --no-headers 2>/dev/null | grep -c "Running" || echo "0")
            echo -e "${GREEN}✓${NC} Solution Server: $SOLUTION_READY/$SOLUTION_PODS pods ready"
        else
            echo -e "${YELLOW}⚠${NC} Solution Server: Not found"
        fi
    else
        echo -e "${YELLOW}⚠${NC} MTA Instance: Not created"
    fi
else
    echo -e "${RED}✗${NC} MTA not installed"
fi
echo ""

# User Namespaces
echo "═══ Workshop Users ═══"
USER_NS_COUNT=$(oc get namespaces -l workshop.user --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$USER_NS_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} User Namespaces: $USER_NS_COUNT"

    # Sample first 3
    echo "Sample namespaces:"
    oc get namespaces -l workshop.user --no-headers | head -3 | awk '{print "  - "$1}'

    # Check workspaces
    TOTAL_WORKSPACES=0
    RUNNING_WORKSPACES=0

    for ns in $(oc get namespaces -l workshop.user -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        WS_COUNT=$(oc get devworkspace -n "$ns" --no-headers 2>/dev/null | wc -l || echo "0")
        TOTAL_WORKSPACES=$((TOTAL_WORKSPACES + WS_COUNT))

        WS_RUNNING=$(oc get devworkspace -n "$ns" -o jsonpath='{.items[?(@.status.phase=="Running")]}' 2>/dev/null | jq -r 'length' || echo "0")
        RUNNING_WORKSPACES=$((RUNNING_WORKSPACES + WS_RUNNING))
    done

    echo -e "Workspaces: ${GREEN}$TOTAL_WORKSPACES${NC} total, $RUNNING_WORKSPACES running"
else
    echo -e "${YELLOW}⚠${NC} No user namespaces found"
fi
echo ""

# OAuth
echo "═══ Authentication ═══"
IDPS=$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}' 2>/dev/null || echo "")
if echo "$IDPS" | grep -q "workshop_htpasswd"; then
    echo -e "${GREEN}✓${NC} Workshop htpasswd provider configured"
else
    echo -e "${YELLOW}⚠${NC} Workshop htpasswd provider not found"
fi

if [ -n "$IDPS" ]; then
    echo "Identity Providers: $IDPS"
fi
echo ""

# Resource Usage (if user has permissions)
echo "═══ Resource Usage ═══"
if oc adm top nodes &> /dev/null; then
    echo "Node Resource Usage:"
    oc adm top nodes 2>/dev/null | head -5
else
    echo -e "${YELLOW}⚠${NC} Cannot retrieve node metrics (requires additional permissions)"
fi
echo ""

# Summary
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Status Summary                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Determine overall status
OVERALL_STATUS="READY"
WARNINGS=""

if ! oc get namespace openshift-gitops &> /dev/null; then
    OVERALL_STATUS="NOT READY"
    WARNINGS="${WARNINGS}\n  - GitOps not installed"
fi

if ! oc get namespace openshift-devspaces &> /dev/null; then
    OVERALL_STATUS="NOT READY"
    WARNINGS="${WARNINGS}\n  - Dev Spaces not installed"
fi

if ! oc get namespace openshift-mta &> /dev/null; then
    OVERALL_STATUS="NOT READY"
    WARNINGS="${WARNINGS}\n  - MTA not installed"
fi

if [ "$USER_NS_COUNT" -eq 0 ]; then
    OVERALL_STATUS="INCOMPLETE"
    WARNINGS="${WARNINGS}\n  - No user namespaces found"
fi

if [ "$OVERALL_STATUS" = "READY" ]; then
    echo -e "${GREEN}✓ Workshop environment is READY${NC}"
elif [ "$OVERALL_STATUS" = "INCOMPLETE" ]; then
    echo -e "${YELLOW}⚠ Workshop environment is INCOMPLETE${NC}"
    echo -e "${WARNINGS}"
else
    echo -e "${RED}✗ Workshop environment is NOT READY${NC}"
    echo -e "${WARNINGS}"
fi
echo ""
