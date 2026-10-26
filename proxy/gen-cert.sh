#!/usr/bin/env bash
# Generate a self-signed TLS certificate for the proxy into proxy/certs/.
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p certs
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout certs/tls.key -out certs/tls.crt \
  -subj "/CN=localhost"
chmod 644 certs/tls.crt certs/tls.key
echo "Created proxy/certs/tls.crt and proxy/certs/tls.key"
