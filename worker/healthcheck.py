"""Exit 0 if the worker wrote its heartbeat file in the last 30 seconds, else exit 1."""
import os
import sys
import time

path = os.environ.get("HEARTBEAT_FILE", "/tmp/worker-heartbeat")
try:
    with open(path) as f:
        age = time.time() - int(f.read().strip())
    sys.exit(0 if age < 30 else 1)
except Exception:
    sys.exit(1)
