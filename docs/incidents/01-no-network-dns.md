# Incident 01 — API and database have no shared network

**Symptom:** API cannot resolve the database hostname when API and database are started without a shared user-defined network.

**Reproduction:** Start the two containers without `--network` and inspect API logs for name-resolution/connection errors. Save the actual output as `docs/evidence/incident-01.log`.

**Root cause:** Docker's user-defined bridge network provides container-name DNS discovery; isolated containers do not share that network namespace or service discovery.

**Fix:** Attach API and database to `internal`. API additionally joins `dmz`; database additionally joins `admin`. The supplied `scripts/up.sh` builds this topology.

**Evidence:** Pending execution on the target Docker host. Do not substitute invented output.
