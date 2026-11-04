# Real-run evidence capture

This directory must contain output produced on the actual Docker host. No logs or screenshots are fabricated or pre-filled.

From the repository root, save real command output, for example:

```bash
bash scripts/up.sh 2>&1 | tee docs/evidence/up.log
bash scripts/netcheck.sh 2>&1 | tee docs/evidence/netcheck.log
docker network inspect dmz internal admin > docs/evidence/networks.json
docker ps --format '{{.Names}} {{.Ports}}' > docs/evidence/ports.txt
docker inspect linkly-api linkly-worker linkly-proxy linkly-db linkly-cache > docs/evidence/container-inspect.json
docker top linkly-api -o user,pid,cmd > docs/evidence/api-process.txt
docker top linkly-worker -o user,pid,cmd > docs/evidence/worker-process.txt
bash scripts/backup.sh 2>&1 | tee docs/evidence/backup.log
```

Also capture app create/redirect/stats responses, image sizes, Trivy output, and persistence before/after down/up. Review for secrets before committing. Never commit the password file or private TLS key.
