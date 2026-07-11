# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-11

### Added
- Initial release of workshop provisioning automation
- Ansible-based bootstrap for OpenShift GitOps Operator
- GitOps-based management of workshop infrastructure
- Support for OpenShift Dev Spaces 3.29+
- Support for MTA 8.1+ with Developer Lightspeed
- Solution Server integration
- htpasswd-based user authentication
- Dynamic user generation (1-99 users)
- Helm-based user namespace and resource generation
- Complete RBAC isolation per user
- ResourceQuota and LimitRange enforcement
- DevWorkspace definitions for Spring to Quarkus migration
- Automated provisioning scripts:
  - `initial-setup.sh` - Complete workshop setup
  - `cleanup-gitops.sh` - GitOps Application cleanup
  - `reset-gitops.sh` - GitOps Application reset
  - `status-check.sh` - Environment status checking
  - `generate-user-list.sh` - User credential list generation
- Comprehensive documentation:
  - README.md - Quick start and overview
  - OPERATIONS.md - Day 2 operations guide
  - WORKSHOP_GUIDE.md - Participant workshop guide
  - TROUBLESHOOTING.md - Common issues and solutions
  - CONTRIBUTING.md - Development guidelines
- GitOps Application hierarchy with Sync Wave ordering
- Application deletion with finalizers and prune policies
- PVC retention controls
- Multi-scope destroy operations (users/workshop/platform/all)
- Verification playbook for deployment validation
- Example configurations and templates
- Test scripts for Helm chart validation

### Features
- Responsibility separation between Ansible (secrets, bootstrap) and GitOps (infrastructure)
- Incremental user addition without disrupting existing users
- Safe user reduction with prune controls
- OAuth configuration preserving existing identity providers
- LLM API key management without workspace distribution
- Private Git repository support
- Multiple LLM provider support (OpenAI, Azure, Gemini, Bedrock)
- Automated verification of all components
- Detailed logging for all operations
- Color-coded status output
- HTML/Markdown/text user credential lists

### Demo Application
- Spring Boot PetClinic to Quarkus migration
- Pre-configured MTA analysis
- Developer Lightspeed integration
- Solution Server for shared learning

[1.0.0]: https://github.com/your-org/workshop-provisioning/releases/tag/v1.0.0
