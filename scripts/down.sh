#!/usr/bin/env bash
set -Eeuo pipefail
for name in linkly-proxy linkly-worker linkly-api linkly-cache linkly-db; do docker rm -f "$name" >/dev/null 2>&1 || true; done
for net in dmz internal admin; do docker network rm "$net" >/dev/null 2>&1 || true; done
echo "Removed containers and networks; retained pgdata, redisdata and reports volumes."
