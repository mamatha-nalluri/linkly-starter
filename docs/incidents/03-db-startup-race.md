# Incident 03 — API starts before PostgreSQL is ready

**Symptom:** API exits during startup because application import calls `init_schema()` and PostgreSQL is not yet accepting connections.

**Reproduction:** Start API and database concurrently without waiting for readiness; save API logs and container states as `docs/evidence/incident-03.log`.

**Root cause:** Container start order does not guarantee database readiness. The starter API opens a database connection during module initialization.

**Fix:** `scripts/up.sh` waits for PostgreSQL's `pg_isready` health check before starting API, and waits for cache health as well.

**Evidence:** Pending a real reproduction on the target Docker host.
