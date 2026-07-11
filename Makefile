.PHONY: help preflight provision verify destroy-users destroy-workshop destroy-platform destroy-all clean

# Default inventory
INVENTORY ?= ansible/inventory/production/hosts.yml
VAULT_PASS ?= --ask-vault-pass

help:
	@echo "OpenShift Dev Spaces + Developer Lightspeed Workshop Provisioning"
	@echo ""
	@echo "Usage:"
	@echo "  make preflight           - Run preflight checks"
	@echo "  make provision           - Full provisioning (preflight + bootstrap + verify)"
	@echo "  make verify              - Verify deployment"
	@echo "  make destroy-users       - Remove only user namespaces and workspaces"
	@echo "  make destroy-workshop    - Remove users + workshop-system"
	@echo "  make destroy-platform    - Remove workshop + Dev Spaces + MTA instances"
	@echo "  make destroy-all         - Remove everything including GitOps Operator"
	@echo "  make clean               - Remove local artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  INVENTORY=<path>         - Ansible inventory file (default: ansible/inventory/production/hosts.yml)"
	@echo "  VAULT_PASS=<option>      - Vault password option (default: --ask-vault-pass)"
	@echo ""
	@echo "Examples:"
	@echo "  make provision"
	@echo "  make provision INVENTORY=ansible/inventory/example/hosts.yml"
	@echo "  make destroy-users"
	@echo "  make destroy-all VAULT_PASS='--vault-password-file ~/.vault_pass'"

preflight:
	@echo "Running preflight checks..."
	ansible-playbook ansible/playbooks/bootstrap.yml \
		-i $(INVENTORY) \
		--tags preflight \
		$(VAULT_PASS)

provision: preflight
	@echo "Provisioning workshop environment..."
	ansible-playbook ansible/playbooks/bootstrap.yml \
		-i $(INVENTORY) \
		$(VAULT_PASS)

verify:
	@echo "Verifying deployment..."
	ansible-playbook ansible/playbooks/verify.yml \
		-i $(INVENTORY)

destroy-users:
	@echo "WARNING: This will delete all user namespaces and workspaces."
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	ansible-playbook ansible/playbooks/destroy.yml \
		-i $(INVENTORY) \
		-e destroy_scope=users \
		-e confirm_destroy=true

destroy-workshop:
	@echo "WARNING: This will delete all user namespaces, workspaces, and workshop-system."
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	ansible-playbook ansible/playbooks/destroy.yml \
		-i $(INVENTORY) \
		-e destroy_scope=workshop \
		-e confirm_destroy=true

destroy-platform:
	@echo "WARNING: This will delete workshop + Dev Spaces and MTA instances."
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	ansible-playbook ansible/playbooks/destroy.yml \
		-i $(INVENTORY) \
		-e destroy_scope=platform \
		-e confirm_destroy=true

destroy-all:
	@echo "DANGER: This will delete EVERYTHING including the GitOps Operator."
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	ansible-playbook ansible/playbooks/destroy.yml \
		-i $(INVENTORY) \
		-e destroy_scope=all \
		-e confirm_destroy=true \
		$(VAULT_PASS)

clean:
	@echo "Removing local artifacts..."
	rm -rf artifacts/
	@echo "Done."
