# Linkly: starter app for the Docker capstone

Linkly is a URL shortener with click analytics. This repository contains the application only.
Your job is to containerize it, segment it across Docker networks, harden it and ship it.
Do not change the application's features. Change only how it is configured and run.

## Components

| Path | What it is |
| --- | --- |
| `api/app.py` | Flask API, served by Gunicorn |
| `api/healthcheck.py` | Exits 0 if `GET /health` returns 200 (standard library only) |
| `worker/worker.py` | Moves clicks from Redis to Postgres, writes a CSV report, posts a summary to a webhook |
| `worker/healthcheck.py` | Exits 0 if the worker's heartbeat file is newer than 30 seconds |
| `proxy/default.conf` | nginx config: HTTP on 8080 redirects to HTTPS on 8443 (except `/healthz`), forwards to `api:5000` |
| `proxy/gen-cert.sh` | Creates a self-signed certificate in `proxy/certs/` |

## API endpoints

| Method and path | Purpose |
| --- | --- |
| `POST /links` with `{"url": "https://..."}` | Create a short link, returns `{"code": ...}` |
| `GET /<code>` | Redirect to the original URL and record a click |
| `GET /stats/<code>` | Number of clicks stored for a code |
| `GET /slow?seconds=N` | Sleeps N seconds (max 30), for testing graceful shutdown |
| `GET /health` | 200 if Postgres and Redis are reachable, else 503 |

## Configuration (environment variables)

| Variable | Used by | Default | Meaning |
| --- | --- | --- | --- |
| `DB_HOST` | api, worker | `localhost` | Postgres host |
| `DB_NAME` | api, worker | `linkly` | Database name |
| `DB_USER` | api, worker | `linkly` | Database user |
| `DB_PASSWORD` | api, worker | empty | Database password |
| `DB_PASSWORD_FILE` | api, worker | unset | Path to a file holding the password; overrides `DB_PASSWORD` |
| `REDIS_HOST` | api, worker | `localhost` | Redis host (port 6379) |
| `LOG_FILE` | api | `logs/api.log` | Log file path; `-` writes to stdout |
| `LOG_FORMAT` | api | `text` | `text` or `json` |
| `REPORT_DIR` | worker | `reports` | Folder for CSV reports |
| `REPORT_INTERVAL` | worker | `86400` | Seconds between reports; the first report is written at start |
| `WEBHOOK_URL` | worker | `https://httpbin.org/post` | Where the report summary is posted; empty disables it |
| `HEARTBEAT_FILE` | worker | `/tmp/worker-heartbeat` | Heartbeat file read by `worker/healthcheck.py` |

The api creates its tables on start, so Postgres must be reachable before the api starts.

## How the developer ran it on a laptop

```
pip install -r api/requirements.txt -r worker/requirements.txt
cd api && DB_PASSWORD=devpass gunicorn app:app
cd worker && DB_PASSWORD=devpass python worker.py
```

## Quick test once the stack is up

```
curl -sk -X POST https://localhost/links -H 'Content-Type: application/json' -d '{"url":"https://example.com"}'
curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/<code>
curl -sk https://localhost/stats/<code>
```
# linkly-starter tarunasthana@IN-FVFGK2EPQ05N
