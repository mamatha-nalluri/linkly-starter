"""Exit 0 if the API answers /health with HTTP 200, else exit 1. Uses only the standard library."""
import sys
import urllib.request

try:
    with urllib.request.urlopen("http://127.0.0.1:5000/health", timeout=3) as resp:
        sys.exit(0 if resp.status == 200 else 1)
except Exception:
    sys.exit(1)
