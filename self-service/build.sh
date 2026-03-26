#!/bin/bash
# Build and deploy the self-service Flask app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBAPP_DIR="$SCRIPT_DIR/webapp"
IMAGE_NAME="polysquid-webapp:latest"
REQUESTS_DIR="$SCRIPT_DIR/requests"
CERTS_DIR="/etc/polysquid/certs"
SERVICE_FILE="$SCRIPT_DIR/polysquid-webapp.service"
NGINX_SERVICE_FILE="$SCRIPT_DIR/polysquid-nginx.service"
SYSTEMD_DIR="/etc/systemd/system"

usage() {
    cat <<EOF
Usage: $0 <command>

Commands:
  build               Build the Docker image
    deploy              Build and install app + HTTPS proxy services
    start               Start app and HTTPS proxy services
    stop                Stop app and HTTPS proxy services
    restart             Restart app and HTTPS proxy services
  status              Show service status
    logs                Show live logs for app and proxy
  clean               Remove container and image
  help                Show this help message

Examples:
  $0 build            # Build the image
    $0 deploy           # Build and deploy app + HTTPS proxy services
    $0 logs             # View app + proxy logs
EOF
}

build_image() {
    echo "🔨 Building Docker image: $IMAGE_NAME"
    docker build -t "$IMAGE_NAME" -f "$WEBAPP_DIR/webapp.Dockerfile" "$WEBAPP_DIR"
    echo "✅ Image built successfully"
}

create_requests_dir() {
    if [ ! -d "$REQUESTS_DIR" ]; then
        echo "📁 Creating requests directory: $REQUESTS_DIR"
        mkdir -p "$REQUESTS_DIR"
        chmod 755 "$REQUESTS_DIR"
    fi
}

create_certs_dir() {
    if [ ! -d "$CERTS_DIR" ]; then
        echo "⚠️  TLS cert directory missing: $CERTS_DIR"
        echo "   Run /opt/polysquid/install.sh first to create shared directories."
        return
    fi
    if [ ! -f "$CERTS_DIR/fullchain.pem" ] || [ ! -f "$CERTS_DIR/privkey.pem" ]; then
        echo "⚠️  Missing TLS certificates in $CERTS_DIR"
        echo "   Required files:"
        echo "   - $CERTS_DIR/fullchain.pem"
        echo "   - $CERTS_DIR/privkey.pem"
    fi
}

deploy_service() {
    echo "📋 Deploying systemd service..."
    
    if [ ! -f "$SERVICE_FILE" ] || [ ! -f "$NGINX_SERVICE_FILE" ]; then
        echo "❌ Service file missing. Required files:"
        echo "   - $SERVICE_FILE"
        echo "   - $NGINX_SERVICE_FILE"
        exit 1
    fi
    
    build_image
    create_requests_dir
    create_certs_dir
    
    echo "🚀 Copying service file to $SYSTEMD_DIR..."
    sudo cp "$SERVICE_FILE" "$SYSTEMD_DIR/polysquid-webapp.service"
    sudo cp "$NGINX_SERVICE_FILE" "$SYSTEMD_DIR/polysquid-nginx.service"
    
    echo "🔄 Reloading systemd..."
    sudo systemctl daemon-reload
    
    echo "✅ Service deployed successfully"
    echo ""
    echo "Next steps:"
    echo "  sudo systemctl enable polysquid-webapp.service"
    echo "  sudo systemctl enable polysquid-nginx.service"
    echo "  sudo systemctl start polysquid-webapp.service"
    echo "  sudo systemctl start polysquid-nginx.service"
    echo "  sudo systemctl status polysquid-webapp.service"
    echo "  sudo systemctl status polysquid-nginx.service"
}

start_service() {
    echo "🚀 Starting app + HTTPS proxy services..."
    sudo systemctl start polysquid-webapp.service
    sudo systemctl start polysquid-nginx.service
    echo "✅ Services started"
}

stop_service() {
    echo "⛔ Stopping app + HTTPS proxy services..."
    sudo systemctl stop polysquid-nginx.service
    sudo systemctl stop polysquid-webapp.service
    echo "✅ Services stopped"
}

restart_service() {
    echo "🔄 Restarting app + HTTPS proxy services..."
    sudo systemctl restart polysquid-webapp.service
    sudo systemctl restart polysquid-nginx.service
    echo "✅ Services restarted"
}

status_service() {
    echo "📊 App service status:"
    sudo systemctl status polysquid-webapp.service || true
    echo ""
    echo "📊 HTTPS proxy service status:"
    sudo systemctl status polysquid-nginx.service || true
    echo ""
    echo "📦 Docker containers:"
    docker ps -a | grep -i polysquid_webapp || echo "  (not running)"
}

show_logs() {
    echo "📋 App logs (last 100):"
    docker logs --tail 100 polysquid_webapp || echo "App container not running"
    echo ""
    echo "📋 HTTPS proxy logs (last 100):"
    docker logs --tail 100 polysquid_nginx || echo "Proxy container not running"
}

clean() {
    echo "🧹 Cleaning up..."
    
    if docker ps -a | grep -q polysquid_webapp; then
        echo "  Removing container..."
        docker rm -f polysquid_webapp
    fi

    if docker ps -a | grep -q polysquid_nginx; then
        echo "  Removing HTTPS proxy container..."
        docker rm -f polysquid_nginx
    fi
    
    if docker images | grep -q "polysquid-webapp"; then
        echo "  Removing image..."
        docker rmi "$IMAGE_NAME"
    fi
    
    echo "✅ Cleanup complete"
}

# Main
if [ $# -eq 0 ]; then
    usage
    exit 0
fi

case "$1" in
    build)
        build_image
        ;;
    deploy)
        deploy_service
        ;;
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    status)
        status_service
        ;;
    logs)
        show_logs
        ;;
    clean)
        clean
        ;;
    help)
        usage
        ;;
    *)
        echo "❌ Unknown command: $1"
        usage
        exit 1
        ;;
esac
