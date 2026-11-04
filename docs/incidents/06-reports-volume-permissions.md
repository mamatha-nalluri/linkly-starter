# Incident 06 — Worker cannot write to a fresh reports volume

**Symptom:** Worker UID 10001 receives permission denied while creating its first CSV report in a new named volume.

**Reproduction:** Mount a fresh named volume at `/app/reports` and run the worker as UID 10001 without ownership initialization. Capture the error as `docs/evidence/incident-06.log`.

**Root cause:** A newly created Docker named volume is initially root-owned, but the worker intentionally runs as a non-root user.

**Fix:** Startup runs a short-lived BusyBox helper with only CHOWN capability to set the reports volume owner to 10001:10001 before launching the worker. The worker itself drops all capabilities.

**Evidence:** Pending a real reproduction on the target Docker host.
