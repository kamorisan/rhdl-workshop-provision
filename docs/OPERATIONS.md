# Workshop Operations Guide

## Overview

This guide provides operational procedures for managing the OpenShift Dev Spaces + Developer Lightspeed workshop environment.

## Prerequisites

- OpenShift cluster with cluster-admin access
- `oc` CLI configured and authenticated
- Ansible 2.15+ with kubernetes.core and community.crypto collections
- Workshop repository cloned locally

## Initial Deployment

### 1. Prepare Configuration

```bash
cd workshop-provisioning

# Copy example inventory
cp ansible/inventory/example/hosts.yml ansible/inventory/production/hosts.yml

# Copy vault template
cp ansible/group_vars/vault.example.yml ansible/group_vars/vault.yml
```

### 2. Edit Configuration

Edit `ansible/inventory/production/hosts.yml`:

```yaml
all:
  hosts:
    localhost:
      ansible_connection: local
  vars:
    cluster_api_url: "https://api.your-cluster.example.com:6443"
    workshop_user_count: 20
    demo_repository_url: "https://github.com/kamorisan/spring-to-quarkus-sample"
    llm_provider: "openai"
    llm_model: "gpt-4"
    llm_api_base: "https://api.openai.com/v1"
```

Edit `ansible/group_vars/vault.yml`:

```yaml
vault_llm_api_key: "sk-your-api-key-here"
```

Encrypt vault:

```bash
ansible-vault encrypt ansible/group_vars/vault.yml
```

### 3. Run Preflight Checks

```bash
make preflight
```

Or manually:

```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  --tags preflight \
  --ask-vault-pass
```

Review preflight output:
- Cluster API connectivity
- OpenShift version
- Available Operators
- Storage capacity
- Resource estimation

### 4. Provision Workshop

```bash
make provision
```

This will:
1. Install OpenShift GitOps Operator
2. Create Root Application
3. Deploy Operators (Dev Spaces, MTA)
4. Create Platform instances
5. Generate workshop users
6. Create user namespaces and workspaces

Monitor progress:

```bash
# Watch GitOps Applications
oc get applications -n openshift-gitops --watch

# Check Operator status
oc get csv -n openshift-devspaces
oc get csv -n openshift-mta

# Check instances
oc get checluster -n openshift-devspaces
oc get tackle -n openshift-mta
```

### 5. Verify Deployment

```bash
make verify
```

This checks:
- GitOps Operator ready
- All Applications synced
- Dev Spaces ready
- MTA ready
- Solution Server running
- User namespaces created
- Workspaces created

### 6. Retrieve User Credentials

```bash
cat artifacts/workshop-users.csv
```

Format:
```
username,password,namespace
user01,<password>,user01-dev
user02,<password>,user02-dev
```

**IMPORTANT:** This file contains plaintext passwords. Handle securely and delete after distributing to users.

## Day 2 Operations

### Adding More Users

To add more users (e.g., from 20 to 30):

```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  -e workshop_user_count=30 \
  --ask-vault-pass
```

This is idempotent - existing users (01-20) remain unchanged, new users (21-30) are created.

### Reducing User Count

To reduce user count (with explicit confirmation):

```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  -e workshop_user_count=15 \
  -e prune_users=true \
  --ask-vault-pass
```

**WARNING:** This will delete user16-user20 namespaces and all their resources.

### Restarting a Workspace

If a user's workspace is stuck or needs restart:

```bash
# Delete the workspace - GitOps will recreate it
oc delete devworkspace spring-to-quarkus-user01 -n user01-dev

# Wait for GitOps to recreate
oc get devworkspace -n user01-dev --watch
```

### Resetting a User Namespace

To clean a user's namespace without deleting it:

```bash
# Delete all resources except the namespace
oc delete all,devworkspace,pvc --all -n user01-dev

# GitOps will recreate managed resources
oc get all -n user01-dev --watch
```

### Updating Workshop Configuration

To update workshop values (e.g., workspace memory limits):

```bash
# Edit values
vi gitops/config/workshop-values.yaml

# Commit and push
git add gitops/config/workshop-values.yaml
git commit -m "Increase workspace memory limit"
git push

# Argo CD will detect and sync changes automatically
# Or manually sync:
oc -n openshift-gitops patch application workshop-resources --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
oc -n openshift-gitops argocd app sync workshop-resources
```

### Checking Application Health

```bash
# List all Applications
oc get applications -n openshift-gitops

# Get detailed status
oc describe application workshop-operators -n openshift-gitops

# Check sync status
oc get application workshop-operators -n openshift-gitops -o jsonpath='{.status.sync.status}'

# Check health status
oc get application workshop-operators -n openshift-gitops -o jsonpath='{.status.health.status}'
```

### Manual Sync

If automatic sync is disabled or you need to force a sync:

```bash
# Sync specific Application
argocd app sync workshop-operators

# Sync with prune
argocd app sync workshop-operators --prune

# Sync all workshop Applications
argocd app sync -l app.kubernetes.io/part-of=developer-lightspeed-workshop
```

### Accessing Logs

**GitOps Operator:**

```bash
oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller
```

**Dev Spaces:**

```bash
oc logs -n openshift-devspaces -l app.kubernetes.io/component=devspaces
```

**MTA:**

```bash
oc logs -n openshift-mta -l app.kubernetes.io/component=tackle-hub
```

**Solution Server:**

```bash
oc logs -n openshift-mta -l app.kubernetes.io/component=solution-server
```

**User Workspace:**

```bash
oc logs -n user01-dev -l controller.devfile.io/devworkspace_name=spring-to-quarkus-user01
```

## Cleanup

### Remove Only Users

```bash
make destroy-users
```

### Remove Workshop (keep Platform)

```bash
make destroy-workshop
```

### Remove Everything Except GitOps Operator

```bash
make destroy-platform
```

### Complete Removal

```bash
make destroy-all
```

## Backup and Recovery

### Backup User Credentials

Always backup the credentials CSV:

```bash
cp artifacts/workshop-users.csv ~/workshop-backups/users-$(date +%Y%m%d).csv
chmod 600 ~/workshop-backups/users-$(date +%Y%m%d).csv
```

### Backup Solution Server Data

If retaining Solution Server learning data:

```bash
# Identify PVC
oc get pvc -n openshift-mta

# Create snapshot (if supported by StorageClass)
oc create -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: solution-server-snapshot-$(date +%Y%m%d)
  namespace: openshift-mta
spec:
  volumeSnapshotClassName: your-snapshot-class
  source:
    persistentVolumeClaimName: solution-server-db-pvc
EOF
```

### Backup GitOps Repository

The GitOps repository is the source of truth - ensure it is:
- Under version control
- Backed up regularly
- Has branch protection rules

## Monitoring

### Key Metrics to Monitor

**Cluster Resources:**
- CPU/Memory usage per namespace
- PVC usage
- Pod count

**Application Health:**
- Argo CD sync status
- Operator health
- Workspace startup time

**User Activity:**
- Active workspaces
- Solution Server requests
- MTA analysis runs

### Monitoring Commands

```bash
# Resource usage by namespace
oc adm top nodes
oc adm top pods -n user01-dev

# PVC usage
oc get pvc --all-namespaces

# Workspace status
oc get devworkspace --all-namespaces

# Application status
oc get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```

## Security

### Rotating LLM API Key

```bash
# Update vault
ansible-vault edit ansible/group_vars/vault.yml

# Re-run llm_secret role
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  --tags llm \
  --ask-vault-pass

# Restart Solution Server to pick up new key
oc delete pod -n openshift-mta -l app.kubernetes.io/component=solution-server
```

### Rotating User Passwords

```bash
# Generate new passwords
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  -e workshop_password_mode=generated \
  --tags users \
  --ask-vault-pass

# New credentials will be in artifacts/workshop-users.csv
```

### Auditing User Access

```bash
# Check who can access a namespace
oc get rolebindings -n user01-dev

# Check OAuth identity providers
oc get oauth cluster -o yaml

# List workshop users
oc get users | grep ^user
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

## Support

For issues or questions:
1. Check logs (see "Accessing Logs" above)
2. Review [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
3. Contact workshop administrator
