# Linkly — Segmented Production Docker Stack

This capstone containerizes the provided Linkly URL shortener and click analytics service. The original application code remains unchanged. Runtime behavior is configured through Dockerfiles, environment variables, mounts and Docker CLI flags.

**The capstone uses plain Docker CLI, not Docker Compose.**

## Architecture

Six services, three networks and three named volumes:

```text
Internet
   |
Host ports 80 / 443
   |
[proxy: nginx unprivileged] -- dmz -- [api: Flask/Gunicorn]
                                         |
                                      internal
                           +-------------+-------------+
                           |             |             |
                        [worker]       [cache]         [db]
                                     Redis AOF      PostgreSQL
                                                        |
                                                      admin
                                                        |
                                                  [backup job]
```

| Service | Image | Networks | Published ports | Storage |
|---|---|---|---|---|
| proxy | nginxinc/nginx-unprivileged:1.27-alpine | dmz | 80:8080, 443:8443 | none |
| api | built from python:3.12-slim-bookworm | dmz, internal | none | none |
| worker | built from python:3.12-slim-bookworm | internal | none | reports |
| cache | redis:7.4-alpine | internal | none | redisdata |
| db | postgres:16-alpine | internal, admin | none | pgdata |
| backup job | postgres:16-alpine (one-shot) | admin | none | ./backups bind mount |

Only API is dual-homed across dmz and internal. The database is dual-homed across internal and admin. Both internal and admin are created with Docker's `--internal` option.

### Why is API reachable from internal?

The API needs PostgreSQL and Redis on internal and receives proxy traffic on dmz. Because worker, cache and database share internal with API, they can also reach the API's listening port. This is the explicit connectivity trade-off of the required topology. A stricter production design would add host firewall policy or a more restrictive service boundary.

## Required reachability matrix

`scripts/netcheck.sh` tests live container network namespaces, prints expected versus actual and exits non-zero on a mismatch.

| From / To | api:5000 | db:5432 | cache:6379 | Internet 1.1.1.1:443 |
|---|---|---|---|---|
| proxy | Allowed | Blocked | Blocked | Allowed |
| api | — | Allowed | Allowed | Allowed |
| worker | Allowed | Allowed | Allowed | Blocked |
| cache | Allowed | Allowed | — | Blocked |
| db | Allowed | — | Allowed | Blocked |
| backup job | Blocked | Allowed | Blocked | Blocked |

## Exact image tags

- `python:3.12-slim-bookworm`
- `nginxinc/nginx-unprivileged:1.27-alpine`
- `postgres:16-alpine`
- `redis:7.4-alpine`
- `busybox:1.36`
- `aquasec/trivy:0.56.2`

Never use `:latest`.

## Prerequisites and setup

Use a Linux Docker host/VM with Docker Engine, Bash, Git and OpenSSL. The stack binds host ports 80 and 443; ensure they are available.

```bash
chmod +x scripts/*.sh proxy/gen-cert.sh
mkdir -p secrets
umask 077
openssl rand -hex 24 > secrets/db_password
chmod 600 secrets/db_password
./proxy/gen-cert.sh
bash scripts/up.sh
```

The password and self-signed TLS key are local-only. `secrets/`, `proxy/certs/`, and generated backups are gitignored. Never commit them.

The startup script builds all three project images, creates the exact networks and volumes, initializes named-volume ownership, starts services in dependency order, waits for health and publishes only proxy ports. API and worker images are tagged with the short Git SHA. To push these two images to Docker Hub:

```bash
docker login
DOCKERHUB_USER=YOUR_DOCKERHUB_USERNAME PUSH_IMAGES=true bash scripts/up.sh
```

Replace the placeholder with your Docker Hub username. The script pushes `linkly-api:<short-sha>` and `linkly-worker:<short-sha>` to your public Docker Hub repositories. Add the real image URLs after a successful push.

## Test the application

```bash
curl -i http://localhost/healthz
curl -k -i https://localhost/health
curl -k -i -X POST https://localhost/links \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com"}'
```

Use the returned code in:

```bash
curl -k -i https://localhost/CODE
curl -k -i https://localhost/stats/CODE
```

Expected: health returns 200, link creation 201, redirect 302, and stats reports the asynchronously persisted click count. The local TLS certificate is self-signed; `curl -k` is for local testing only.

## Network proof

```bash
bash scripts/netcheck.sh
```

It uses disposable `busybox:1.36` sidecars sharing each service's network namespace. A throwaway backup-role sidecar tests admin-only access. The script must exit 0 for a pass.

## Backup and persistence

```bash
bash scripts/backup.sh
ls -lh backups/
gzip -t backups/linkly-*.sql.gz
zcat backups/linkly-TIMESTAMP.sql.gz | grep 'YOUR_SHORT_CODE'
```

The backup job uses a temporary PostgreSQL client on admin only and writes a timestamped compressed SQL dump. To test persistence, record a known code, run `bash scripts/down.sh`, then `bash scripts/up.sh` and query its stats again. The down script removes containers and networks but retains `pgdata`, `redisdata` and `reports`.

## Security controls

- API and worker use fixed UID/GID 10001; proxy uses unprivileged UID 101; database and cache use their image service users.
- Containers drop all capabilities, enable `no-new-privileges`, use read-only root filesystems and bounded tmpfs mounts.
- CPU and memory limits are configured for long-running services and one-shot jobs.
- Database password is mounted read-only at `/run/secrets/db_password` and passed through `DB_PASSWORD_FILE` / `POSTGRES_PASSWORD_FILE`; it is not embedded in image layers or container environment values.
- Every long-running service has a health check; startup waits for dependencies.
- No privileged containers, host networking or Docker socket mounts.
- Redis AOF and PostgreSQL data use named volumes.

### Webhook egress trade-off

The starter worker defaults to an external webhook endpoint. The required topology explicitly blocks worker Internet access. To keep worker internal-only and avoid crashing on its first report, startup sets `WEBHOOK_URL=`. CSV report generation and click processing remain enabled, but external webhook delivery is disabled. See incident 04. This does not claim webhook delivery succeeds.

## Vulnerability scan

After pushing the images, scan both pushed tags:

```bash
docker run --rm aquasec/trivy:0.56.2 image --severity CRITICAL --ignore-unfixed --exit-code 1 YOUR_DOCKERHUB_USERNAME/linkly-api:SHORT_SHA
docker run --rm aquasec/trivy:0.56.2 image --severity CRITICAL --ignore-unfixed --exit-code 1 YOUR_DOCKERHUB_USERNAME/linkly-worker:SHORT_SHA
```

Acceptance target: zero fixable CRITICAL vulnerabilities. Record actual output; do not claim a pass until both commands exit 0.

## Incidents and evidence

Six incident analyses are in `docs/incidents/`: missing shared network/DNS, proxy 502, database readiness race, worker webhook egress, API read-only filesystem logging, and reports-volume ownership. Each write-up describes symptom, reproduction, root cause and fix.

The evidence directory contains capture instructions. The capstone requires genuine output from a real Docker host; no fabricated evidence is committed. Capture at minimum:

- Fresh clone to all healthy services in 10 minutes or less.
- `netcheck.sh` exit 0 and matching matrix.
- Network membership and published-port inspection.
- Link creation, redirect and stats output.
- API image size at most 200 MB.
- Non-root API/worker process output.
- Container security inspection and proof secret is absent from Config.Env.
- Trivy scans with zero fixable CRITICAL findings.
- Link count before/after down/up.
- SQL gzip backup containing a known link code.

## Repository layout

```text
.
├── .dockerignore
├── README.md
├── api/                 # original app + Dockerfile
├── worker/              # original worker + Dockerfile
├── proxy/               # unprivileged nginx config + TLS generator
├── scripts/             # up, down, backup and netcheck
└── docs/
    ├── incidents/       # six incident reports
    └── evidence/        # real command output
```
