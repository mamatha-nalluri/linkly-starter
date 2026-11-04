#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PASSWORD_FILE="${DB_PASSWORD_FILE:-$ROOT/secrets/db_password}"
[[ -s "$PASSWORD_FILE" ]] || { echo "Missing database password file: $PASSWORD_FILE" >&2; exit 1; }
mkdir -p backups && chmod 700 backups
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$ROOT/backups/linkly-$stamp.sql.gz"
docker run --rm --network admin --cap-drop ALL --security-opt no-new-privileges --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=32m --tmpfs /run/secrets:rw,noexec,nosuid,size=1m --memory 256m --cpus 0.5 \
  --user "$(id -u):$(id -g)" --mount type=bind,src="$PASSWORD_FILE",dst=/run/secrets/db_password,readonly \
  --mount type=bind,src="$ROOT/backups",dst=/backups \
  --entrypoint sh postgres:16-alpine -ec \
  'export PGPASSWORD="$(cat /run/secrets/db_password)"; pg_dump -h linkly-db -U linkly -d linkly --no-owner --no-privileges | gzip > "/backups/'"linkly-$stamp"'.sql.gz"'
test -s "$out" && chmod 600 "$out"
echo "Backup created: $out"
