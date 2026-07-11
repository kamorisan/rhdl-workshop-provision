# Contributing to Workshop Provisioning

## Development Setup

### Prerequisites

- OpenShift cluster with cluster-admin access
- Ansible 2.15+
- oc CLI
- Git

### Local Development

1. Clone the repository:
```bash
git clone <repository-url>
cd workshop-provisioning
```

2. Install Ansible collections:
```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

3. Create your development inventory:
```bash
cp ansible/inventory/example/hosts.yml ansible/inventory/dev/hosts.yml
# Edit ansible/inventory/dev/hosts.yml
```

4. Create and encrypt vault:
```bash
cp ansible/group_vars/vault.example.yml ansible/group_vars/vault.yml
# Edit ansible/group_vars/vault.yml
ansible-vault encrypt ansible/group_vars/vault.yml
```

## Making Changes

### GitOps Manifests

When modifying GitOps manifests:

1. Test with kustomize:
```bash
kustomize build gitops/operators
kustomize build gitops/platform-instances
kustomize build gitops/workshop/namespaces
```

2. Validate YAML syntax:
```bash
yamllint gitops/
```

3. Test Helm charts:
```bash
helm template workshop gitops/workshop/namespaces -f gitops/config/workshop-values.yaml
helm template workshop gitops/workshop/resources -f gitops/config/workshop-values.yaml
```

### Ansible Roles

When modifying Ansible roles:

1. Test syntax:
```bash
ansible-playbook ansible/playbooks/bootstrap.yml --syntax-check
```

2. Run with check mode:
```bash
ansible-playbook ansible/playbooks/bootstrap.yml -i ansible/inventory/dev/hosts.yml --check
```

3. Test individual roles:
```bash
ansible-playbook ansible/playbooks/bootstrap.yml -i ansible/inventory/dev/hosts.yml --tags preflight
```

### Scripts

When modifying scripts:

1. Check shell syntax:
```bash
shellcheck scripts/*.sh
```

2. Test in non-production cluster first

3. Verify logging output

## Testing

### Manual Testing Checklist

- [ ] Preflight checks pass
- [ ] GitOps Operator installs successfully
- [ ] All Applications sync and become healthy
- [ ] User namespaces created
- [ ] Workspaces start successfully
- [ ] MTA extension available in workspace
- [ ] Solution Server accessible
- [ ] User can log in with htpasswd
- [ ] RBAC correctly restricts access
- [ ] Destroy operations work cleanly

### Integration Testing

Run full integration test:

```bash
# Provision
./scripts/initial-setup.sh

# Verify
./scripts/status-check.sh
make verify

# Test user access
oc login -u user01 -p <password>
oc get pods -n user01-dev

# Cleanup
./scripts/cleanup-gitops.sh all
```

## Code Style

### YAML

- Use 2-space indentation
- Use `---` document separator
- Keep lines under 120 characters
- Use explicit quotes for strings with special characters

### Ansible

- Use `snake_case` for variables and task names
- Add `no_log: true` for tasks handling secrets
- Use `validate_certs: "{{ cluster_validate_certs }}"` for k8s tasks
- Add descriptions to all roles

### Shell Scripts

- Use `#!/bin/bash` shebang
- Set `set -e` for error handling
- Use 4-space indentation
- Include usage/help text
- Add colored output for user feedback
- Save logs to artifacts directory

## Pull Request Process

1. Create a feature branch:
```bash
git checkout -b feature/your-feature-name
```

2. Make your changes

3. Test thoroughly (see Testing section)

4. Commit with descriptive messages:
```bash
git commit -m "feat: add support for custom StorageClass"
```

5. Push and create pull request:
```bash
git push origin feature/your-feature-name
```

6. Address review feedback

## Commit Message Format

Use conventional commits format:

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `refactor:` - Code refactoring
- `test:` - Test additions/changes
- `chore:` - Maintenance tasks

Examples:
```
feat(ansible): add support for Azure OpenAI
fix(gitops): correct Tackle CR field names
docs(readme): update installation instructions
refactor(scripts): improve error handling in cleanup script
```

## Security

- Never commit secrets or passwords
- Always use Ansible Vault for sensitive data
- Test Secret handling with `no_log: true`
- Verify CSV file permissions (0600)
- Check that generated credentials are not in Git

## Documentation

When adding features:

1. Update README.md
2. Update relevant docs/ files
3. Add script documentation to scripts/README.md
4. Update TROUBLESHOOTING.md with known issues
5. Add examples to OPERATIONS.md

## Questions?

- Check existing issues
- Review TROUBLESHOOTING.md
- Contact maintainers
