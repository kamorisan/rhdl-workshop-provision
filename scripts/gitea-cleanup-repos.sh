#!/bin/bash
#
# Gitea Repository Cleanup Script
# Deletes coolstore-eap7 repositories for all workshop users
#

set -eo pipefail

GITEA_URL="${GITEA_URL:-https://gitea-gitea.apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com}"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-gitea-admin}"
GITEA_ADMIN_PASSWORD="${GITEA_ADMIN_PASSWORD:-}"
USER_COUNT="${USER_COUNT:-10}"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

if [ -z "${GITEA_ADMIN_PASSWORD}" ]; then
    error "GITEA_ADMIN_PASSWORD environment variable is required"
    echo "Usage: GITEA_ADMIN_PASSWORD='your-password' $0"
    exit 1
fi

log "==================================="
log "Gitea Repository Cleanup"
log "==================================="

for i in $(seq -f "%02g" 1 "${USER_COUNT}"); do
    username="user${i}"
    
    log "Deleting repository for ${username}..."

    http_code=$(curl -sS -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
        -X DELETE "${GITEA_URL}/api/v1/repos/${username}/coolstore-eap7" \
        -o /dev/null -w "%{http_code}")

    if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        log "✓ Deleted ${username}/coolstore-eap7"
    elif [ "$http_code" = "404" ]; then
        log "  (repository not found, skipping)"
    else
        error "Failed to delete ${username}/coolstore-eap7 (HTTP ${http_code})"
    fi
done

log "==================================="
log "✓ Cleanup complete"
log "==================================="
