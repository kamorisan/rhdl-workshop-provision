# TODO - Pre-Deployment Tasks

## Required Before First Deployment

### Critical (Must Complete)

- [ ] **Verify MTA Tackle CR fields** against target cluster
  ```bash
  oc explain tackle.spec --recursive
  oc get crd tackles.tackle.konveyor.io -o yaml
  ```
  Update: `gitops/platform-instances/mta/tackle.yaml`

- [ ] **Configure GitOps repository URL**
  - Update in: `ansible/inventory/production/hosts.yml`
  - Field: `gitops_repo_url`
  - Current value: `TO_BE_PROVIDED`

- [ ] **Configure demo repository URL**
  - Verify accessible: https://github.com/kamorisan/spring-to-quarkus-sample
  - Or update to your fork

- [ ] **Obtain and configure LLM credentials**
  - Provider: OpenAI / Azure / Gemini / Bedrock
  - API key
  - Model name
  - API base URL

### Important (Should Complete)

- [ ] **Verify Operator channels** on target cluster
  ```bash
  oc get packagemanifest devspaces -n openshift-marketplace -o jsonpath='{.status.channels[*].name}'
  oc get packagemanifest mta-operator -n openshift-marketplace -o jsonpath='{.status.channels[*].name}'
  ```
  Update in: `ansible/inventory/production/hosts.yml`

- [ ] **Test LLM endpoint connectivity**
  ```bash
  curl -I https://api.openai.com/v1/models
  ```

- [ ] **Determine StorageClass**
  ```bash
  oc get storageclass
  ```
  Set in inventory if no default exists

- [ ] **Calculate resource requirements**
  - User count × 2GB RAM + 16GB platform
  - User count × 0.5 CPU + 4 CPU platform
  - User count × 10GB storage + 20GB platform

### Optional (Nice to Have)

- [ ] **Customize workspace resources**
  - Memory limits
  - CPU limits
  - Storage size

- [ ] **Enable NetworkPolicy** (if required)
  - Set `network_policy_enabled: true`
  - Define allowed egress

- [ ] **Configure PVC retention**
  - Solution Server data retention
  - Workspace PVC retention

- [ ] **Test on non-production cluster first**

## Post-Deployment

- [ ] Verify all components with `./scripts/status-check.sh`
- [ ] Test sample user login
- [ ] Test workspace startup
- [ ] Test MTA analysis
- [ ] Test Developer Lightspeed
- [ ] Generate user credentials list
- [ ] Brief workshop facilitators

## Known Limitations / Future Enhancements

- [ ] MTA Tackle CR template needs cluster-specific validation
- [ ] NetworkPolicy rules are basic (can be enhanced)
- [ ] Support for multiple workshop sessions with shared Solution Server
- [ ] Integration with external identity providers (beyond htpasswd)
- [ ] Metrics and monitoring integration
- [ ] Cost estimation calculator
- [ ] Automated capacity planning
- [ ] Support for air-gapped environments

## Documentation Updates Needed

- [ ] Add actual cluster URLs to examples
- [ ] Add screenshots to workshop guide
- [ ] Add video walkthrough links (if available)
- [ ] Add FAQ section based on common questions

---

Last updated: 2026-07-11
