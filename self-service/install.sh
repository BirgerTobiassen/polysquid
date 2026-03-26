#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WEBAPP_DIR="$SCRIPT_DIR/webapp"
IMAGE_NAME="polysquid-webapp:latest"
REQUESTS_DIR="$SCRIPT_DIR/requests"
APP_UID=10001
APP_GID=10001
CERTS_DIR="/etc/polysquid/certs"
SYSTEMD_DIR="/etc/systemd/system"
APP_UNIT_SRC="$SCRIPT_DIR/polysquid-webapp.service"
NGINX_UNIT_SRC="$SCRIPT_DIR/polysquid-nginx.service"
APP_UNIT_DST="$SYSTEMD_DIR/polysquid-webapp.service"
NGINX_UNIT_DST="$SYSTEMD_DIR/polysquid-nginx.service"
RECONCILE_SERVICE_NAME="polysquid-self-service-reconcile"
RECONCILE_PATH_NAME="polysquid-self-service-reconcile"
TRUSTED_EXEC="/usr/local/lib/polysquid/polysquid.py"

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root (sudo $0)"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required"
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemd is required"
    exit 1
fi

if [[ ! -f "$APP_UNIT_SRC" || ! -f "$NGINX_UNIT_SRC" ]]; then
    echo "Required service unit templates are missing from $SCRIPT_DIR"
    exit 1
fi

mkdir -p "$REQUESTS_DIR"
chown -R "$APP_UID:$APP_GID" "$REQUESTS_DIR"
chmod 775 "$REQUESTS_DIR"

if [[ ! -d "$CERTS_DIR" ]]; then
    echo "Missing TLS cert directory: $CERTS_DIR"
    echo "Run the main install first or create the directory and place fullchain.pem and privkey.pem there."
    exit 1
fi

if [[ ! -f "$CERTS_DIR/fullchain.pem" || ! -f "$CERTS_DIR/privkey.pem" ]]; then
    echo "Missing TLS certificate files in $CERTS_DIR"
    echo "Expected: fullchain.pem and privkey.pem"
    exit 1
fi

if [[ ! -x "$TRUSTED_EXEC" ]]; then
    echo "Missing trusted polysquid executor: $TRUSTED_EXEC"
    echo "Run the main install first to install trusted runtime components."
    exit 1
fi

echo "Creating Docker network for service communication"
docker network create polysquid-net >/dev/null 2>&1 || true

echo "Building Docker image: $IMAGE_NAME"
docker build -t "$IMAGE_NAME" -f "$WEBAPP_DIR/webapp.Dockerfile" "$WEBAPP_DIR"

echo "Installing systemd units for repo path: $REPO_DIR"
sed "s|/opt/polysquid|$REPO_DIR|g" "$APP_UNIT_SRC" > "$APP_UNIT_DST"
sed "s|/opt/polysquid|$REPO_DIR|g" "$NGINX_UNIT_SRC" > "$NGINX_UNIT_DST"

chmod 644 "$APP_UNIT_DST" "$NGINX_UNIT_DST"

RECONCILE_SERVICE_FILE="$SYSTEMD_DIR/${RECONCILE_SERVICE_NAME}.service"
cat > "$RECONCILE_SERVICE_FILE" << EOF
[Unit]
Description=Polysquid Reconcile on Self-Service Request Changes
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 $TRUSTED_EXEC --config $REPO_DIR/services.yaml --base-dir $REPO_DIR
User=root
EOF

RECONCILE_PATH_FILE="$SYSTEMD_DIR/${RECONCILE_PATH_NAME}.path"
cat > "$RECONCILE_PATH_FILE" << EOF
[Unit]
Description=Trigger Polysquid reconcile when self-service requests change

[Path]
PathChanged=$REQUESTS_DIR
PathModified=$REQUESTS_DIR
Unit=${RECONCILE_SERVICE_NAME}.service

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$RECONCILE_SERVICE_FILE" "$RECONCILE_PATH_FILE"

echo "Reloading systemd"
systemctl daemon-reload

echo "Enabling services"
systemctl enable polysquid-webapp.service
systemctl enable polysquid-nginx.service
systemctl enable --now "${RECONCILE_PATH_NAME}.path"

echo "Starting services"
systemctl restart polysquid-webapp.service
systemctl restart polysquid-nginx.service

echo "Reconciling self-service squid configuration"
/usr/bin/python3 "$TRUSTED_EXEC" --config "$REPO_DIR/services.yaml" --base-dir "$REPO_DIR"

echo "Self-service portal installed"
echo "App unit:    $APP_UNIT_DST"
echo "Proxy unit:  $NGINX_UNIT_DST"
echo "Requests dir: $REQUESTS_DIR"
echo "Reconcile path: $RECONCILE_PATH_FILE"
echo "Check status with: systemctl status polysquid-webapp.service polysquid-nginx.service"