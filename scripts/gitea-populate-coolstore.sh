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

# Path to devfile.yaml template (in workshop-provisioning repo)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVFILE_TEMPLATE="${SCRIPT_DIR}/../templates/coolstore-eap7/devfile.yaml"

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
            \"internal\": false,
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

    # Replace namespace in scripts and deployment files
    log "  - Updating PROJECT_NAME to ${user_namespace}"
    sed -i.bak "s|user01-dev|${user_namespace}|g" \
        scripts/openshift/eap7/01-setup.sh \
        scripts/openshift/eap7/02-build.sh \
        scripts/openshift/eap7/03-deploy.sh \
        openshift/deployment.yaml

    # Replace Git repository URL in scripts
    log "  - Updating GIT_REPOSITORY to ${user_git_url}"
    sed -i.bak "s|https://github.com/kamorisan/coolstore-eap7.git|${user_git_url}|g" \
        scripts/openshift/eap7/01-setup.sh

    # Replace Git branch ref (GitHub: ocp-s2i-eap7 → Gitea: main)
    log "  - Updating GIT_REF from ocp-s2i-eap7 to main"
    sed -i.bak "s|ocp-s2i-eap7|main|g" \
        scripts/openshift/eap7/01-setup.sh

    # Add sourceSecret to BuildConfig for Git authentication
    log "  - Adding sourceSecret to BuildConfig"
    sed -i.bak '/contextDir: ""/a\
    sourceSecret:\
      name: gitea-git-secret' \
        scripts/openshift/eap7/01-setup.sh

    # Copy and customize devfile.yaml for DevSpaces
    log "  - Adding devfile.yaml for DevSpaces"
    if [ -f "${DEVFILE_TEMPLATE}" ]; then
        cp "${DEVFILE_TEMPLATE}" devfile.yaml
        # Update Git URL in devfile.yaml
        sed -i.bak "s|https://github.com/kamorisan/coolstore-eap7|${user_git_url%.git}|g" devfile.yaml
    else
        warn "devfile.yaml template not found at ${DEVFILE_TEMPLATE}"
        warn "Skipping devfile.yaml creation"
    fi

    # Add MTA setup script
    log "  - Adding setup-mta-config.sh script"
    cat > .devspaces/setup-mta-config.sh <<'SCRIPT_EOF'
#!/bin/bash
set -u

LOG_FILE="/tmp/setup-mta-config.log"
SOURCE_FILE="/projects/coolstore-eap7/.devspaces/provider-settings.yaml"
SETTINGS_DIR="/checode/remote/data/User/globalStorage/redhat.mta-core/settings"
TARGET_FILE="${SETTINGS_DIR}/provider-settings.yaml"

exec >>"${LOG_FILE}" 2>&1

echo "[$(date -Iseconds)] setup-mta-config started"
echo "user=$(id)"
echo "pwd=$(pwd)"

for i in $(seq 1 60); do
  if [ -f "${SOURCE_FILE}" ]; then
    break
  fi
  echo "[$(date -Iseconds)] waiting for ${SOURCE_FILE}: ${i}/60"
  sleep 2
done

if [ ! -f "${SOURCE_FILE}" ]; then
  echo "[$(date -Iseconds)] ERROR: source file not found"
  exit 1
fi

mkdir -p "${SETTINGS_DIR}"

if [ -f "${TARGET_FILE}" ] && cmp -s "${SOURCE_FILE}" "${TARGET_FILE}"; then
  echo "[$(date -Iseconds)] target is already up to date"
  exit 0
fi

TMP_FILE="${TARGET_FILE}.tmp.$$"
cp "${SOURCE_FILE}" "${TMP_FILE}"
chmod 0644 "${TMP_FILE}"
mv -f "${TMP_FILE}" "${TARGET_FILE}"

test -s "${TARGET_FILE}"
echo "[$(date -Iseconds)] setup-mta-config completed"
ls -l "${TARGET_FILE}"
SCRIPT_EOF
    chmod +x .devspaces/setup-mta-config.sh

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

    # Force add .vscode/extensions.json (ignored by .gitignore but needed for DevWorkspace)
    if [ -f ".vscode/extensions.json" ]; then
        git add -f .vscode/extensions.json
        log "  - Added .vscode/extensions.json"
    fi

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
