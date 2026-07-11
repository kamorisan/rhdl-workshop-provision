# Workshop Deployment Checklist

Use this checklist to ensure all requirements are met before deploying the workshop environment.

## Pre-Deployment

### Cluster Requirements

- [ ] OpenShift cluster version 4.12 or higher
- [ ] Current user has cluster-admin permissions
- [ ] Default StorageClass configured
- [ ] Cluster domain identified: `________________________`
- [ ] Cluster has sufficient resources:
  - [ ] CPU: ~{{ workshop_user_count }} cores for users + 4 cores for platform
  - [ ] Memory: ~{{ workshop_user_count * 2 + 16 }}GB
  - [ ] Storage: ~{{ workshop_user_count * 10 + 20 }}GB

### OperatorHub Access

- [ ] Can access Red Hat Operator catalog
- [ ] Dev Spaces Operator available:
  ```bash
  oc get packagemanifest devspaces -n openshift-marketplace
  ```
- [ ] MTA Operator available:
  ```bash
  oc get packagemanifest mta-operator -n openshift-marketplace
  ```
- [ ] Verified channels for both operators:
  - Dev Spaces channel: `________________________`
  - MTA channel: `________________________`

### Network Access

- [ ] Demo repository accessible from cluster: https://github.com/kamorisan/spring-to-quarkus-sample
- [ ] LLM endpoint accessible from cluster: `________________________`
- [ ] Maven Central accessible for dependency downloads
- [ ] Container registry accessible for Dev Spaces images

### LLM Configuration

- [ ] LLM provider selected: `________________________`
- [ ] LLM model identified: `________________________`
- [ ] LLM API base URL: `________________________`
- [ ] LLM API key obtained (DO NOT write here)
- [ ] LLM endpoint tested from local machine:
  ```bash
  curl -I https://api.openai.com/v1/models
  ```

### GitOps Repository

- [ ] GitOps repository created/identified: `________________________`
- [ ] Repository accessible from cluster
- [ ] Branch/revision identified: `________________________`
- [ ] Repository credentials obtained (if private)
- [ ] Repository contains workshop-provisioning code

### Ansible Setup

- [ ] Ansible 2.15+ installed
- [ ] oc CLI installed and configured
- [ ] htpasswd utility installed
- [ ] Python 3.9+ available
- [ ] Ansible collections installed:
  ```bash
  ansible-galaxy collection install -r ansible/requirements.yml
  ```

## Configuration

### Inventory File

- [ ] Created production inventory:
  ```bash
  cp ansible/inventory/example/hosts.yml ansible/inventory/production/hosts.yml
  ```
- [ ] Configured cluster_api_url: `________________________`
- [ ] Set workshop_user_count: `________________________`
- [ ] Configured demo_repository_url
- [ ] Set migration_source: `springboot`
- [ ] Set migration_target: `quarkus`
- [ ] Configured devspaces_channel
- [ ] Configured mta_channel
- [ ] Configured gitops_repo_url
- [ ] Set llm_provider
- [ ] Set llm_model
- [ ] Set llm_api_base

### Vault File

- [ ] Created vault file:
  ```bash
  cp ansible/group_vars/vault.example.yml ansible/group_vars/vault.yml
  ```
- [ ] Configured vault_llm_api_key
- [ ] Configured vault_gitops_repo_token (if needed)
- [ ] Configured vault_demo_repo_token (if private)
- [ ] Encrypted vault file:
  ```bash
  ansible-vault encrypt ansible/group_vars/vault.yml
  ```
- [ ] Vault password stored securely

### MTA Tackle CR Verification

- [ ] Connected to target cluster
- [ ] Verified Tackle CRD fields:
  ```bash
  oc explain tackle.spec --recursive
  ```
- [ ] Updated `gitops/platform-instances/mta/tackle.yaml` according to actual CRD
- [ ] Verified field names for:
  - [ ] kai.enabled
  - [ ] LLM provider field name
  - [ ] LLM model field name
  - [ ] Secret name field
  - [ ] Database configuration

## Deployment

### Pre-Flight Checks

- [ ] Logged in to OpenShift:
  ```bash
  oc login https://api.your-cluster.com:6443
  oc whoami
  oc auth can-i '*' '*' --all-namespaces
  ```
- [ ] Run preflight checks:
  ```bash
  make preflight
  ```
- [ ] Review preflight output for warnings

### Provisioning

- [ ] Run initial setup:
  ```bash
  ./scripts/initial-setup.sh
  ```
  OR manual provisioning:
  ```bash
  make provision
  ```
- [ ] Monitor GitOps sync:
  ```bash
  oc get applications -n openshift-gitops --watch
  ```
- [ ] Wait for all Applications to become Synced and Healthy

### Verification

- [ ] Run verification:
  ```bash
  make verify
  ```
  OR:
  ```bash
  ./scripts/status-check.sh
  ```
- [ ] Verify GitOps Operator ready
- [ ] Verify Dev Spaces Operator ready
- [ ] Verify MTA Operator ready
- [ ] Verify Dev Spaces instance available
- [ ] Verify MTA instance created
- [ ] Verify Solution Server running
- [ ] Verify user namespaces created (count: `___`)
- [ ] Verify workspaces created (count: `___`)

### Endpoints

- [ ] GitOps Console accessible: `________________________`
- [ ] Dev Spaces Dashboard accessible: `________________________`
- [ ] MTA Hub accessible (optional): `________________________`

### User Credentials

- [ ] User credentials generated: `artifacts/workshop-users.csv`
- [ ] CSV file has correct permissions (0600)
- [ ] Generated user list for distribution:
  ```bash
  ./scripts/generate-user-list.sh html
  ```
- [ ] User list reviewed and ready for distribution

## Post-Deployment Testing

### Sample User Test

- [ ] Test login with user01:
  ```bash
  oc login -u user01 -p <password>
  ```
- [ ] Verify user can access their namespace:
  ```bash
  oc get pods -n user01-dev
  ```
- [ ] Verify user CANNOT access other namespace:
  ```bash
  oc get pods -n user02-dev  # should fail
  ```
- [ ] Access Dev Spaces Dashboard as user01
- [ ] Start workspace for user01
- [ ] Verify demo app cloned in workspace
- [ ] Verify MTA extension available
- [ ] Test MTA analysis on demo app
- [ ] Verify Developer Lightspeed accessible
- [ ] Test AI suggestion retrieval

### Platform Test

- [ ] Solution Server health check:
  ```bash
  oc get pods -n openshift-mta -l app.kubernetes.io/component=solution-server
  ```
- [ ] MTA Hub accessible (if enabled)
- [ ] LLM connectivity from Solution Server:
  ```bash
  oc logs -n openshift-mta -l app.kubernetes.io/component=solution-server | grep -i "llm\|openai\|error"
  ```

## Workshop Readiness

- [ ] All preflight checks passed
- [ ] All verification checks passed
- [ ] Sample user tested successfully
- [ ] Platform components healthy
- [ ] User credentials ready for distribution
- [ ] Workshop guide reviewed
- [ ] Troubleshooting guide accessible
- [ ] Support contact information prepared
- [ ] Estimated workshop duration: `________________________`
- [ ] Workshop facilitator briefed

## Backup/Rollback Plan

- [ ] GitOps repository backed up
- [ ] User credentials backed up securely
- [ ] Vault file backed up
- [ ] Cleanup procedure tested:
  ```bash
  ./scripts/cleanup-gitops.sh users  # test only
  ```
- [ ] Reset procedure documented
- [ ] Rollback plan prepared

## Sign-Off

- Deployment completed by: `________________________`
- Date: `________________________`
- Cluster: `________________________`
- User count: `________________________`
- Workshop date/time: `________________________`

**Notes:**
_Add any deployment-specific notes, issues encountered, or deviations from standard procedure:_

---

## Post-Workshop

After workshop completion:

- [ ] Gather feedback from participants
- [ ] Export Solution Server data (if retaining):
  ```bash
  oc get pvc -n openshift-mta
  ```
- [ ] Run cleanup:
  ```bash
  ./scripts/cleanup-gitops.sh all
  ```
- [ ] Verify all resources deleted
- [ ] Revoke/rotate LLM API key
- [ ] Delete user credentials CSV
- [ ] Document lessons learned
- [ ] Update troubleshooting guide with new issues
