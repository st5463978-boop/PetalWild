"""Resolve HAILO_DECIDE_URL from the Pi's public discovery topic (ntfy.sh).

Order: discovery (live tunnel, /health-checked) -> existing env HAILO_DECIDE_URL -> Tailscale default.
Usage:  eval "$(python3 tools/hailo_decide_url.py --export)"   # at startup
        from hailo_decide_url import resolve_decide_url; url = resolve_decide_url(force=True)  # on failure
"""
import json, os, sys, urllib.request

DISCOVERY_URL = os.environ.get(
    "HAILO_DECIDE_DISCOVERY_URL",
    "https://ntfy.sh/petalwild-hailo-decide-b71128b262bf79cd/raw?poll=1&since=latest",
)
TAILSCALE_DEFAULT = "http://100.126.22.71:8766/v1/decide"


def _get(url, timeout=15):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.status, r.read().decode().strip()


def _healthy(base):
    try:
        s, body = _get(base.rstrip("/") + "/health", 20)
        return s == 200 and json.loads(body).get("ok") is True
    except Exception:
        return False


def discover_base():
    """Return the newest published tunnel base URL (no path) or None."""
    try:
        _, text = _get(DISCOVERY_URL)
        lines = [l.strip() for l in text.splitlines() if l.strip().startswith("https://")]
        return lines[-1].rstrip("/") if lines else None
    except Exception:
        return None


def resolve_decide_url(force=False):
    env = os.environ.get("HAILO_DECIDE_URL", "").strip()
    if env and not force and _healthy(env.split("/v1/decide")[0].split("/decide")[0]):
        return env
    base = discover_base()
    if base and _healthy(base):
        url = base + "/v1/decide"
    elif env:
        url = env
    else:
        url = TAILSCALE_DEFAULT
    os.environ["HAILO_DECIDE_URL"] = url
    return url


if __name__ == "__main__":
    url = resolve_decide_url(force=True)
    print(f"export HAILO_DECIDE_URL={url}" if "--export" in sys.argv else url)
