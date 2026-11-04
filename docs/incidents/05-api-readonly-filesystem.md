# Incident 05 — API cannot write with a read-only root filesystem

**Symptom:** API fails on its first filesystem write when started read-only with the starter default log path.

**Reproduction:** Run API with `--read-only` and `LOG_FILE=logs/api.log`; capture the exception and logs as `docs/evidence/incident-05.log`.

**Root cause:** Application logging attempts to create/write a file under the read-only application filesystem.

**Fix:** Set `LOG_FILE=-` to send logs to stdout and mount a bounded writable `/tmp` tmpfs for Gunicorn temporary files.

**Evidence:** Pending a real reproduction on the target Docker host.
