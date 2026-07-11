# Troubleshooting Guide

## Common Issues and Solutions

### Provisioning Issues

#### Preflight Check Failures

**Issue:** Preflight fails with "cluster-admin permissions required"

**Solution:**
```bash
# Verify current user
oc whoami

# Check permissions
oc auth can-i '*' '*' --all-namespaces

# If not cluster-admin, contact cluster administrator
```

---

**Issue:** "Required Operator package not found"

**Solution:**
```bash
# Check OperatorHub connectivity
oc get catalogsources -n openshift-marketplace

# Verify specific package
oc get packagemanifest devspaces -n openshift-marketplace
oc get packagemanifest mta-operator -n openshift-marketplace

# If missing, check OperatorHub configuration
oc get operatorhub cluster -o yaml
```

---

**Issue:** "No default StorageClass found"

**Solution:**
```bash
# List StorageClasses
oc get storageclasses

# Set a default if needed
oc patch storageclass <your-storage-class> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Or specify in inventory
# storage_class_name: "gp2"
```

#### GitOps Operator Installation Failures

**Issue:** GitOps Operator CSV stuck in "Installing"

**Solution:**
```bash
# Check CSV status
oc get csv -n openshift-gitops-operator

# Check operator pod logs
oc logs -n openshift-gitops-operator -l name=openshift-gitops-operator

# Check for pending install plans
oc get installplan -n openshift-gitops-operator

# If stuck, try deleting and re-running
oc delete subscription openshift-gitops-operator -n openshift-gitops-operator
ansible-playbook ansible/playbooks/bootstrap.yml -i ansible/inventory/production/hosts.yml --tags gitops
```

---

**Issue:** Argo CD instance not becoming Available

**Solution:**
```bash
# Check ArgoCD status
oc get argocd openshift-gitops -n openshift-gitops -o yaml

# Check pods
oc get pods -n openshift-gitops

# Check events
oc get events -n openshift-gitops --sort-by='.lastTimestamp'

# Check for resource constraints
oc describe pod -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller
```

#### Application Sync Issues

**Issue:** Root Application stuck in "OutOfSync"

**Solution:**
```bash
# Check Application status
oc describe application workshop-root -n openshift-gitops

# Check sync errors
oc get application workshop-root -n openshift-gitops -o jsonpath='{.status.conditions}'

# Manual sync
argocd app sync workshop-root --prune

# Check repository connectivity
oc get secret workshop-gitops-repo -n openshift-gitops -o yaml
```

---

**Issue:** Child Applications not created

**Solution:**
```bash
# Verify root-application.yaml is in Git repo at correct path
# Check bootstrap path in bootstrap Application

# Manually create if needed
oc apply -f gitops/bootstrap/root-application.yaml

# Check for errors in Argo CD logs
oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller
```

### Operator Issues

#### Dev Spaces Operator

**Issue:** Dev Spaces Operator CSV fails

**Solution:**
```bash
# Check CSV
oc get csv -n openshift-devspaces

# Check operator pod
oc logs -n openshift-devspaces -l app.kubernetes.io/name=devspaces-operator

# Check prerequisites
oc get nodes -o wide
oc get sc

# Verify channel
oc get packagemanifest devspaces -n openshift-marketplace -o jsonpath='{.status.channels[*].name}'
```

---

**Issue:** CheCluster stuck in "Available=False"

**Solution:**
```bash
# Check CheCluster status
oc get checluster devspaces -n openshift-devspaces -o yaml

# Check devspaces pods
oc get pods -n openshift-devspaces

# Common issue: insufficient resources
oc describe pod -n openshift-devspaces -l app.kubernetes.io/component=devspaces

# Check PVC status
oc get pvc -n openshift-devspaces

# Review events
oc get events -n openshift-devspaces --sort-by='.lastTimestamp'
```

#### MTA Operator

**Issue:** MTA Operator fails to install

**Solution:**
```bash
# Check subscription
oc get subscription mta-operator -n openshift-mta

# Check CSV
oc get csv -n openshift-mta

# Check operator logs
oc logs -n openshift-mta -l control-plane=mta-operator

# Verify CRD
oc get crd tackles.tackle.konveyor.io
```

---

**Issue:** Tackle CR not becoming Ready

**Solution:**
```bash
# Check Tackle status
oc get tackle mta -n openshift-mta -o yaml

# Check MTA pods
oc get pods -n openshift-mta

# Common issue: LLM Secret not found
oc get secret kai-api-keys -n openshift-mta

# Check hub pod logs
oc logs -n openshift-mta -l app.kubernetes.io/component=tackle-hub

# Check for image pull errors
oc describe pod -n openshift-mta -l app.kubernetes.io/component=tackle-hub
```

---

**Issue:** Solution Server not starting

**Solution:**
```bash
# Check if enabled in Tackle CR
oc get tackle mta -n openshift-mta -o yaml | grep -A5 kai

# Check solution server pods
oc get pods -n openshift-mta -l app.kubernetes.io/component=solution-server

# Check logs
oc logs -n openshift-mta -l app.kubernetes.io/component=solution-server

# Verify LLM Secret
oc get secret kai-api-keys -n openshift-mta -o yaml

# Test LLM endpoint
curl -I https://api.openai.com/v1/models

# Check PVC
oc get pvc -n openshift-mta
```

### User and Workspace Issues

#### User Authentication

**Issue:** Users cannot log in

**Solution:**
```bash
# Check OAuth configuration
oc get oauth cluster -o yaml

# Verify htpasswd Secret
oc get secret workshop-htpasswd -n openshift-config

# Check if identity provider is listed
oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}'

# Verify user in htpasswd
oc extract secret/workshop-htpasswd -n openshift-config --to=-

# OAuth pods may need restart
oc get pods -n openshift-authentication
oc delete pod -n openshift-authentication -l app=oauth-openshift
```

---

**Issue:** User can log in but has no access

**Solution:**
```bash
# Check RoleBinding
oc get rolebinding -n user01-dev

# Verify user identity
oc get user user01

# Check identity mapping
oc get identity | grep user01

# Manually create RoleBinding if missing
oc create rolebinding workshop-user-admin \
  --clusterrole=admin \
  --user=user01 \
  -n user01-dev
```

#### Workspace Issues

**Issue:** Workspace not starting

**Solution:**
```bash
# Check DevWorkspace
oc get devworkspace -n user01-dev

# Describe for errors
oc describe devworkspace spring-to-quarkus-user01 -n user01-dev

# Check workspace pods
oc get pods -n user01-dev

# Common issues:
# 1. Resource quota exceeded
oc get resourcequota -n user01-dev
oc describe resourcequota -n user01-dev

# 2. Image pull issues
oc describe pod -n user01-dev <workspace-pod-name>

# 3. PVC binding issues
oc get pvc -n user01-dev
```

---

**Issue:** Workspace stuck in "Starting"

**Solution:**
```bash
# Check workspace pod status
oc get pods -n user01-dev -l controller.devfile.io/devworkspace_name=spring-to-quarkus-user01

# Check pod events
oc describe pod -n user01-dev <workspace-pod-name>

# Common causes:
# 1. Insufficient cluster resources
oc describe node | grep -A5 "Allocated resources"

# 2. Slow image pull
oc logs -n user01-dev <workspace-pod-name>

# 3. Init container failures
oc logs -n user01-dev <workspace-pod-name> -c <init-container-name>

# Force restart
oc delete pod -n user01-dev <workspace-pod-name>
```

---

**Issue:** Git clone fails in workspace

**Solution:**
```bash
# Check if repository is accessible
curl -I https://github.com/kamorisan/spring-to-quarkus-sample

# If private repo, check Secret
oc get secret workshop-demo-repo -n openshift-gitops

# Check workspace logs
oc logs -n user01-dev <workspace-pod-name>

# Verify DevWorkspace definition
oc get devworkspace spring-to-quarkus-user01 -n user01-dev -o yaml
```

#### MTA Extension Issues

**Issue:** MTA extension not available in workspace

**Solution:**
```bash
# Check workspace image
oc get devworkspace spring-to-quarkus-user01 -n user01-dev -o jsonpath='{.spec.template.components[0].container.image}'

# Verify universal-developer-image includes MTA CLI
# Connect to workspace terminal and check:
which mta-cli

# If missing, update DevWorkspace to use correct image
```

---

**Issue:** MTA analysis fails

**Solution:**
```bash
# In workspace terminal, check MTA CLI
mta-cli --version

# Check Java version
java -version  # Should be 17+

# Check Maven
mvn -version

# Verify project structure
ls -la /projects/spring-petclinic/src

# Try manual analysis
mta-cli analyze --input /projects/spring-petclinic/src --target quarkus --source springboot
```

---

**Issue:** Developer Lightspeed not working

**Solution:**
```bash
# Check Solution Server URL in workspace
echo $MTA_SOLUTION_SERVER_URL

# Test connectivity from workspace
curl -I $MTA_SOLUTION_SERVER_URL/health

# Check Solution Server status
oc get pods -n openshift-mta -l app.kubernetes.io/component=solution-server
oc logs -n openshift-mta -l app.kubernetes.io/component=solution-server

# Verify LLM Secret
oc get secret kai-api-keys -n openshift-mta

# Check MTA VS Code extension settings
# In workspace, View -> Command Palette -> "Preferences: Open Settings (JSON)"
# Verify mta.solutionServer.url and mta.generativeAI.enabled
```

### Resource Issues

#### Quota Exceeded

**Issue:** "forbidden: exceeded quota"

**Solution:**
```bash
# Check current usage
oc describe resourcequota -n user01-dev

# Adjust quota if needed
oc patch resourcequota workshop-quota -n user01-dev --type merge -p '{"spec":{"hard":{"requests.cpu":"4"}}}'

# Or update in workshop-values.yaml and re-sync
```

---

**Issue:** PVC won't bind

**Solution:**
```bash
# Check PVC status
oc get pvc -n user01-dev

# Check events
oc describe pvc <pvc-name> -n user01-dev

# Verify StorageClass
oc get sc

# Check available PVs
oc get pv

# If no PVs available, check storage backend
```

### Network Issues

**Issue:** Workspace cannot reach external services

**Solution:**
```bash
# From workspace terminal, test connectivity
curl -I https://github.com
curl -I https://api.openai.com

# Check NetworkPolicy if enabled
oc get networkpolicy -n user01-dev

# Check egress rules
oc describe networkpolicy -n user01-dev

# Verify DNS
nslookup github.com
nslookup api.openshift.com
```

---

**Issue:** Solution Server unreachable from workspace

**Solution:**
```bash
# Check Solution Server service
oc get svc -n openshift-mta -l app.kubernetes.io/component=solution-server

# Check route
oc get route -n openshift-mta

# Test from workspace
curl -v $MTA_SOLUTION_SERVER_URL/health

# Check if NetworkPolicy blocks traffic
oc get networkpolicy -n user01-dev
oc get networkpolicy -n openshift-mta
```

## Destroy Issues

**Issue:** Application won't delete

**Solution:**
```bash
# Check Application status
oc get application <app-name> -n openshift-gitops -o yaml

# Check finalizers
oc patch application <app-name> -n openshift-gitops --type json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'

# Force delete if needed (use with caution)
oc delete application <app-name> -n openshift-gitops --grace-period=0 --force
```

---

**Issue:** Namespace stuck in Terminating

**Solution:**
```bash
# Check namespace status
oc get namespace user01-dev -o yaml

# Check for stuck resources
oc api-resources --verbs=list --namespaced -o name | xargs -n 1 oc get --show-kind --ignore-not-found -n user01-dev

# Remove finalizers
oc patch namespace user01-dev -p '{"metadata":{"finalizers":null}}' --type=merge

# If still stuck, check for stuck pods
oc get pods -n user01-dev
oc delete pod <pod-name> -n user01-dev --grace-period=0 --force
```

## Performance Issues

**Issue:** Workspace startup is very slow

**Solution:**
- Check cluster resources (CPU, memory, storage)
- Review image pull times
- Consider using faster StorageClass
- Increase workspace resource requests
- Pre-pull images on nodes

**Issue:** MTA analysis takes too long

**Solution:**
- Check workspace resource limits
- Verify Maven repository cache
- Check network connectivity to Maven Central
- Review project size

## Getting Additional Help

1. **Check logs** for all relevant components
2. **Review events** in affected namespaces
3. **Search documentation**:
   - OpenShift: https://docs.openshift.com
   - Dev Spaces: https://access.redhat.com/documentation/en-us/red_hat_openshift_dev_spaces
   - MTA: https://access.redhat.com/documentation/en-us/migration_toolkit_for_applications
4. **Contact support** with:
   - Error messages
   - Component versions
   - Steps to reproduce
   - Relevant logs

## Useful Commands

```bash
# Cluster health
oc get nodes
oc get co  # Cluster Operators

# Application status
oc get applications -n openshift-gitops

# All workshop resources
oc get all -n user01-dev

# Events across namespaces
oc get events --all-namespaces --sort-by='.lastTimestamp'

# Resource usage
oc adm top nodes
oc adm top pods -n user01-dev

# Logs
oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller --tail=100 -f
oc logs -n openshift-devspaces -l app.kubernetes.io/component=devspaces --tail=100 -f
oc logs -n openshift-mta -l app.kubernetes.io/component=tackle-hub --tail=100 -f
```
