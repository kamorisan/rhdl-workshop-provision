# DevWorkspace MTA Setup Issue Report

**Date**: 2026-07-19  
**Issue**: `setup-mta-config` postStart event not executing in Gitea-based DevWorkspaces

---

## 🔴 Current Problem

MTA provider settings file is **NOT** being copied automatically when DevWorkspace starts:
- **Source**: `/projects/coolstore-eap7/.devspaces/provider-settings.yaml` 
- **Target**: `/checode/remote/data/User/globalStorage/redhat.mta-core/settings/provider-settings.yaml`
- **Expected**: postStart event should execute `setup-mta-config` command automatically
- **Actual**: Command does not execute; manual execution works

---

## ✅ What Works

### Manual Execution
```bash
# This works when run manually in the workspace terminal
oc exec -n user01-devspaces $POD_NAME -c dev-tools -- bash -c '
SETTINGS_DIR="/checode/remote/data/User/globalStorage/redhat.mta-core/settings"
SOURCE_FILE="/projects/coolstore-eap7/.devspaces/provider-settings.yaml"
TARGET_FILE="$SETTINGS_DIR/provider-settings.yaml"
mkdir -p "$SETTINGS_DIR"
cp -f "$SOURCE_FILE" "$TARGET_FILE"
chmod 644 "$TARGET_FILE"
'
```
✅ **Result**: File copied successfully

### Source File Exists
```bash
ls -la /projects/coolstore-eap7/.devspaces/
# provider-settings.yaml exists in Gitea repo and workspace
```
✅ **Verified**: File is present in all user repositories (user01-user10)

---

## 🔍 Investigation

### Comparison: GitHub Direct vs Gitea-based

| Aspect | GitHub Direct (Working Before) | Gitea-based (Current - Not Working) |
|--------|--------------------------------|-------------------------------------|
| **devfile.yaml location** | GitHub repo root | Gitea repo root |
| **Branch** | `ocp-s2i-eap7` | `main` |
| **Deployment method** | DevWorkspace from URL | DevWorkspace CR template |
| **postStart events** | `- setup-mta-config` | `- oc-auto-login`<br>`- setup-mta-config` |

### Key Difference Found

**GitHub Direct devfile.yaml** (workshop-provisioning/devfile.yaml):
```yaml
events:
  postStart:
    - setup-mta-config  # Only one command
```

**Current DevWorkspace template**:
```yaml
events:
  postStart:
    - oc-auto-login      # Added this
    - setup-mta-config   # Still present
```

### DevWorkspace Status Check

```bash
# DevWorkspace CR shows correct events
oc get devworkspace coolstore-modernization-workshop -n user01-devspaces \
  -o jsonpath='{.spec.template.events.postStart}'
# Output: ["oc-auto-login","setup-mta-config"]
```
✅ Events are correctly defined in the CR

### Execution Verification

**che-code status**:
- ✅ che-code server is running (Server bound to 127.0.0.1:3100)
- ✅ Pod status: Running
- ✅ DevWorkspace phase: Running

**Logs checked**:
- ❌ No evidence of postStart command execution in container logs
- ❌ No "Setting up MTA configuration..." messages
- ❌ No errors related to postStart

---

## 🤔 Hypothesis: Branch Name Impact?

### Question: Does branch name affect postStart execution?

**Gitea Repository Details**:
- **Source**: GitHub `ocp-s2i-eap7` branch
- **Gitea**: Mapped to `main` branch during clone
- **devfile.yaml revision**: `main` (in DevWorkspace git spec)

```yaml
projects:
  - name: coolstore-eap7
    git:
      remotes:
        origin: https://user01:openshift@gitea.../user01/coolstore-eap7
      checkoutFrom:
        revision: main  # ← Using 'main' not 'ocp-s2i-eap7'
```

**Analysis**:
- Branch name should NOT affect postStart execution
- postStart is a devfile event, not a git event
- The devfile.yaml content is identical regardless of branch name

---

## 🔎 Root Cause Analysis

### DevWorkspace postStart Event Lifecycle

Based on DevWorkspace Operator behavior:

1. **Pod starts** → initContainers run (project-clone, che-code-injector)
2. **Containers start** → dev-tools, che-gateway
3. **che-code server starts** → Listening on port 3100
4. **⚠️ postStart events execute** → **ONLY WHEN**:
   - User accesses the workspace via Web UI
   - che-code IDE fully initializes
   - devfile commands are registered

### Key Finding

**postStart events are IDE-driven, not pod-driven**

From che-code entrypoint logs:
```
[00:40:01] Extension host agent started.
[00:40:01] Started initializing default profile extensions...
```

But NO logs showing:
```
# Expected but missing:
Running postStart command: oc-auto-login
Running postStart command: setup-mta-config
```

### Comparison with GitHub Direct

**Possible difference**:
- GitHub direct DevWorkspace may use a different che-code version
- Different devfile schema version (2.3.0 vs 2.2.2)
- Different DevWorkspace Operator configuration

---

## 📊 Evidence

### 1. Source File Exists
```bash
curl -u admin:pass \
  "https://gitea.../api/v1/repos/user01/coolstore-eap7/contents/.devspaces/provider-settings.yaml?ref=main"
# HTTP 200 - File exists
```

### 2. DevWorkspace Events Configured
```bash
oc get devworkspace -n user01-devspaces -o json | jq '.spec.template.events'
# {
#   "postStart": ["oc-auto-login", "setup-mta-config"]
# }
```

### 3. Commands Defined
```bash
oc get devworkspace -n user01-devspaces -o json | \
  jq '.spec.template.commands[] | select(.id == "setup-mta-config")'
# Command exists with correct script
```

### 4. Manual Execution Works
```bash
# Verified that the script logic is correct
# File copies successfully when run manually
```

---

## 🚨 Critical Question

**Why does postStart work in GitHub-direct but not Gitea-based?**

### Possibilities:

1. **Web UI Access Required**
   - postStart only executes when user opens workspace in browser
   - We tested via `oc exec` (CLI) not via Web UI
   - **Action**: Need to test by actually accessing DevSpaces dashboard

2. **DevWorkspace Operator Version Difference**
   - Different operator versions may handle postStart differently
   - **Action**: Check DevWorkspace Operator version

3. **Devfile Schema Version**
   - GitHub direct: uses devfile 2.x from source
   - Template: wrapped in DevWorkspace v1alpha2 API
   - **Action**: Check if schema conversion affects events

4. **Timing Issue**
   - oc-auto-login added BEFORE setup-mta-config
   - If oc-auto-login fails, does it stop the chain?
   - **Action**: Check oc-auto-login execution

---

## 🔧 Recommended Next Steps

### Step 1: Verify Web UI Access Trigger
```bash
# Access workspace via DevSpaces dashboard (not CLI)
# Open https://devspaces.../user01/coolstore-modernization-workshop
# Check Terminal output for:
# "Setting up MTA configuration..."
```

### Step 2: Check oc-auto-login Impact
```bash
# Temporarily remove oc-auto-login from postStart
# Test if setup-mta-config runs alone
events:
  postStart:
    # - oc-auto-login  # Commented out for test
    - setup-mta-config
```

### Step 3: Compare DevWorkspace Schemas
```bash
# GitHub direct creates DevWorkspace differently
# Check if annotation metadata differs
```

### Step 4: Fallback Solutions (If postStart Cannot Be Fixed)

**Option A**: Add to .bashrc
```bash
# Auto-run on first terminal open
if [ ! -f /checode/remote/data/User/globalStorage/redhat.mta-core/settings/provider-settings.yaml ]; then
  # Run setup-mta-config
fi
```

**Option B**: Add README instruction
```markdown
# First-time Setup
Run this command in terminal:
setup-mta-config
```

**Option C**: initContainer (Requires pod-overrides support)
- Currently not working due to DevWorkspace Operator limitations

---

## 📝 Summary

| Item | Status |
|------|--------|
| Source file in Gitea | ✅ Present |
| devfile.yaml events configured | ✅ Correct |
| Manual execution | ✅ Works |
| Automatic postStart execution | ❌ **Not working** |
| Branch name (main vs ocp-s2i-eap7) | ⚠️ Unlikely to be the cause |

**Recommended Action**: 
1. Test workspace via Web UI (not just oc exec)
2. Check if postStart executes when IDE fully loads
3. If still not working, implement .bashrc auto-run as fallback

---

## 🔗 Related Files

- `/Users/kamori/vscode/developer-lightspeed/workshop-provisioning/devfile.yaml` (GitHub direct - working before)
- `/Users/kamori/vscode/developer-lightspeed/workshop-provisioning/scripts/workspace/devworkspace-template.yaml` (Current template)
- Gitea repos: `https://gitea.../user{01-10}/coolstore-eap7` (main branch)
