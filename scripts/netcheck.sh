#!/usr/bin/env bash
set -Eeuo pipefail
IMAGE=busybox:1.36
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"
failures=0
check() {
  local source="$1" target="$2" host="$3" port="$4" expected="$5" actual
  if docker run --rm --network "container:$source" "$IMAGE" sh -c "nc -zw3 '$host' '$port' >/dev/null 2>&1"; then actual=Allowed; else actual=Blocked; fi
  printf '%-12s %-9s %-22s expected=%-8s actual=%-8s' "$source" "$target" "$host:$port" "$expected" "$actual"
  if [[ "$actual" == "$expected" ]]; then echo PASS; else echo FAIL; failures=$((failures+1)); fi
}
check linkly-proxy api linkly-api 5000 Allowed
check linkly-proxy db linkly-db 5432 Blocked
check linkly-proxy cache linkly-cache 6379 Blocked
check linkly-proxy internet 1.1.1.1 443 Allowed
check linkly-api db linkly-db 5432 Allowed
check linkly-api cache linkly-cache 6379 Allowed
check linkly-api internet 1.1.1.1 443 Allowed
check linkly-worker api linkly-api 5000 Allowed
check linkly-worker db linkly-db 5432 Allowed
check linkly-worker cache linkly-cache 6379 Allowed
check linkly-worker internet 1.1.1.1 443 Blocked
check linkly-cache api linkly-api 5000 Allowed
check linkly-cache db linkly-db 5432 Allowed
check linkly-cache internet 1.1.1.1 443 Blocked
check linkly-db api linkly-api 5000 Allowed
check linkly-db cache linkly-cache 6379 Allowed
check linkly-db internet 1.1.1.1 443 Blocked
docker run -d --rm --name linkly-backup-netcheck --network admin "$IMAGE" sleep 60 >/dev/null
check linkly-backup-netcheck db linkly-db 5432 Allowed
check linkly-backup-netcheck api linkly-api 5000 Blocked
check linkly-backup-netcheck cache linkly-cache 6379 Blocked
check linkly-backup-netcheck internet 1.1.1.1 443 Blocked
docker rm -f linkly-backup-netcheck >/dev/null 2>&1 || true
echo "Reachability mismatches: $failures"
[[ "$failures" -eq 0 ]]
