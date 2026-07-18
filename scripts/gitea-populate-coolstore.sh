#!/bin/bash
#
# Gitea Repository Population Script for Coolstore EAP7
#
# This script:
# 1. Clones coolstore-eap7 from GitHub (ocp-s2i-eap7 branch)
# 2. Creates repositories in Gitea for user01-user10
# 3. Customizes scripts for each user (namespace and Git URL)
# 4. Pushes to each user's Gitea repository
#

set -euo pipefail

# Configuration
GITEA_URL="${GITEA_URL:-https://gitea-gitea.apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com}"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-gitea-admin}"
GITEA_ADMIN_PASSWORD="${GITEA_ADMIN_PASSWORD:-}"

SOURCE_REPO="https://github.com/kamorisan/coolstore-eap7.git"
SOURCE_BRANCH="ocp-s2i-eap7"

TEMP_DIR="${TEMP_DIR:-/tmp/coolstore-eap7-populate}"
USER_COUNT="${USER_COUNT:-10}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v git &> /dev/null; then
        error "git is not installed"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        error "curl is not installed"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        error "jq is not installed"
        exit 1
    fi

    if [ -z "${GITEA_ADMIN_PASSWORD}" ]; then
        error "GITEA_ADMIN_PASSWORD environment variable is required"
        echo "Usage: GITEA_ADMIN_PASSWORD='your-password' $0"
        exit 1
    fi

    log "✓ Prerequisites check passed"
}

# Test Gitea API connectivity
test_gitea_api() {
    log "Testing Gitea API connectivity..."

    local response
    response=$(curl -fsS -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
        "${GITEA_URL}/api/v1/version" 2>&1 | jq -r '.version' 2>/dev/null || echo "")

    if [ -z "${response}" ]; then
        error "Failed to connect to Gitea API at ${GITEA_URL}"
        error "Please check:"
        error "  1. Gitea URL is correct"
        error "  2. Admin credentials are valid"
        error "  3. Gitea is accessible"
        exit 1
    fi

    log "✓ Connected to Gitea ${response}"
}

# Clone source repository
clone_source() {
    log "Cloning source repository..."

    rm -rf "${TEMP_DIR}"

    if ! git clone -b "${SOURCE_BRANCH}" --single-branch "${SOURCE_REPO}" "${TEMP_DIR}"; then
        error "Failed to clone ${SOURCE_REPO} branch ${SOURCE_BRANCH}"
        exit 1
    fi

    log "✓ Cloned ${SOURCE_REPO} (${SOURCE_BRANCH})"
}

# Create repository in Gitea for a user
create_gitea_repo() {
    local username="$1"

    log "Creating repository for ${username}..."

    local response
    response=$(curl -fsS -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
        -X POST "${GITEA_URL}/api/v1/admin/users/${username}/repos" \
        -H 'Content-Type: application/json' \
        -d "{
            \"name\": \"coolstore-eap7\",
            \"description\": \"Coolstore EAP7 Application for ${username}\",
            \"private\": false,
            \"auto_init\": false,
            \"default_branch\": \"main\"
        }" 2>&1)

    if echo "${response}" | jq -e '.id' >/dev/null 2>&1; then
        log "✓ Repository created for ${username}"
        return 0
    elif echo "${response}" | grep -q "already exists"; then
        warn "Repository already exists for ${username}"
        return 0
    else
        error "Failed to create repository for ${username}"
        echo "${response}" | jq '.' 2>/dev/null || echo "${response}"
        return 1
    fi
}

# Customize repository for a specific user
customize_for_user() {
    local username="$1"
    local user_namespace="${username}-dev"
    local user_git_url="${GITEA_URL}/${username}/coolstore-eap7.git"
    local work_dir="${TEMP_DIR}-${username}"

    log "Customizing repository for ${username}..."

    # Copy template to user-specific directory
    rm -rf "${work_dir}"
    cp -r "${TEMP_DIR}" "${work_dir}"
    cd "${work_dir}"

    # Remove existing Git metadata
    rm -rf .git

    # Replace namespace in scripts
    log "  - Updating PROJECT_NAME to ${user_namespace}"
    sed -i.bak "s|user01-dev|${user_namespace}|g" \
        scripts/openshift/eap7/01-setup.sh \
        scripts/openshift/eap7/02-build.sh \
        scripts/openshift/eap7/03-deploy.sh

    # Replace Git repository URL in scripts
    log "  - Updating GIT_REPOSITORY to ${user_git_url}"
    sed -i.bak "s|https://github.com/kamorisan/coolstore-eap7.git|${user_git_url}|g" \
        scripts/openshift/eap7/01-setup.sh

    # Create devfile.yaml for DevSpaces
    log "  - Creating devfile.yaml for DevSpaces"
    cat > devfile.yaml <<EOF
schemaVersion: 2.3.0
metadata:
  name: coolstore-modernization-workshop
  displayName: Coolstore Modernization Workshop (${username})
  description: Workshop environment for modernizing EAP7 application with Red Hat Developer Lightspeed
  language: java
  projectType: maven
  tags:
    - Java
    - EAP
    - Migration
    - Modernization
  version: 1.0.0

projects:
  - name: coolstore-eap7
    git:
      remotes:
        origin: ${user_git_url}
      checkoutFrom:
        revision: main

components:
  - name: dev-tools
    container:
      image: registry.redhat.io/devspaces/udi-rhel9:latest
      memoryRequest: 2Gi
      memoryLimit: 8Gi
      cpuRequest: 500m
      cpuLimit: 2000m
      mountSources: true
      sourceMapping: /projects
      volumeMounts:
        - name: m2
          path: /home/user/.m2
      env:
        - name: MAVEN_OPTS
          value: "-Xmx2g"

  - name: m2
    volume:
      size: 10Gi

commands:
  - id: oc-auto-login
    exec:
      component: dev-tools
      commandLine: |
        #!/bin/bash
        USERNAME=\$(echo "\${DEVWORKSPACE_NAMESPACE}" | sed 's/-dev\$//')
        OCP_API=\$(oc whoami --show-server 2>/dev/null || echo "https://kubernetes.default.svc")

        if oc login --insecure-skip-tls-verify=true "\$OCP_API" -u "\$USERNAME" -p "openshift" >/dev/null 2>&1; then
          echo "✅ Logged in as \$USERNAME"
        else
          echo "⚠️ Auto-login skipped"
        fi
        exit 0
      workingDir: \${PROJECT_SOURCE}
      label: "Auto-login to OpenShift"
      group:
        kind: run
        isDefault: false

  - id: setup-mta-config
    exec:
      component: dev-tools
      commandLine: |
        SETTINGS_DIR="/checode/remote/data/User/globalStorage/redhat.mta-core/settings"
        SOURCE_FILE="/projects/coolstore-eap7/.devspaces/provider-settings.yaml"
        TARGET_FILE="\$SETTINGS_DIR/provider-settings.yaml"
        echo "Setting up MTA configuration..."
        MAX_WAIT=60
        WAITED=0
        while [ ! -d "/projects/coolstore-eap7" ] && [ \$WAITED -lt \$MAX_WAIT ]; do
          echo "Waiting for coolstore-eap7 project... (\$WAITED/\$MAX_WAIT)"
          sleep 5
          WAITED=\$((WAITED + 5))
        done
        mkdir -p "\$SETTINGS_DIR"
        if [ -f "\$SOURCE_FILE" ]; then
          cp -f "\$SOURCE_FILE" "\$TARGET_FILE"
          chmod 644 "\$TARGET_FILE"
          echo "MTA provider settings configured successfully"
          echo "Source: \$SOURCE_FILE"
          echo "Target: \$TARGET_FILE"
          ls -la "\$SETTINGS_DIR/"
        else
          echo "Warning: Source file not found: \$SOURCE_FILE"
          echo "Please ensure .devspaces/provider-settings.yaml exists in coolstore-eap7 repository"
        fi
        exit 0
      workingDir: /projects
      label: "Setup MTA Configuration"
      group:
        kind: run
        isDefault: false

  - id: maven-build
    exec:
      component: dev-tools
      commandLine: mvn clean package -DskipTests
      workingDir: \${PROJECT_SOURCE}/coolstore-eap7
      label: "Build"
      group:
        kind: build
        isDefault: false

  - id: maven-test
    exec:
      component: dev-tools
      commandLine: mvn test
      workingDir: \${PROJECT_SOURCE}/coolstore-eap7
      label: "Test"
      group:
        kind: test

  - id: run-app
    exec:
      component: dev-tools
      commandLine: mvn spring-boot:run
      workingDir: \${PROJECT_SOURCE}/coolstore-eap7
      label: "Run Application"
      group:
        kind: run
        isDefault: false

events:
  postStart:
    - setup-mta-config
EOF

    # Clean up backup files
    find . -name "*.bak" -delete

    # Add user-specific README section
    cat >> README.md <<EOF

---

## Workshop User: ${username}

This repository is customized for workshop user **${username}**.

### Configuration

- **Namespace**: \`${user_namespace}\`
- **Git Repository**: ${user_git_url}
- **Default Branch**: \`main\`

---

## Quick Start Options

### Option 1: OpenShift DevSpaces (Recommended for Workshop)

1. **Open DevSpaces Dashboard**
   - Access your DevSpaces instance

2. **Create Workspace from this repository**
   - Click "Create Workspace"
   - Enter Git repository URL: \`${user_git_url}\`
   - DevSpaces will automatically use the \`devfile.yaml\` in this repository

3. **Workspace will auto-configure**
   - Clone this repository
   - Setup Maven environment
   - Configure MTA (Migration Toolkit for Applications)
   - Auto-login to OpenShift as ${username}

4. **Available commands** (from Terminal in DevSpaces)
   \`\`\`bash
   # Build application
   mvn clean package -DskipTests

   # Deploy to OpenShift
   ./scripts/openshift/eap7/01-setup.sh
   ./scripts/openshift/eap7/02-build.sh
   ./scripts/openshift/eap7/03-deploy.sh
   \`\`\`

---

### Option 2: Local Development / CLI

\`\`\`bash
# 1. Clone this repository
git clone ${user_git_url}
cd coolstore-eap7

# 2. Login to OpenShift
oc login <cluster-url> -u ${username} -p openshift

# 3. Deploy (scripts already configured for your user)
./scripts/openshift/eap7/01-setup.sh
./scripts/openshift/eap7/02-build.sh
./scripts/openshift/eap7/03-deploy.sh

# 4. Access your application
oc get route -n ${user_namespace}
\`\`\`

---

## DevSpaces Features

This repository includes a \`devfile.yaml\` that configures:

- **Java Development Environment**: Red Hat UBI 9 with Java, Maven
- **Memory**: 2-8Gi for build/runtime
- **Persistent Maven Cache**: 10Gi volume for faster builds
- **Auto-configuration**:
  - Auto-login to OpenShift as ${username}
  - MTA extension configuration from \`.devspaces/provider-settings.yaml\`
- **Pre-configured commands**:
  - Build, Test, Run application
  - OpenShift deployment scripts

---

## Environment Variables (Optional Override)

The scripts use the following defaults (already customized for you):

\`\`\`bash
PROJECT_NAME="${user_namespace}"
GIT_REPOSITORY="${user_git_url}"
GIT_REF="main"
\`\`\`

You can override these by exporting environment variables before running scripts.

---

**Note**: This repository was automatically generated from \`github.com/kamorisan/coolstore-eap7\` (ocp-s2i-eap7 branch) and customized for ${username}.
EOF

    log "✓ Customization complete for ${username}"
}

# Push to Gitea
push_to_gitea() {
    local username="$1"
    local user_git_url="${GITEA_URL}/${username}/coolstore-eap7.git"
    local work_dir="${TEMP_DIR}-${username}"

    log "Pushing to Gitea for ${username}..."

    cd "${work_dir}"

    # Initialize Git repository
    git init -b main
    git config user.name "Workshop Admin"
    git config user.email "admin@workshop.local"

    # Add all files
    git add .

    # Commit
    git commit -m "Initial commit for ${username}

Customized configuration:
- Namespace: ${username}-dev
- Git URL: ${user_git_url}
- Source: ${SOURCE_REPO} (${SOURCE_BRANCH})
"

    # Add remote and push
    # Push with authentication embedded in URL (for automation)
    local auth_url="${GITEA_URL/https:\/\//https://${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}@}"
    local auth_git_url="${auth_url}/${username}/coolstore-eap7.git"

    if git push -u "${auth_git_url}" main 2>&1; then
        log "✓ Pushed to ${user_git_url}"
        return 0
    else
        error "Failed to push for ${username}"
        return 1
    fi
}

# Process single user
process_user() {
    local username="$1"

    echo ""
    log "==================================="
    log "Processing ${username}"
    log "==================================="

    if ! create_gitea_repo "${username}"; then
        error "Skipping ${username} due to repository creation failure"
        return 1
    fi

    if ! customize_for_user "${username}"; then
        error "Skipping ${username} due to customization failure"
        return 1
    fi

    if ! push_to_gitea "${username}"; then
        error "Failed to push for ${username}"
        return 1
    fi

    log "✓ ${username} completed successfully"
    echo ""
}

# Main function
main() {
    log "==================================="
    log "Gitea Coolstore Population Script"
    log "==================================="
    log "Gitea URL: ${GITEA_URL}"
    log "Source: ${SOURCE_REPO} (${SOURCE_BRANCH})"
    log "Users: user01 - user${USER_COUNT}"
    log "==================================="
    echo ""

    check_prerequisites
    test_gitea_api
    clone_source

    local success_count=0
    local fail_count=0

    for i in $(seq -f "%02g" 1 "${USER_COUNT}"); do
        username="user${i}"

        if process_user "${username}"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done

    echo ""
    log "==================================="
    log "Summary"
    log "==================================="
    log "Successful: ${success_count}/${USER_COUNT}"
    log "Failed: ${fail_count}/${USER_COUNT}"
    log "==================================="

    if [ "${fail_count}" -gt 0 ]; then
        exit 1
    fi

    log "✓ All users completed successfully"
}

# Run main function
main "$@"
