# Incident 04 — Worker webhook fails on an internal-only network

**Symptom:** The starter worker's first report attempts its default external webhook; an internal-only network cannot reach that Internet endpoint. The request exception can terminate the worker.

**Reproduction:** Run worker on `internal` with the default webhook and allow the first report interval to run. Save logs as `docs/evidence/incident-04.log`.

**Root cause:** The assignment requires worker to stay on `internal` and requires its Internet reachability to be blocked, while the starter default webhook is external.

**Fix and trade-off:** Startup sets `WEBHOOK_URL=`. Click processing and CSV reports remain enabled; external webhook delivery is disabled. Enabling it requires an approved internal webhook receiver or a separately approved egress architecture. Do not attach worker to dmz because that violates the required topology.

**Evidence:** Pending a real reproduction on the target Docker host.
