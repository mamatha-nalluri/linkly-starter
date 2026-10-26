# Linkly — Docker Capstone

Linkly is a URL shortener with click analytics. This project containerizes the existing application using Docker and Docker Compose, separates services across Docker networks, manages the database password using a file-based secret, and adds health checks and persistent storage.

The application features remain unchanged.

## Architecture

The application consists of five services:

| Service | Responsibility |
|---|---|
| `proxy` | Nginx reverse proxy; HTTP and HTTPS entry points |
| `api` | Flask API served by Gunicorn |
| `worker` | Processes click events, writes CSV reports, and posts webhook summaries |
| `postgres` | Stores links and click records |
| `redis` | Queues click events for background processing |

### Request flow

1. A client sends a request to Nginx.
2. Nginx forwards HTTPS requests to the API.
3. The API creates short links and records click events.
4. Redis queues click events for asynchronous processing.
5. The worker reads events from Redis and stores them in PostgreSQL.
6. The worker periodically generates CSV reports and sends webhook summaries.

### Docker networking

- `frontend`: connects the proxy to the API.
- `backend`: connects the API, PostgreSQL, Redis, and worker.
- PostgreSQL and Redis are not published directly to the host.

### Persistent storage

- `postgres_data`: PostgreSQL database data.
- `worker_reports`: generated CSV reports.

## Prerequisites

Install Docker Desktop and ensure Docker Compose is available.

Verify the installation:

```bash
docker --version
docker compose version
docker info
```

## Project structure

```text
linkly-starter/
├── api/
│   ├── Dockerfile
│   ├── app.py
│   ├── healthcheck.py
│   └── requirements.txt
├── worker/
│   ├── Dockerfile
│   ├── worker.py
│   ├── healthcheck.py
│   └── requirements.txt
├── proxy/
│   ├── Dockerfile
│   ├── default.conf
│   ├── gen-cert.sh
│   └── certs/
├── secrets/
│   └── db_password
├── compose.yaml
└── README.md
```

Generated certificates and database secrets are local development files and must not be committed to Git.

## Configuration and setup

Run these commands from the repository root.

### 1. Generate the local TLS certificate

```bash
chmod +x proxy/gen-cert.sh
./proxy/gen-cert.sh
```

The script creates the certificate and private key under `proxy/certs/`.

The certificate is self-signed and intended for local development only.

### 2. Generate a database password

```bash
mkdir -p secrets
umask 077
openssl rand -hex 24 > secrets/db_password
chmod 600 secrets/db_password
```

Do not commit or share this password.

### 3. Validate the Compose configuration

```bash
docker compose config --quiet
docker compose config --services
```

### 4. Build and start the application

```bash
docker compose up --build -d
```

### 5. Verify container health

```bash
docker compose ps
```

Wait until the services with health checks report `healthy`.

## Local testing

The HTTPS listener is published on port `8443`, and the HTTP listener is published on port `8080`.

The following commands use `curl -k` because the local TLS certificate is self-signed. Do not use this option as a substitute for certificate validation in production.

### 1. Check the proxy

```bash
curl -i http://localhost:8080/healthz
```

Expected result: HTTP `200 OK`.

### 2. Check API health

```bash
curl -k -i https://localhost:8443/health
```

Expected result: HTTP `200 OK`, with PostgreSQL and Redis reporting healthy connections.

### 3. Create a short link

```bash
curl -k -i -X POST https://localhost:8443/links \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com"}'
```

Example response:

```json
{
  "code": "K8Q1X0",
  "url": "https://example.com"
}
```

The generated code will vary.

### 4. Test the redirect

Replace `CODE` with the code returned by the API.

```bash
curl -k -i https://localhost:8443/CODE
```

Expected result: HTTP `302 FOUND`, with a `Location` header pointing to the original URL.

### 5. Check click statistics

```bash
curl -k -i https://localhost:8443/stats/CODE
```

The response contains the short code and its click count.

### 6. Simulate multiple visits

```bash
for i in 1 2 3; do
  curl -k -s -o /dev/null \
    -w "Visitor $i: HTTP %{http_code}\n" \
    https://localhost:8443/CODE
done
```

Query the statistics endpoint again to check whether the clicks were recorded.

### 7. Inspect worker processing

```bash
docker compose logs --tail=50 worker
```

Look for messages indicating that click events were stored.

## Operations and troubleshooting

### View logs

```bash
docker compose logs --tail=100
docker compose logs -f api
docker compose logs -f worker
docker compose logs -f proxy
```

Press `Ctrl+C` to stop following logs.

### Restart services

```bash
docker compose restart api worker
docker compose ps
```

### Rebuild after configuration or Dockerfile changes

```bash
docker compose up --build -d
```

### Stop the stack

```bash
docker compose down
```

The named database and report volumes are retained when the stack is stopped this way.

**Warning:** `docker compose down -v` removes Compose-managed volumes and can delete stored database data and reports.

## Security considerations

- The database password is provided using a file-based secret.
- The `secrets/` and `proxy/certs/` directories must remain excluded from Git.
- The proxy is the only service publishing application ports to the host.
- PostgreSQL and Redis are accessible through internal Docker networks rather than published host ports.
- The local TLS certificate is self-signed and must be replaced with a trusted certificate for a public deployment.
- Before public deployment, configure a domain, production TLS, suitable firewall rules, secure secret management, and appropriate resource limits.

## Scope and limitations

This repository is a local Docker capstone environment. It is not automatically a public URL-shortening service.

The current local short URLs are accessible from the host running Docker. Making links accessible to other users requires a suitable deployment and public domain.

The original application endpoints and behavior are unchanged.
