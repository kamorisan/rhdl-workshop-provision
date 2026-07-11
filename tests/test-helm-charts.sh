#!/bin/bash
#
# Test Helm Chart Rendering
# Validates that Helm charts render correctly with different user counts
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Testing Helm Chart Rendering..."
echo ""

# Test namespaces chart
echo "=== Testing workshop-namespaces chart ==="

for user_count in 1 5 10 50; do
    echo "Testing with $user_count users..."

    helm template workshop-namespaces \
        "$PROJECT_ROOT/gitops/workshop/namespaces" \
        -f "$PROJECT_ROOT/gitops/config/workshop-values.yaml" \
        --set workshop.userCount=$user_count \
        --dry-run > /tmp/test-namespaces-$user_count.yaml

    # Count generated namespaces
    ns_count=$(grep -c "kind: Namespace" /tmp/test-namespaces-$user_count.yaml || echo "0")

    if [ "$ns_count" -eq "$user_count" ]; then
        echo "  ✓ Generated $ns_count namespaces (expected $user_count)"
    else
        echo "  ✗ Generated $ns_count namespaces (expected $user_count)"
        exit 1
    fi
done

echo ""

# Test resources chart
echo "=== Testing workshop-resources chart ==="

for user_count in 1 5 10 50; do
    echo "Testing with $user_count users..."

    helm template workshop-resources \
        "$PROJECT_ROOT/gitops/workshop/resources" \
        -f "$PROJECT_ROOT/gitops/config/workshop-values.yaml" \
        --set workshop.userCount=$user_count \
        --dry-run > /tmp/test-resources-$user_count.yaml

    # Count generated resources
    rb_count=$(grep -c "kind: RoleBinding" /tmp/test-resources-$user_count.yaml || echo "0")
    quota_count=$(grep -c "kind: ResourceQuota" /tmp/test-resources-$user_count.yaml || echo "0")
    ws_count=$(grep -c "kind: DevWorkspace" /tmp/test-resources-$user_count.yaml || echo "0")

    if [ "$rb_count" -eq "$user_count" ] && [ "$quota_count" -eq "$user_count" ] && [ "$ws_count" -eq "$user_count" ]; then
        echo "  ✓ Generated $rb_count RoleBindings, $quota_count Quotas, $ws_count Workspaces"
    else
        echo "  ✗ RoleBindings: $rb_count, Quotas: $quota_count, Workspaces: $ws_count (expected $user_count each)"
        exit 1
    fi
done

echo ""

# Test username formatting
echo "=== Testing username formatting ==="

helm template workshop-namespaces \
    "$PROJECT_ROOT/gitops/workshop/namespaces" \
    -f "$PROJECT_ROOT/gitops/config/workshop-values.yaml" \
    --set workshop.userCount=15 \
    --dry-run > /tmp/test-usernames.yaml

# Check for user01, user09, user15
if grep -q "name: user01-dev" /tmp/test-usernames.yaml && \
   grep -q "name: user09-dev" /tmp/test-usernames.yaml && \
   grep -q "name: user15-dev" /tmp/test-usernames.yaml; then
    echo "  ✓ Username formatting correct (user01, user09, user15)"
else
    echo "  ✗ Username formatting issue"
    exit 1
fi

echo ""
echo "=== All Helm chart tests passed! ==="
