# Quick Reference Guide

## Common Commands

### Provisioning

```bash
# Complete setup (recommended)
./scripts/initial-setup.sh

# Or manual steps
make provision
make verify
```

### Status Checking

```bash
# Overall status
./scripts/status-check.sh

# GitOps Applications
oc get applications -n openshift-gitops

# Operators
oc get csv -n openshift-devspaces
oc get csv -n openshift-mta

# Platform Instances
oc get checluster -n openshift-devspaces
oc get tackle -n openshift-mta

# User Resources
oc get namespaces -l workshop.user
oc get devworkspace -A
```

### User Management

```bash
# Generate user list
./scripts/generate-user-list.sh html

# View credentials
cat artifacts/workshop-users.csv

# Add users (10 → 20)
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  -e workshop_user_count=20 \
  --ask-vault-pass

# Reduce users (with confirmation)
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  -e workshop_user_count=10 \
  -e prune_users=true \
  --ask-vault-pass
```

### Cleanup

```bash
# Remove users only
./scripts/cleanup-gitops.sh users

# Remove platform
./scripts/cleanup-gitops.sh platform

# Remove all GitOps-managed
./scripts/cleanup-gitops.sh all

# Remove everything including root
export CLEANUP_ROOT=true
./scripts/cleanup-gitops.sh all
```

### Reset

```bash
# Reset Applications (keep secrets)
./scripts/reset-gitops.sh applications

# Full reset (new passwords)
./scripts/reset-gitops.sh full
```

## Troubleshooting

### Application Not Syncing

```bash
# Check status
oc describe application workshop-operators -n openshift-gitops

# Manual sync
argocd app sync workshop-operators

# Force refresh
oc patch application workshop-operators -n openshift-gitops \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Workspace Not Starting

```bash
# Check workspace
oc get devworkspace -n user01-dev
oc describe devworkspace spring-to-quarkus-user01 -n user01-dev

# Check pods
oc get pods -n user01-dev

# Check events
oc get events -n user01-dev --sort-by='.lastTimestamp'

# Restart workspace
oc delete devworkspace spring-to-quarkus-user01 -n user01-dev
```

### Operator Issues

```bash
# Check CSV
oc get csv -n openshift-devspaces
oc describe csv <csv-name> -n openshift-devspaces

# Check operator pod
oc get pods -n openshift-devspaces
oc logs -n openshift-devspaces <operator-pod>

# Force operator reconcile
oc delete pod -n openshift-devspaces -l app=devspaces-operator
```

### Solution Server Issues

```bash
# Check pods
oc get pods -n openshift-mta -l app.kubernetes.io/component=solution-server

# Check logs
oc logs -n openshift-mta -l app.kubernetes.io/component=solution-server

# Check LLM secret
oc get secret kai-api-keys -n openshift-mta
oc get secret kai-api-keys -n openshift-mta -o yaml

# Restart Solution Server
oc delete pod -n openshift-mta -l app.kubernetes.io/component=solution-server
```

### User Login Issues

```bash
# Check OAuth
oc get oauth cluster -o yaml

# Check htpasswd secret
oc get secret workshop-htpasswd -n openshift-config

# Extract htpasswd
oc extract secret/workshop-htpasswd -n openshift-config --to=-

# Check user identity
oc get user user01
oc get identity | grep user01

# Restart OAuth pods
oc delete pod -n openshift-authentication -l app=oauth-openshift
```

### Stuck Namespace

```bash
# Check namespace status
oc get namespace user01-dev -o yaml

# Remove finalizers
oc patch namespace user01-dev -p '{"metadata":{"finalizers":null}}' --type=merge

# Force delete pods
oc delete pod --all -n user01-dev --grace-period=0 --force
```

## Useful Queries

### Resource Usage

```bash
# Node resources
oc adm top nodes

# Pod resources per namespace
oc adm top pods -n user01-dev

# All workshop namespaces
for ns in $(oc get ns -l workshop.user -o name); do
  echo "=== $ns ==="
  oc adm top pods -n ${ns#namespace/}
done
```

### Workspace Status

```bash
# All workspaces
oc get devworkspace -A

# Running workspaces
oc get devworkspace -A -o json | jq -r '.items[] | select(.status.phase=="Running") | "\(.metadata.namespace)/\(.metadata.name)"'

# Failed workspaces
oc get devworkspace -A -o json | jq -r '.items[] | select(.status.phase=="Failed") | "\(.metadata.namespace)/\(.metadata.name)"'
```

### Application Health

```bash
# All applications
oc get applications -n openshift-gitops \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status

# Out of sync applications
oc get applications -n openshift-gitops -o json | \
  jq -r '.items[] | select(.status.sync.status != "Synced") | .metadata.name'

# Unhealthy applications
oc get applications -n openshift-gitops -o json | \
  jq -r '.items[] | select(.status.health.status != "Healthy") | .metadata.name'
```

## Variables Quick Reference

### Required Variables

```yaml
# ansible/inventory/production/hosts.yml
cluster_api_url: "https://api.cluster.example.com:6443"
workshop_user_count: 20
demo_repository_url: "https://github.com/kamorisan/spring-to-quarkus-sample"
llm_provider: "openai"
llm_model: "gpt-4"
llm_api_base: "https://api.openai.com/v1"
```

```yaml
# ansible/group_vars/vault.yml (encrypted)
vault_llm_api_key: "sk-..."
```

### Common Overrides

```bash
# User count
-e workshop_user_count=50

# Workspace resources
-e workspace_memory_limit=16Gi
-e workspace_cpu_limit=4000m

# Storage
-e workspace_storage=20Gi
-e solution_server_storage=10Gi

# Operator channels
-e devspaces_channel=stable
-e mta_channel=stable-8.1

# Destroy options
-e destroy_scope=users
-e confirm_destroy=true
-e prune_users=true
```

## File Locations

```
Configuration:
  ansible/inventory/production/hosts.yml
  ansible/group_vars/vault.yml

Outputs:
  artifacts/workshop-users.csv
  artifacts/workshop-user-list.html
  artifacts/*.log

GitOps:
  gitops/config/workshop-values.yaml
  gitops/bootstrap/root-application.yaml

Scripts:
  scripts/initial-setup.sh
  scripts/status-check.sh
  scripts/cleanup-gitops.sh
  scripts/reset-gitops.sh
  scripts/generate-user-list.sh

Docs:
  docs/OPERATIONS.md
  docs/WORKSHOP_GUIDE.md
  docs/TROUBLESHOOTING.md
  docs/DEPLOYMENT_CHECKLIST.md
```

## URLs

```bash
# Get GitOps console
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'

# Get Dev Spaces dashboard
oc get route devspaces -n openshift-devspaces -o jsonpath='{.spec.host}'

# Get MTA Hub (if enabled)
oc get route -n openshift-mta -l app.kubernetes.io/component=tackle-hub -o jsonpath='{.items[0].spec.host}'

# Get OpenShift console
oc whoami --show-console
```

## Emergency Procedures

### Complete Reset

```bash
# 1. Cleanup all
export CLEANUP_ROOT=true
./scripts/cleanup-gitops.sh all

# 2. Verify clean
oc get applications -n openshift-gitops
oc get namespaces | grep -E 'user.*-dev|openshift-mta|openshift-devspaces'

# 3. Re-provision
./scripts/initial-setup.sh
```

### Force Remove Stuck Resources

```bash
# Remove finalizers from Application
oc patch application <app-name> -n openshift-gitops \
  --type json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'

# Remove finalizers from Namespace
oc patch namespace <ns-name> \
  --type json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'

# Force delete
oc delete <resource> <name> --grace-period=0 --force
```

### Recover From Failed Provisioning

```bash
# Check what exists
oc get namespaces
oc get applications -n openshift-gitops
oc get csv -A

# Run cleanup for the level that succeeded
./scripts/cleanup-gitops.sh <users|platform|all>

# Fix configuration issue
vim ansible/inventory/production/hosts.yml

# Re-run setup
./scripts/initial-setup.sh
```

## Testing

```bash
# Test Helm charts
./tests/test-helm-charts.sh

# Dry-run provisioning
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  --check

# Syntax check
ansible-playbook ansible/playbooks/bootstrap.yml --syntax-check

# Validate kustomize
kustomize build gitops/operators
kustomize build gitops/platform-instances
```

## Support

- Check logs: `artifacts/*.log`
- Status: `./scripts/status-check.sh`
- Docs: `docs/TROUBLESHOOTING.md`
- Issues: Review GitOps Application status and events
