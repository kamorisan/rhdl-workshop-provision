# OpenShift Dev Spaces + Developer Lightspeed Workshop Provisioning

Automated provisioning system for OpenShift Dev Spaces + Red Hat Developer Lightspeed for MTA workshop environment.

This workshop demonstrates migrating a Spring Boot application (PetClinic) to Quarkus using MTA static analysis and AI-powered code suggestions.

## Overview

Provisions a multi-user workshop environment with:
- **OpenShift Dev Spaces** - Cloud IDE for each participant
- **Migration Toolkit for Applications (MTA)** - Static code analysis
- **Red Hat Developer Lightspeed for MTA** - LLM-powered migration assistance
- **Solution Server** - Shared learning from migration fixes
- **htpasswd Authentication** - Workshop user authentication
- **GitOps Management** - Declarative infrastructure via Argo CD

## Architecture

```
Ansible (Bootstrap)
  └─> OpenShift GitOps Operator
      └─> Root Application
          ├─> Operators (Dev Spaces, MTA)
          ├─> Platform Instances (Dev Spaces CR, Tackle CR, Solution Server)
          ├─> Cluster Config (OAuth)
          ├─> Workshop Namespaces (userXX-dev)
          └─> Workshop Resources (RBAC, Quota, DevWorkspace)
```

**Responsibility Separation:**
- **Ansible**: GitOps Operator, Secrets (htpasswd, LLM API Key, Git credentials), Bootstrap
- **GitOps**: All Operators, Platform Instances, Namespaces, RBAC, Workspaces

## Prerequisites

### Cluster Requirements
- OpenShift Container Platform 4.12+
- `cluster-admin` access
- Default StorageClass configured
- Sufficient capacity for:
  - Dev Spaces Operator + instance
  - MTA Operator + instance + Solution Server
  - N user workspaces (default: 2Gi memory, 500m CPU each)

### Management Workstation
- Ansible Core 2.15+ or Ansible Automation Platform
- `oc` CLI authenticated with cluster-admin
- `htpasswd` utility
- Python 3.9+
- Git

### Required Information
- **Demo Repository URL** (required): Spring Boot app to migrate
- **LLM Configuration** (required): Provider, model, API base, API key
- **Workshop User Count**: Number of participants (default: 10, max: 99)
- **Operator Channels**: Verified against target cluster

## Quick Start

### Using the Setup Script (Recommended)

The easiest way to get started is using the automated setup script:

```bash
# 1. Configure inventory
cp ansible/inventory/example/hosts.yml ansible/inventory/production/hosts.yml
vim ansible/inventory/production/hosts.yml

# 2. Configure vault
cp ansible/group_vars/vault.example.yml ansible/group_vars/vault.yml
vim ansible/group_vars/vault.yml
ansible-vault encrypt ansible/group_vars/vault.yml

# 3. Login to OpenShift
oc login https://api.your-cluster.com:6443

# 4. Run automated setup
./scripts/initial-setup.sh
```

The setup script will:
- Check all prerequisites
- Run preflight validation
- Provision the complete environment
- Verify deployment
- Display endpoints and credentials

### Manual Setup

If you prefer manual control:

### 1. Install Ansible Collections

```bash
cd workshop-provisioning
ansible-galaxy collection install -r ansible/requirements.yml
```

### 2. Configure Variables

Copy example inventory and variables:

```bash
cp ansible/inventory/example/hosts.yml ansible/inventory/production/hosts.yml
cp ansible/group_vars/vault.example.yml ansible/group_vars/vault.yml
```

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
    demo_repository_revision: "main"
    migration_source: "springboot"
    migration_target: "quarkus"
```

Edit `ansible/group_vars/vault.yml` and encrypt it:

```yaml
vault_llm_api_key: "your-llm-api-key"
vault_gitops_repo_token: "your-git-token"  # if using private GitOps repo
```

```bash
ansible-vault encrypt ansible/group_vars/vault.yml
```

### 3. Run Preflight Checks

```bash
make preflight
```

or

```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  --tags preflight \
  --ask-vault-pass
```

### 4. Provision Workshop Environment

```bash
make provision
```

or

```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  --ask-vault-pass
```

### 5. Verify Deployment

```bash
make verify
```

Verification checks:
- GitOps Operator ready
- All Applications synced and healthy
- Dev Spaces and MTA instances ready
- Solution Server ready
- All user namespaces created
- RBAC configured correctly
- Workspaces created for all users

### 6. Retrieve User Credentials

After provisioning, user credentials are saved to:

```
./artifacts/workshop-users.csv
```

Format:
```
username,password,namespace
user01,<generated>,user01-dev
user02,<generated>,user02-dev
```

**IMPORTANT**: This file is created with `0600` permissions and is NOT committed to Git.

## Usage

### Scripts (Recommended)

The `scripts/` directory contains convenient operational scripts:

```bash
# Initial provisioning
./scripts/initial-setup.sh

# Check workshop status
./scripts/status-check.sh

# Generate user credential list (HTML/Markdown/Table)
./scripts/generate-user-list.sh html

# Cleanup GitOps Applications
./scripts/cleanup-gitops.sh [users|platform|all]

# Reset GitOps (cleanup and re-create)
./scripts/reset-gitops.sh [applications|full]
```

See [scripts/README.md](scripts/README.md) for detailed script documentation.

### Makefile Targets

```bash
make preflight          # Run preflight checks
make provision          # Full provisioning (preflight + bootstrap + verify)
make verify             # Verify deployment
make destroy-users      # Remove only user namespaces and workspaces
make destroy-workshop   # Remove users + workshop-system
make destroy-platform   # Remove workshop + Dev Spaces + MTA instances
make destroy-all        # Remove everything including GitOps Operator
```

### Manual Playbook Execution

**Bootstrap (full provisioning):**

```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  -e workshop_user_count=30 \
  --ask-vault-pass
```

**Add more users (incremental):**

```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  -e workshop_user_count=50 \
  --ask-vault-pass
```

Existing users (user01-user30) remain unchanged. New users (user31-user50) are added.

**Reduce user count (with explicit prune):**

```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/production/hosts.yml \
  -e workshop_user_count=20 \
  -e prune_users=true \
  --ask-vault-pass
```

**DANGER**: This will delete user21-user30 namespaces and all their resources.

**Destroy workshop (scoped deletion):**

```bash
# Remove only users
ansible-playbook ansible/playbooks/destroy.yml \
  -i ansible/inventory/production/hosts.yml \
  -e destroy_scope=users \
  -e confirm_destroy=true

# Remove everything except GitOps Operator
ansible-playbook ansible/playbooks/destroy.yml \
  -i ansible/inventory/production/hosts.yml \
  -e destroy_scope=all-gitops-managed \
  -e confirm_destroy=true

# Remove everything including GitOps Operator
ansible-playbook ansible/playbooks/destroy.yml \
  -i ansible/inventory/production/hosts.yml \
  -e destroy_scope=all \
  -e confirm_destroy=true \
  --ask-vault-pass
```

## Configuration

### Key Variables

See [ansible/group_vars/all.yml](ansible/group_vars/all.yml) for all configurable variables.

**Required:**
- `demo_repository_url` - Git URL of the demo application
- `llm_api_key` - LLM API key (in vault.yml)

**Important:**
- `workshop_user_count` - Number of workshop participants (default: 10)
- `workspace_memory_limit` - Memory per workspace (default: 8Gi for MTA)
- `llm_provider` - LLM provider (openai, azure, gemini, bedrock)
- `llm_model` - Model name
- `llm_api_base` - API endpoint URL

**Optional:**
- `network_policy_enabled` - Enable NetworkPolicy (default: false)
- `retain_solution_server_pvc` - Keep Solution Server data on delete (default: false)
- `retain_workspace_pvc` - Keep workspace PVCs on delete (default: false)

### Operator Channels

Before running on a new cluster, verify available Operator channels:

```bash
# Dev Spaces
oc get packagemanifest devspaces -n openshift-marketplace -o jsonpath='{.status.channels[*].name}'

# MTA
oc get packagemanifest mta-operator -n openshift-marketplace -o jsonpath='{.status.channels[*].name}'
```

Update in `ansible/group_vars/all.yml`:

```yaml
devspaces_channel: "stable"
mta_channel: "stable"
```

## Workshop User Experience

1. Receive username (`userXX`) and password from workshop administrator
2. Log in to OpenShift Console
3. Navigate to Dev Spaces Dashboard
4. Start the pre-configured workspace
5. Open the MTA Analysis view in VS Code
6. Run analysis on the Spring Boot PetClinic app
7. Review detected migration issues
8. Request AI-powered fix suggestions from Developer Lightspeed
9. Apply, review, and customize suggested fixes
10. Build and test the migrated Quarkus application
11. Deploy to their OpenShift namespace (`userXX-dev`)
12. Verify the migrated application

## Repository Structure

```
workshop-provisioning/
├── ansible/                    # Ansible automation
│   ├── ansible.cfg
│   ├── requirements.yml        # Ansible collections
│   ├── inventory/              # Inventory files
│   ├── group_vars/             # Variables and vault
│   ├── playbooks/              # Playbooks
│   │   ├── bootstrap.yml       # Main provisioning
│   │   ├── verify.yml          # Verification
│   │   └── destroy.yml         # Cleanup
│   ├── roles/                  # Ansible roles
│   │   ├── preflight/          # Pre-flight checks
│   │   ├── gitops_operator/    # Install GitOps Operator
│   │   ├── gitops_bootstrap/   # Bootstrap Root Application
│   │   ├── htpasswd_users/     # User creation
│   │   ├── llm_secret/         # LLM credential Secret
│   │   ├── repository_secret/  # Git credential Secret
│   │   ├── verification/       # Post-deployment verification
│   │   └── destroy/            # Cleanup tasks
│   └── templates/              # Jinja2 templates
├── gitops/                     # GitOps manifests
│   ├── bootstrap/              # Root Application
│   ├── operators/              # Operator Subscriptions
│   ├── cluster-config/         # OAuth, RBAC
│   ├── platform-namespaces/    # Platform namespaces
│   ├── platform-instances/     # Dev Spaces CR, Tackle CR
│   ├── workshop/               # User namespaces and resources
│   ├── applicationsets/        # ApplicationSet definitions
│   └── config/                 # Helm values
├── devfile/                    # Devfile and IDE settings
├── scripts/                    # Utility scripts
├── tests/                      # Test scripts
├── docs/                       # Documentation
│   ├── OPERATIONS.md           # Operations guide
│   ├── WORKSHOP_GUIDE.md       # Workshop participant guide
│   └── TROUBLESHOOTING.md      # Troubleshooting guide
├── Makefile                    # Convenience targets
└── README.md                   # This file
```

## GitOps Application Hierarchy

```
root-application
├── operators-application (wave: -80)
│   ├── devspaces-operator
│   └── mta-operator
├── cluster-config-application (wave: -50)
│   └── oauth
├── platform-namespaces-application (wave: -40)
│   ├── openshift-devspaces
│   ├── openshift-mta
│   └── workshop-system
├── platform-instances-application (wave: -20)
│   ├── devspaces-instance
│   └── mta-instance (with Solution Server)
├── workshop-namespaces-application (wave: 0)
│   ├── user01-dev
│   ├── user02-dev
│   └── userNN-dev
├── workshop-resources-application (wave: 10)
│   ├── RBAC
│   ├── ResourceQuota
│   ├── LimitRange
│   └── DevWorkspace
└── verification-application (wave: 50)
```

**Application Deletion:**
- All Applications have `finalizers: [resources-finalizer.argocd.argoproj.io]`
- Deleting an Application deletes all its managed resources
- Deleting Root Application cascades to all child Applications
- PVC retention is controlled by variables

## Security

**Secret Management:**
- All secrets managed by Ansible (not stored in Git)
- htpasswd passwords generated or provided via Vault
- LLM API Key stored in cluster Secret, not distributed to workspaces
- Git credentials (if needed) managed via Secret
- CSV output file permissions: `0600`

**RBAC:**
- Each user has `admin` role in their namespace only
- Users CANNOT access other namespaces
- Users CANNOT modify Operators, OAuth, cluster config
- AppProject `workshop-users` prevents dangerous operations

**NetworkPolicy (optional):**
- Default deny ingress
- Allow only necessary connections:
  - DNS, OpenShift API
  - MTA Solution Server
  - Git repository
  - Maven/artifact repositories

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues.

**Quick checks:**

```bash
# Check GitOps status
oc get applications -n openshift-gitops

# Check Operator status
oc get csv -n openshift-devspaces
oc get csv -n openshift-mta

# Check Platform instances
oc get checluster -n openshift-devspaces
oc get tackle -n openshift-mta

# Check user namespaces
oc get namespaces | grep -- '-dev'

# Check user workspaces
oc get devworkspace -A

# Check Solution Server
oc get pods -n openshift-mta -l app=solution-server
oc logs -n openshift-mta -l app=solution-server
```

## License

Apache License 2.0

## Contributing

See design documents in `docs/` for architecture and implementation details.

For issues or questions, contact the workshop administrator.
