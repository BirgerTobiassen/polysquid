#!/bin/bash

set -o pipefail

REPO_DIR="/opt/polysquid"
LOG_FILE="/var/log/polysquid-git-update.log"
TRUSTED_EXEC="/usr/local/lib/polysquid/polysquid.py"

GIT_BRANCH_FILE="/etc/polysquid/git-branch"

cd "$REPO_DIR" || { echo "$(date): Failed to cd to $REPO_DIR" | tee -a "$LOG_FILE"; exit 1; }

if [ ! -x "$TRUSTED_EXEC" ]; then
    echo "$(date): Trusted executor missing or not executable: $TRUSTED_EXEC" | tee -a "$LOG_FILE"
    exit 1
fi

CONFIGURED_GIT_BRANCH=""
if [ -f "$GIT_BRANCH_FILE" ]; then
    IFS= read -r CONFIGURED_GIT_BRANCH < "$GIT_BRANCH_FILE" || true
fi

if [ -z "$CONFIGURED_GIT_BRANCH" ]; then
    remote_head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD || true)
    if [ -z "$remote_head" ]; then
        if ! git remote set-head origin --auto >/dev/null; then
            echo "$(date): Could not determine origin's default branch" | tee -a "$LOG_FILE"
            exit 1
        fi
        remote_head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD || true)
    fi
    case "$remote_head" in
        origin/*) CONFIGURED_GIT_BRANCH="${remote_head#origin/}" ;;
        *)
            echo "$(date): Could not determine origin's default branch" | tee -a "$LOG_FILE"
            exit 1
            ;;
    esac
fi

if ! git check-ref-format "refs/heads/$CONFIGURED_GIT_BRANCH"; then
    echo "$(date): Invalid configured branch '$CONFIGURED_GIT_BRANCH'" | tee -a "$LOG_FILE"
    exit 1
fi

if ! git fetch --quiet --no-tags origin "+refs/heads/$CONFIGURED_GIT_BRANCH:refs/remotes/origin/$CONFIGURED_GIT_BRANCH"; then
    echo "$(date): Could not fetch branch '$CONFIGURED_GIT_BRANCH' from origin" | tee -a "$LOG_FILE"
    exit 1
fi

current_commit=$(git rev-parse HEAD 2>/dev/null || echo "")
target_ref="refs/remotes/origin/$CONFIGURED_GIT_BRANCH"
target_commit=$(git rev-parse "$target_ref^{commit}" 2>/dev/null || echo "")
if [ -z "$target_commit" ]; then
    echo "$(date): Could not resolve branch '$CONFIGURED_GIT_BRANCH'" | tee -a "$LOG_FILE"
    exit 1
fi

current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
if [ "$current_commit" = "$target_commit" ] && [ "$current_branch" = "$CONFIGURED_GIT_BRANCH" ]; then
    echo "$(date): Already up to date on branch '$CONFIGURED_GIT_BRANCH'" | tee -a "$LOG_FILE"
    exit 0
fi

if ! git checkout --quiet -B "$CONFIGURED_GIT_BRANCH" "$target_ref"; then
    echo "$(date): Failed to check out branch '$CONFIGURED_GIT_BRANCH'" | tee -a "$LOG_FILE"
    exit 1
fi

echo "$(date): Checked out branch '$CONFIGURED_GIT_BRANCH' ($current_commit -> $target_commit)" | tee -a "$LOG_FILE"
if [ "$current_commit" = "$target_commit" ]; then
    echo "$(date): Reattached to branch '$CONFIGURED_GIT_BRANCH'; no config change to reconcile" | tee -a "$LOG_FILE"
    exit 0
fi

if [ ! -f "$REPO_DIR/services.yaml" ]; then
    echo "$(date): services.yaml not found after checking out '$CONFIGURED_GIT_BRANCH'" | tee -a "$LOG_FILE"
    exit 1
fi

echo "$(date): Branch updated, running trusted polysquid executor" | tee -a "$LOG_FILE"
if /usr/bin/python3 "$TRUSTED_EXEC" --config "$REPO_DIR/services.yaml" --base-dir "$REPO_DIR" 2>&1 | tee -a "$LOG_FILE"; then
    echo "$(date): trusted polysquid executor completed successfully" | tee -a "$LOG_FILE"
else
    pipeline_status=("${PIPESTATUS[@]}")
    result="${pipeline_status[0]}"
    if [ "$result" -eq 0 ]; then
        result="${pipeline_status[1]}"
    fi
    echo "$(date): trusted polysquid executor failed with exit code $result" | tee -a "$LOG_FILE"
    exit "$result"
fi
