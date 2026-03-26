#!/bin/bash

# Install script for polysquid
# This script sets up a systemd service that periodically checks for updates to services.yaml
# and runs polysquid.py when changes are detected.

set -euo pipefail

# Configuration
REPO_DIR="/opt/polysquid"
REPO_URL="git@github.com:BirgerTobiassen/Polysquid.git"
SERVICE_NAME="polysquid-git-update"
TRUSTED_DIR="/usr/local/lib/polysquid"
TRUSTED_EXEC="${TRUSTED_DIR}/polysquid.py"
TRUSTED_UPDATE="${TRUSTED_DIR}/polysquid-git-update.sh"
CERTS_DIR="/etc/polysquid/certs"
TIMER_INTERVAL="*-*-* *:0/5:00"  # Every 5 minutes

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo $0)"
    exit 1
fi

# Clone or update the repository
if [ ! -d "$REPO_DIR/.git" ]; then
    echo "Cloning repository to $REPO_DIR..."
    git clone "$REPO_URL" "$REPO_DIR"
else
    echo "Repository already exists, pulling latest changes..."
    cd "$REPO_DIR"
    git pull
fi
chown -R root:root "$REPO_DIR"

# Install a trusted, root-owned executor outside the git working tree.
# This prevents code in future git pulls from being executed automatically.
mkdir -p "$TRUSTED_DIR"
install -o root -g root -m 0755 "$REPO_DIR/polysquid.py" "$TRUSTED_EXEC"
install -o root -g root -m 0755 "$REPO_DIR/polysquid-git-update.sh" "$TRUSTED_UPDATE"

# Create shared TLS cert location used by Squid TLS and self-service nginx.
mkdir -p "$CERTS_DIR"
chmod 755 /etc/polysquid "$CERTS_DIR" 2>/dev/null || true

# Create systemd service
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Polysquid Update Service
After=network-online.target

[Service]
Type=oneshot
ExecStart=$TRUSTED_UPDATE
User=root
EOF

# Create systemd timer
TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"
cat > "$TIMER_FILE" << EOF
[Unit]
Description=Run polysquid update $TIMER_INTERVAL

[Timer]
OnCalendar=$TIMER_INTERVAL
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload systemd and enable timer
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.timer"

# Create logrotate config for the update log
LOGROTATE_CONF="/etc/logrotate.d/polysquid-git-update"
cat > "$LOGROTATE_CONF" << EOF
/var/log/polysquid-git-update.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 644 root root
}
EOF

# Build Debian-based OpenSSL Squid image used by default for proxy containers.
echo "Building default Squid image: polysquid-proxy:debian-openssl"
docker build -t polysquid-proxy:debian-openssl -f "$REPO_DIR/proxy.Dockerfile" "$REPO_DIR"

# Perform an initial reconciliation so enabled services start immediately after install.
/usr/bin/python3 "$TRUSTED_EXEC" --config "$REPO_DIR/services.yaml" --base-dir "$REPO_DIR"

echo "Installation complete!"
echo "Trusted executor installed at: ${TRUSTED_EXEC}"
echo "Trusted updater installed at: ${TRUSTED_UPDATE}"
echo "Shared cert directory prepared at: ${CERTS_DIR}"
echo "Enabled services have been reconciled and started where applicable."
echo "The service will check for updates to services.yaml every 5 minutes."
echo "To check status: systemctl status ${SERVICE_NAME}.timer"
echo "To view logs: journalctl -u ${SERVICE_NAME}.service or tail /var/log/polysquid-git-update.log"