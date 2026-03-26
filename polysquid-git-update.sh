#!/bin/bash

REPO_DIR="/opt/polysquid"
LOG_FILE="/var/log/polysquid-update.log"
TRUSTED_EXEC="/usr/local/lib/polysquid/polysquid.py"

cd "$REPO_DIR" || { echo "$(date): Failed to cd to $REPO_DIR" | tee -a "$LOG_FILE"; exit 1; }

if [ ! -x "$TRUSTED_EXEC" ]; then
    echo "$(date): Trusted executor missing or not executable: $TRUSTED_EXEC" | tee -a "$LOG_FILE"
    exit 1
fi

# Helper: hash active self-service request files so dynamic whitelist changes trigger reconcile.
hash_requests() {
    local req_dir="$REPO_DIR/self-service/requests"
    if [ ! -d "$req_dir" ]; then
        echo ""
        return
    fi

    find "$req_dir" -maxdepth 1 -type f -name 'request_*.json' -print0 \
        | sort -z \
        | while IFS= read -r -d '' file; do
            sha256sum "$file"
        done \
        | sha256sum \
        | awk '{print $1}'
}

# Get current hashes
old_hash=$(git rev-parse HEAD:services.yaml 2>/dev/null || echo "")
old_req_hash=$(hash_requests)

# Pull latest changes
if git pull --quiet; then
    echo "$(date): Git pull successful" | tee -a "$LOG_FILE"
else
    echo "$(date): Failed to pull from Git" | tee -a "$LOG_FILE"
    exit 1
fi

# Get new hashes
new_hash=$(git rev-parse HEAD:services.yaml 2>/dev/null || echo "")
new_req_hash=$(hash_requests)

# Reconcile when either static config changes or dynamic self-service request files change.
if { [ "$old_hash" != "$new_hash" ] && [ -n "$new_hash" ]; } || [ "$old_req_hash" != "$new_req_hash" ]; then
    echo "$(date): Reconcile trigger detected (services.yaml: $old_hash -> $new_hash, requests: $old_req_hash -> $new_req_hash), running trusted polysquid executor" | tee -a "$LOG_FILE"
    if /usr/bin/python3 "$TRUSTED_EXEC" --config "$REPO_DIR/services.yaml" --base-dir "$REPO_DIR" 2>&1 | tee -a "$LOG_FILE"; then
        echo "$(date): trusted polysquid executor completed successfully" | tee -a "$LOG_FILE"
    else
        echo "$(date): trusted polysquid executor failed with exit code $?" | tee -a "$LOG_FILE"
    fi
else
    echo "$(date): No changes to services.yaml or self-service requests" | tee -a "$LOG_FILE"
fi