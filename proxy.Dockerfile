FROM debian:12-slim

# OpenSSL-backed Squid build to avoid GnuTLS chain presentation issues on TLS proxy listeners.
RUN apt-get update \
 && apt-get install -y --no-install-recommends squid-openssl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Create a readable entrypoint script.
# It initializes cache directories and then starts Squid in the foreground.
RUN cat <<'EOF' > /entrypoint.sh
#!/bin/sh
set -e

# Initialize cache layout in non-daemon mode (safe and idempotent).
# Using -N avoids leaving a background parent process from cache init.
squid -N -z -f /etc/squid/squid.conf || true

# Clear any stale PID file before foreground start.
rm -f /run/squid.pid /var/run/squid.pid

# If invoked manually without arguments, start Squid with the default command.
if [ "$#" -eq 0 ]; then
	set -- squid -NYC -f /etc/squid/squid.conf
fi

exec "$@"
EOF

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["squid", "-NYC", "-f", "/etc/squid/squid.conf"]
