#!/usr/bin/env python3
import subprocess
import sys
import yaml
import time

# Configuration
USER_COUNT = 10
USERNAME_PREFIX = "user"
PASSWORD = "openshift"
API_URL = "https://api.cluster-59m78.59m78.sandbox1272.opentlc.com:6443"
REFERENCE_USER = "user01"
REFERENCE_NAMESPACE = f"{REFERENCE_USER}-devspaces"

def run_cmd(cmd, capture=True, check=True):
    """Run shell command"""
    if capture:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=check)
        return result.stdout.strip()
    else:
        return subprocess.run(cmd, shell=True, check=check)

def get_reference_workspace():
    """Get reference workspace name"""
    try:
        output = run_cmd(f"oc get devworkspace -n {REFERENCE_NAMESPACE} -o name")
        if not output:
            print(f"❌ No DevWorkspace found in {REFERENCE_NAMESPACE}")
            sys.exit(1)
        return output.split('/')[1].split('\n')[0]
    except Exception as e:
        print(f"❌ Failed to get reference workspace: {e}")
        sys.exit(1)

def get_template_name(workspace_name):
    """Get editor template name from workspace"""
    try:
        output = run_cmd(
            f"oc get devworkspace {workspace_name} -n {REFERENCE_NAMESPACE} "
            f"-o jsonpath='{{.spec.contributions[?(@.name==\"editor\")].kubernetes.name}}'"
        )
        if not output:
            print("❌ No editor template found")
            sys.exit(1)
        return output
    except Exception as e:
        print(f"❌ Failed to get template name: {e}")
        sys.exit(1)

def export_yaml(kind, name, namespace):
    """Export Kubernetes resource as YAML"""
    cmd = f"oc get {kind} {name} -n {namespace} -o yaml"
    output = run_cmd(cmd)
    doc = yaml.safe_load(output)

    # Clean metadata
    if 'metadata' in doc:
        for field in ['resourceVersion', 'uid', 'creationTimestamp', 'generation',
                     'managedFields', 'ownerReferences', 'selfLink', 'finalizers']:
            doc['metadata'].pop(field, None)

        # Clean annotations
        if 'annotations' in doc['metadata']:
            doc['metadata']['annotations'].pop('kubectl.kubernetes.io/last-applied-configuration', None)
            doc['metadata']['annotations'].pop('che.eclipse.org/last-updated-timestamp', None)
            doc['metadata']['annotations'].pop('controller.devfile.io/started-at', None)

        # Clean labels
        if 'labels' in doc['metadata']:
            doc['metadata']['labels'].pop('controller.devfile.io/creator', None)

    # Remove status
    doc.pop('status', None)

    return doc

def create_workspace_for_user(username, workspace_doc, template_doc, workspace_name, template_name):
    """Create workspace and template for a user"""
    namespace = f"{username}-devspaces"

    print(f"\n--- {username} ---")

    # Check if workspace already exists
    try:
        existing = run_cmd(f"oc get devworkspace -n {namespace} -o name 2>/dev/null", check=False)
        if existing:
            print("  ⚠️  Workspace already exists, skipping")
            return True
    except:
        pass

    # Login as user
    login_cmd = f"oc login --insecure-skip-tls-verify=true {API_URL} -u {username} -p {PASSWORD} >/dev/null 2>&1"
    result = run_cmd(login_cmd, capture=False, check=False)
    if result.returncode != 0:
        print("  ❌ Login failed")
        return False

    # Generate new template name
    new_template_name = f"{template_name}-{username}"

    # Create template
    template_copy = template_doc.copy()
    template_copy['metadata']['name'] = new_template_name
    template_copy['metadata']['namespace'] = namespace

    try:
        proc = subprocess.Popen(['oc', 'apply', '-f', '-'], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        proc.communicate(input=yaml.dump(template_copy).encode())
        if proc.returncode == 0:
            print(f"  ✅ Template: {new_template_name}")
        else:
            print(f"  ❌ Template creation failed")
            return False
    except Exception as e:
        print(f"  ❌ Template creation error: {e}")
        return False

    # Create workspace (stopped)
    workspace_copy = workspace_doc.copy()
    workspace_copy['metadata']['name'] = workspace_name
    workspace_copy['metadata']['namespace'] = namespace
    workspace_copy['spec']['started'] = False

    # Update template reference
    for contrib in workspace_copy['spec'].get('contributions', []):
        if contrib.get('name') == 'editor' and 'kubernetes' in contrib:
            contrib['kubernetes']['name'] = new_template_name

    try:
        proc = subprocess.Popen(['oc', 'apply', '-f', '-'], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        proc.communicate(input=yaml.dump(workspace_copy).encode())
        if proc.returncode == 0:
            print(f"  ✅ Workspace: {workspace_name} (Stopped)")
            return True
        else:
            print(f"  ❌ Workspace creation failed")
            return False
    except Exception as e:
        print(f"  ❌ Workspace creation error: {e}")
        return False

def main():
    print("=== DevWorkspace Replication from Reference ===")
    print(f"Reference: {REFERENCE_USER}")
    print(f"Target: {USERNAME_PREFIX}02 - {USERNAME_PREFIX}{USER_COUNT:02d}")
    print()

    # Step 1: Export reference
    print("Step 1: Exporting reference workspace...")

    workspace_name = get_reference_workspace()
    print(f"  Workspace: {workspace_name}")

    template_name = get_template_name(workspace_name)
    print(f"  Template: {template_name}")

    workspace_doc = export_yaml('devworkspace', workspace_name, REFERENCE_NAMESPACE)
    template_doc = export_yaml('devworkspacetemplate', template_name, REFERENCE_NAMESPACE)

    print("  ✅ Templates exported")

    # Step 2: Create for users
    print("\nStep 2: Creating workspaces...")

    success_count = 0
    for i in range(2, USER_COUNT + 1):
        username = f"{USERNAME_PREFIX}{i:02d}"
        if create_workspace_for_user(username, workspace_doc, template_doc, workspace_name, template_name):
            success_count += 1

    # Restore admin context
    run_cmd(f"oc config use-context default/api-cluster-59m78-59m78-sandbox1272-opentlc-com:6443/kube:admin >/dev/null 2>&1", check=False)

    # Summary
    print("\n=== Summary ===\n")
    time.sleep(3)
    print("Workspace Status:")
    run_cmd("oc get devworkspace -A | grep -E 'NAMESPACE|devspaces'", capture=False, check=False)

    print(f"\n✅ Created {success_count} workspaces")
    print("\nUsers can access their workspaces at:")
    print("https://devspaces.apps.cluster-59m78.59m78.sandbox1272.opentlc.com")

if __name__ == '__main__':
    main()
