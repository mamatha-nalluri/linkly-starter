"""Linkly API: create short links, redirect, and count clicks."""
import logging
import os
import secrets
import string
import sys
import time

import psycopg
import redis
from flask import Flask, jsonify, redirect, request

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_NAME = os.environ.get("DB_NAME", "linkly")
DB_USER = os.environ.get("DB_USER", "linkly")
REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
LOG_FILE = os.environ.get("LOG_FILE", "logs/api.log")  # "-" means stdout
LOG_FORMAT = os.environ.get("LOG_FORMAT", "text")  # "text" or "json"


def read_password():
    """Read the DB password from DB_PASSWORD_FILE if set, else from DB_PASSWORD."""
    path = os.environ.get("DB_PASSWORD_FILE")
    if path:
        with open(path) as f:
            return f.read().strip()
    return os.environ.get("DB_PASSWORD", "")


DB_PASSWORD = read_password()

if LOG_FORMAT == "json":
    fmt = '{"time": "%(asctime)s", "level": "%(levelname)s", "msg": "%(message)s"}'
else:
    fmt = "%(asctime)s %(levelname)s %(message)s"
if LOG_FILE == "-":
    logging.basicConfig(stream=sys.stdout, level=logging.INFO, format=fmt)
else:
    os.makedirs(os.path.dirname(LOG_FILE) or ".", exist_ok=True)
    logging.basicConfig(filename=LOG_FILE, level=logging.INFO, format=fmt)
log = logging.getLogger("api")

app = Flask(__name__)
cache = redis.Redis(host=REDIS_HOST, port=6379, socket_timeout=2, decode_responses=True)


def db():
    return psycopg.connect(
        host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD, connect_timeout=3
    )


def init_schema():
    with db() as conn:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS links ("
            " code TEXT PRIMARY KEY,"
            " url TEXT NOT NULL,"
            " created_at TIMESTAMPTZ NOT NULL DEFAULT now())"
        )
        conn.execute(
            "CREATE TABLE IF NOT EXISTS clicks ("
            " id BIGSERIAL PRIMARY KEY,"
            " code TEXT NOT NULL,"
            " clicked_at TIMESTAMPTZ NOT NULL)"
        )


def new_code(length=6):
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


@app.post("/links")
def create_link():
    url = (request.get_json(silent=True) or {}).get("url", "")
    if not url.startswith(("http://", "https://")):
        return jsonify(error="url must start with http:// or https://"), 400
    code = new_code()
    with db() as conn:
        conn.execute("INSERT INTO links (code, url) VALUES (%s, %s)", (code, url))
    cache.set(f"link:{code}", url, ex=3600)
    log.info("created code=%s url=%s", code, url)
    return jsonify(code=code, url=url), 201


@app.get("/<code>")
def follow(code):
    url = cache.get(f"link:{code}")
    if url is None:
        with db() as conn:
            row = conn.execute("SELECT url FROM links WHERE code = %s", (code,)).fetchone()
        if row is None:
            return jsonify(error="not found"), 404
        url = row[0]
        cache.set(f"link:{code}", url, ex=3600)
    cache.rpush("clicks", f"{code}|{int(time.time())}")
    log.info("click code=%s", code)
    return redirect(url, code=302)


@app.get("/stats/<code>")
def stats(code):
    with db() as conn:
        row = conn.execute("SELECT count(*) FROM clicks WHERE code = %s", (code,)).fetchone()
    return jsonify(code=code, clicks=row[0])


@app.get("/slow")
def slow():
    seconds = min(int(request.args.get("seconds", 5)), 30)
    time.sleep(seconds)
    return jsonify(slept=seconds)


@app.get("/health")
def health():
    status = {}
    try:
        with db() as conn:
            conn.execute("SELECT 1")
        status["db"] = "ok"
    except Exception as exc:
        status["db"] = f"error: {exc.__class__.__name__}"
    try:
        cache.ping()
        status["cache"] = "ok"
    except Exception as exc:
        status["cache"] = f"error: {exc.__class__.__name__}"
    healthy = all(v == "ok" for v in status.values())
    return jsonify(status=status), (200 if healthy else 503)


init_schema()
