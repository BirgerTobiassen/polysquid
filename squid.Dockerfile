FROM debian:12-slim

# OpenSSL-backed Squid build to avoid GnuTLS chain presentation issues on TLS proxy listeners.
RUN apt-get update \
 && apt-get install -y --no-install-recommends squid-openssl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Ensure cache directory structure exists on first boot (idempotent).
RUN printf '#!/bin/sh\nset -e\nsquid -z -f /etc/squid/squid.conf || true\nexec "$@"\n' > /entrypoint.sh \
 && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["squid", "-NYC", "-f", "/etc/squid/squid.conf"]
