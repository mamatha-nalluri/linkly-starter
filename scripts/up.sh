#!/usr/bin/env bash
# Build and start the required segmented stack with plain Docker CLI.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PASSWORD_FILE="${DB_PASSWORD_FILE:-$ROOT/secrets/db_password}"
GIT_SHA="${GIT_SHA:-$(git rev-parse --short=7 HEAD 2>/dev/null || echo dev)}"
: "${DOCKERHUB_USER:=}"
: "${PUSH_IMAGES:=false}"
command -v docker >/dev/null || { echo "Docker CLI is required" >&2; exit 1; }
[[ -s "$PASSWORD_FILE" ]] || { echo "Create secrets/db_password first (see README)" >&2; exit 1; }
[[ -s proxy/certs/tls.crt && -s proxy/certs/tls.key ]] || ./proxy/gen-cert.sh
chmod 600 "$PASSWORD_FILE"

docker build -t "linkly-api:$GIT_SHA" ./api
docker build -t "linkly-worker:$GIT_SHA" ./worker
docker build -t "linkly-proxy:$GIT_SHA" ./proxy
if [[ "$PUSH_IMAGES" == true ]]; then
  [[ -n "$DOCKERHUB_USER" ]] || { echo "Set DOCKERHUB_USER to push images" >&2; exit 1; }
  docker tag "linkly-api:$GIT_SHA" "$DOCKERHUB_USER/linkly-api:$GIT_SHA"
  docker tag "linkly-worker:$GIT_SHA" "$DOCKERHUB_USER/linkly-worker:$GIT_SHA"
  docker push "$DOCKERHUB_USER/linkly-api:$GIT_SHA"
  docker push "$DOCKERHUB_USER/linkly-worker:$GIT_SHA"
fi

# Idempotent container/network recreation; named volumes are preserved.
for name in linkly-proxy linkly-worker linkly-api linkly-cache linkly-db; do docker rm -f "$name" >/dev/null 2>&1 || true; done
for net in dmz internal admin; do docker network rm "$net" >/dev/null 2>&1 || true; done
docker network create --driver bridge --subnet 172.30.1.0/24 dmz
docker network create --driver bridge --internal --subnet 172.30.2.0/24 internal
docker network create --driver bridge --internal --subnet 172.30.3.0/24 admin
docker volume create pgdata >/dev/null
docker volume create redisdata >/dev/null
docker volume create reports >/dev/null

# Initialize persistent volume ownership with a short-lived helper.
docker run --rm --user 0 --cap-drop ALL --cap-add CHOWN --security-opt no-new-privileges -v pgdata:/v busybox:1.36 chown 70:70 /v
docker run --rm --user 0 --cap-drop ALL --cap-add CHOWN --security-opt no-new-privileges -v redisdata:/v busybox:1.36 chown 999:999 /v
docker run --rm --user 0 --cap-drop ALL --cap-add CHOWN --security-opt no-new-privileges -v reports:/v busybox:1.36 chown 10001:10001 /v

docker run -d --name linkly-db --network internal --network-alias db --user 70:70 --restart unless-stopped \
  --cap-drop ALL --security-opt no-new-privileges --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m --tmpfs /var/run/postgresql:rw,noexec,nosuid,size=16m \
  --memory 512m --cpus 1.0 -v pgdata:/var/lib/postgresql/data \
  --mount type=bind,src="$PASSWORD_FILE",dst=/run/secrets/db_password,readonly \
  -e POSTGRES_DB=linkly -e POSTGRES_USER=linkly -e POSTGRES_PASSWORD_FILE=/run/secrets/db_password \
  --health-cmd 'pg_isready -U linkly -d linkly' --health-interval 5s --health-timeout 3s --health-retries 12 \
  postgres:16-alpine
docker network connect admin linkly-db

docker run -d --name linkly-cache --network internal --user 999:999 --restart unless-stopped \
  --cap-drop ALL --security-opt no-new-privileges --read-only --tmpfs /tmp:rw,noexec,nosuid,size=16m \
  --memory 128m --cpus 0.5 -v redisdata:/data \
  --health-cmd 'redis-cli ping' --health-interval 5s --health-timeout 3s --health-retries 12 \
  redis:7.4-alpine redis-server --appendonly yes --dir /data

wait_healthy() {
  local name="$1" status
  for _ in $(seq 1 60); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || true)"
    [[ "$status" == healthy ]] && { echo "$name is healthy"; return 0; }
    [[ "$status" == unhealthy || "$status" == exited ]] && { docker logs "$name"; return 1; }
    sleep 2
  done
  echo "Timed out waiting for $name" >&2; docker logs "$name" || true; return 1
}
wait_healthy linkly-db
wait_healthy linkly-cache

docker run -d --name linkly-api --network dmz --user 10001:10001 --restart unless-stopped \
  --cap-drop ALL --security-opt no-new-privileges --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --memory 256m --cpus 1.0 --mount type=bind,src="$PASSWORD_FILE",dst=/run/secrets/db_password,readonly \
  -e DB_HOST=linkly-db -e DB_NAME=linkly -e DB_USER=linkly -e DB_PASSWORD_FILE=/run/secrets/db_password \
  -e REDIS_HOST=linkly-cache -e LOG_FILE=- -e LOG_FORMAT=json \
  --health-cmd 'python healthcheck.py' --health-interval 10s --health-timeout 5s --health-retries 5 \
  "linkly-api:$GIT_SHA"
docker network connect internal linkly-api
wait_healthy linkly-api

# Worker must remain internal-only; disable external webhook to honor the blocked-egress matrix.
docker run -d --name linkly-worker --network internal --user 10001:10001 --restart unless-stopped \
  --cap-drop ALL --security-opt no-new-privileges --read-only --tmpfs /tmp:rw,noexec,nosuid,size=32m \
  --memory 256m --cpus 0.75 --mount type=bind,src="$PASSWORD_FILE",dst=/run/secrets/db_password,readonly \
  -v reports:/app/reports -e DB_HOST=linkly-db -e DB_NAME=linkly -e DB_USER=linkly \
  -e DB_PASSWORD_FILE=/run/secrets/db_password -e REDIS_HOST=linkly-cache \
  -e REPORT_DIR=/app/reports -e REPORT_INTERVAL=86400 -e WEBHOOK_URL= -e HEARTBEAT_FILE=/tmp/worker-heartbeat \
  --health-cmd 'python healthcheck.py' --health-interval 10s --health-timeout 3s --health-retries 3 \
  "linkly-worker:$GIT_SHA"
wait_healthy linkly-worker

# nginx unprivileged user 101 needs read access to the mounted development private key.
chmod 644 proxy/certs/tls.key
docker run -d --name linkly-proxy --network dmz --user 101:101 --restart unless-stopped \
  --cap-drop ALL --security-opt no-new-privileges --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=32m --tmpfs /var/cache/nginx:rw,noexec,nosuid,size=32m --tmpfs /var/run:rw,noexec,nosuid,size=8m \
  --memory 128m --cpus 0.5 -p 80:8080 -p 443:8443 \
  --mount type=bind,src="$ROOT/proxy/certs/tls.crt",dst=/etc/nginx/certs/tls.crt,readonly \
  --mount type=bind,src="$ROOT/proxy/certs/tls.key",dst=/etc/nginx/certs/tls.key,readonly \
  --health-cmd 'wget -q -O /dev/null http://127.0.0.1:8080/healthz' --health-interval 10s --health-timeout 3s --health-retries 3 \
  "linkly-proxy:$GIT_SHA"
wait_healthy linkly-proxy
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo "Stack started. Run scripts/netcheck.sh and capture real evidence."
