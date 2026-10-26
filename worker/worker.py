"""Linkly worker: move clicks from Redis to Postgres and write a daily CSV report."""
import csv
import datetime
import os
import time

import psycopg
import redis
import requests

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_NAME = os.environ.get("DB_NAME", "linkly")
DB_USER = os.environ.get("DB_USER", "linkly")
REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REPORT_DIR = os.environ.get("REPORT_DIR", "reports")
REPORT_INTERVAL = int(os.environ.get("REPORT_INTERVAL", "86400"))
WEBHOOK_URL = os.environ.get("WEBHOOK_URL", "https://httpbin.org/post")

HEARTBEAT_FILE = os.environ.get("HEARTBEAT_FILE", "/tmp/worker-heartbeat")


def read_password():
    """Read the DB password from DB_PASSWORD_FILE if set, else from DB_PASSWORD."""
    path = os.environ.get("DB_PASSWORD_FILE")
    if path:
        with open(path) as f:
            return f.read().strip()
    return os.environ.get("DB_PASSWORD", "")


DB_PASSWORD = read_password()
cache = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)


def db():
    return psycopg.connect(
        host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD, connect_timeout=3
    )


def store_click(item):
    code, ts = item.split("|")
    with db() as conn:
        conn.execute(
            "INSERT INTO clicks (code, clicked_at) VALUES (%s, to_timestamp(%s))",
            (code, int(ts)),
        )


def write_report():
    today = datetime.date.today().isoformat()
    with db() as conn:
        rows = conn.execute(
            "SELECT code, count(*) FROM clicks GROUP BY code ORDER BY count(*) DESC"
        ).fetchall()
    os.makedirs(REPORT_DIR, exist_ok=True)
    path = os.path.join(REPORT_DIR, f"clicks-{today}.csv")
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["code", "clicks"])
        writer.writerows(rows)
    print(f"report written: {path} ({len(rows)} codes)", flush=True)
    if WEBHOOK_URL:
        resp = requests.post(WEBHOOK_URL, json={"date": today, "codes": len(rows)}, timeout=10)
        print(f"webhook status: {resp.status_code}", flush=True)


def main():
    print("worker started", flush=True)
    next_report = time.time()
    while True:
        with open(HEARTBEAT_FILE, "w") as f:
            f.write(str(int(time.time())))
        item = cache.blpop("clicks", timeout=5)
        if item:
            store_click(item[1])
            print(f"stored click {item[1]}", flush=True)
        if time.time() >= next_report:
            write_report()
            next_report = time.time() + REPORT_INTERVAL


if __name__ == "__main__":
    main()
