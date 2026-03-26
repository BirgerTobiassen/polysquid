#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="polysquid-webapp:latest"
APP_CONTAINER="polysquid_webapp"
NGINX_CONTAINER="polysquid_nginx"
APP_UNIT="polysquid-webapp.service"
NGINX_UNIT="polysquid-nginx.service"
RECONCILE_SERVICE_UNIT="polysquid-self-service-reconcile.service"
RECONCILE_PATH_UNIT="polysquid-self-service-reconcile.path"
SYSTEMD_DIR="/etc/systemd/system"
REQUESTS_DIR="$SCRIPT_DIR/requests"
PURGE=false

if [[ "${1:-}" == "--purge" ]]; then
    PURGE=true
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root (sudo $0 [--purge])"
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemd is required"
    exit 1
fi

echo "Stopping and disabling self-service services"
systemctl disable --now "$NGINX_UNIT" 2>/dev/null || true
systemctl disable --now "$APP_UNIT" 2>/dev/null || true
systemctl disable --now "$RECONCILE_PATH_UNIT" 2>/dev/null || true
systemctl disable --now "$RECONCILE_SERVICE_UNIT" 2>/dev/null || true
# Remove generated self-service squid service units.
systemctl disable --now polysquid-self_service.service 2>/dev/null || true
systemctl disable --now polysquid-self_service-start.timer 2>/dev/null || true
systemctl disable --now polysquid-self_service-stop.timer 2>/dev/null || true

echo "Removing installed systemd units"
rm -f "$SYSTEMD_DIR/$APP_UNIT"
rm -f "$SYSTEMD_DIR/$NGINX_UNIT"
rm -f "$SYSTEMD_DIR/$RECONCILE_SERVICE_UNIT"
rm -f "$SYSTEMD_DIR/$RECONCILE_PATH_UNIT"
rm -f "$SYSTEMD_DIR/polysquid-self_service.service"
rm -f "$SYSTEMD_DIR/polysquid-self_service-start.timer"
rm -f "$SYSTEMD_DIR/polysquid-self_service-stop.timer"
rm -f "$SYSTEMD_DIR/polysquid-self_service-stop.service"
rm -f /etc/logrotate.d/polysquid-self_service

echo "Removing self-service containers"
if command -v docker >/dev/null 2>&1; then
    docker rm -f "$APP_CONTAINER" "$NGINX_CONTAINER" polysquid_self_service >/dev/null 2>&1 || true
fi

if [[ "$PURGE" == true ]]; then
    echo "Purge enabled: removing Docker image and requests directory"
    if command -v docker >/dev/null 2>&1; then
        docker rmi "$IMAGE_NAME" >/dev/null 2>&1 || true
    fi
    rm -rf "$REQUESTS_DIR"
fi

echo "Reloading systemd"
systemctl daemon-reload

echo "Self-service portal uninstalled"
if [[ "$PURGE" == false ]]; then
    echo "Requests directory preserved at: $REQUESTS_DIR"
    echo "Run '$0 --purge' to also remove requests data and the Docker image"
fi