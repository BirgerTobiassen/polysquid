#!/bin/bash

# Uninstall script for polysquid
# Removes systemd units/timers, logrotate entries, and update helper installed by install.sh.
# Use --purge to also remove /opt/polysquid and /var/log/polysquid-update.log.

set -euo pipefail

SERVICE_NAME="polysquid-update"
RECONCILE_SERVICE_NAME="polysquid-reconcile"
RECONCILE_PATH_NAME="polysquid-reconcile"
TRUSTED_DIR="/usr/local/lib/polysquid"
TRUSTED_EXEC="${TRUSTED_DIR}/polysquid.py"
TRUSTED_UPDATE="${TRUSTED_DIR}/polysquid-update.sh"
REPO_DIR="/opt/polysquid"
UPDATE_LOG="/var/log/polysquid-update.log"
PURGE=false

if [[ "${1:-}" == "--purge" ]]; then
    PURGE=true
fi

# Check if running as root
if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root (sudo $0 [--purge])"
    exit 1
fi

echo "Stopping and disabling update timer/service..."
systemctl disable --now "${SERVICE_NAME}.timer" 2>/dev/null || true
systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true
systemctl disable --now "${RECONCILE_SERVICE_NAME}.service" 2>/dev/null || true
systemctl disable --now "${RECONCILE_PATH_NAME}.path" 2>/dev/null || true

echo "Stopping and disabling generated squid services/timers..."
# Stop timers first so they cannot race and restart services during uninstall.
for unit in /etc/systemd/system/squid-*.timer; do
    if [[ -e "$unit" ]]; then
        unit_name="$(basename "$unit")"
        systemctl disable --now "$unit_name" 2>/dev/null || true
    fi
done

echo "Force-removing running squid containers (name prefix: squid_)..."
if command -v docker >/dev/null 2>&1; then
    mapfile -t SQUID_CONTAINERS < <(docker ps -aq --filter "name=^squid_")
    if [[ "${#SQUID_CONTAINERS[@]}" -gt 0 ]]; then
        docker rm -f "${SQUID_CONTAINERS[@]}" >/dev/null 2>&1 || true
    fi
fi

# Units are disabled without --now because containers are already removed above.
for unit in /etc/systemd/system/squid-*.service /etc/systemd/system/squid-*.timer; do
    if [[ -e "$unit" ]]; then
        unit_name="$(basename "$unit")"
        systemctl disable "$unit_name" 2>/dev/null || true
    fi
done

echo "Removing generated systemd unit links/files..."
rm -f /etc/systemd/system/${SERVICE_NAME}.service
rm -f /etc/systemd/system/${SERVICE_NAME}.timer
rm -f /etc/systemd/system/${RECONCILE_SERVICE_NAME}.service
rm -f /etc/systemd/system/${RECONCILE_PATH_NAME}.path
rm -f /etc/systemd/system/squid-*.service
rm -f /etc/systemd/system/squid-*.timer

echo "Removing logrotate entries..."
rm -f /etc/logrotate.d/polysquid-update
rm -f /etc/logrotate.d/squid-*

echo "Removing trusted updater and executor..."
rm -f "$TRUSTED_UPDATE"
rm -f "$TRUSTED_EXEC"
rmdir "$TRUSTED_DIR" 2>/dev/null || true

if [[ "$PURGE" == true ]]; then
    echo "Purge enabled: removing $REPO_DIR and update log..."
    rm -rf "$REPO_DIR"
    rm -f "$UPDATE_LOG"
fi

echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Uninstall complete."
if [[ "$PURGE" == false ]]; then
    echo "Tip: run '$0 --purge' to also remove $REPO_DIR and $UPDATE_LOG"
fi
