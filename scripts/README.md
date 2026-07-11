# Workshop Scripts

This directory contains operational scripts for managing the workshop environment.

## Available Scripts

### Initial Setup and Provisioning

#### `initial-setup.sh`
Complete initial provisioning of the workshop environment.

**Usage:**
```bash
./scripts/initial-setup.sh
```

**What it does:**
1. Checks prerequisites (oc, ansible, htpasswd)
2. Verifies configuration files
3. Installs Ansible collections
4. Runs preflight checks
5. Provisions complete workshop environment
6. Runs verification checks
7. Displays endpoints and credentials

**Requirements:**
- `ansible/inventory/production/hosts.yml` configured
- `ansible/group_vars/vault.yml` configured and encrypted
- Logged in to OpenShift with cluster-admin

### GitOps Management

#### `cleanup-gitops.sh`
Cleanup GitOps Applications and resources.

**Usage:**
```bash
./scripts/cleanup-gitops.sh [users|platform|all]
```

**Scopes:**
- `users` - Remove user namespaces and workspaces only
- `platform` - Remove users + Dev Spaces + MTA instances
- `all` - Remove all workshop Applications (keeps GitOps Operator)

**Options:**
```bash
# Also delete Root Application
export CLEANUP_ROOT=true
./scripts/cleanup-gitops.sh all
```

---

#### `reset-gitops.sh`
Reset GitOps Applications (cleanup and re-create).

**Usage:**
```bash
./scripts/reset-gitops.sh [applications|full]
```

**Modes:**
- `applications` - Reset Applications only (keeps Operator and Secrets)
- `full` - Complete reset including Operator and Secrets (regenerates passwords)

**What it does:**
1. Cleanup existing Applications
2. Wait for cleanup to complete
3. Re-install GitOps Operator (if full mode)
4. Re-create Secrets (if full mode)
5. Bootstrap GitOps Applications
6. Monitor sync status

**Warning:** Full mode regenerates user passwords!

### Status and Monitoring

#### `status-check.sh`
Quick status check of workshop environment.

**Usage:**
```bash
./scripts/status-check.sh
```

**Displays:**
- GitOps Operator status
- GitOps Applications sync/health
- Dev Spaces Operator and instance status
- MTA Operator and instance status
- Solution Server status
- User namespaces count
- Workspace status
- OAuth configuration
- Resource usage
- Overall environment status

---

#### `generate-user-list.sh`
Generate formatted user credential list for distribution.

**Usage:**
```bash
./scripts/generate-user-list.sh [markdown|html|table]
```

**Formats:**
- `markdown` - Markdown file (default)
- `html` - HTML file with styling
- `table` - Plain text table

**Output:**
- `artifacts/workshop-user-list.[md|html|txt]`

**Example:**
```bash
# Generate HTML version
./scripts/generate-user-list.sh html

# Open in browser
open artifacts/workshop-user-list.html
```

## Typical Workflows

### Complete New Workshop Setup

```bash
# 1. Configure inventory and vault
cp ansible/inventory/example/hosts.yml ansible/inventory/production/hosts.yml
vim ansible/inventory/production/hosts.yml

cp ansible/group_vars/vault.example.yml ansible/group_vars/vault.yml
vim ansible/group_vars/vault.yml
ansible-vault encrypt ansible/group_vars/vault.yml

# 2. Login to OpenShift
oc login https://api.your-cluster.com:6443

# 3. Run initial setup
./scripts/initial-setup.sh

# 4. Generate user list for distribution
./scripts/generate-user-list.sh html

# 5. Check status
./scripts/status-check.sh
```

### Reset Workshop for New Session

```bash
# Full reset (new passwords)
./scripts/reset-gitops.sh full

# Generate new user list
./scripts/generate-user-list.sh html
```

### Cleanup Workshop Resources

```bash
# Remove only user resources
./scripts/cleanup-gitops.sh users

# Remove everything except GitOps Operator
./scripts/cleanup-gitops.sh all

# Complete cleanup including Root Application
export CLEANUP_ROOT=true
./scripts/cleanup-gitops.sh all
```

### Troubleshooting

```bash
# Check current status
./scripts/status-check.sh

# Watch Application sync
oc get applications -n openshift-gitops --watch

# Reset just the Applications
./scripts/reset-gitops.sh applications
```

## Environment Variables

### `initial-setup.sh`
- `INVENTORY` - Path to inventory file (default: `ansible/inventory/production/hosts.yml`)

### `cleanup-gitops.sh`
- `CLEANUP_ROOT` - Set to `true` to also delete Root Application (default: `false`)

### `generate-user-list.sh`
- `CSV_FILE` - Path to user credentials CSV (default: `artifacts/workshop-users.csv`)

## Logs

All scripts save logs to `artifacts/` directory:
- `initial-setup-YYYYMMDD-HHMMSS.log`
- `cleanup-gitops-YYYYMMDD-HHMMSS.log`
- `reset-gitops-YYYYMMDD-HHMMSS.log`

Review logs for detailed execution information.

## Prerequisites

All scripts require:
- `oc` CLI installed and authenticated
- OpenShift cluster with cluster-admin access

Additional requirements per script:
- `initial-setup.sh`: ansible-playbook, htpasswd
- `reset-gitops.sh`: ansible-playbook
- `generate-user-list.sh`: jq (optional, for HTML format)

## Security Notes

- All scripts require confirmation before destructive operations
- User credentials CSV has 0600 permissions
- Vault files should be encrypted with `ansible-vault encrypt`
- Generated user lists should be distributed securely
- Clean up generated credential files after distribution

## Getting Help

For issues or questions:
1. Check script logs in `artifacts/`
2. Run `status-check.sh` to diagnose environment state
3. Review [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)
4. Contact workshop administrator
