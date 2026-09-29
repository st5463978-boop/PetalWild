"""Resolve HAILO_DECIDE_URL from the Pi's public JEV-H discovery topic (ntfy.sh).

JEV-H is port 8771. Port 8766 is the old Qwen3 chat decide service — do not use it.
Do not hardcode a trycloudflare host; the public base changes when the tunnel restarts.

Order: discovery (live tunnel, /health-checked) -> existing env HAILO_DECIDE_URL -> Tailscale default.
HAILO_DECIDE_URL overrides when set on purpose and that origin is healthy.
Usage:  eval "$(python3 tools/hailo_decide_url.py --export)"   # at startup
        from hailo_decide_url import resolve_decide_url; url = resolve_decide_url(force=True)  # on failure
"""
import json, os, sys, urllib.request

DISCOVERY_URL = os.environ.get(
    "HAILO_DECIDE_DISCOVERY_URL",
    "https://ntfy.sh/jevh-decide-05923aed092556ed/raw?poll=1&since=latest",
)
TAILSCALE_DEFAULT = "http://100.126.22.71:8771/v1/decide"


def _get(url, timeout=15):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.status, r.read().decode().strip()


def _healthy(base):
    root = base.rstrip("/")
    for path in ("/health", "/v1/health"):
        try:
            s, body = _get(root + path, 20)
            if s == 200 and json.loads(body).get("ok") is True:
                return True
        except Exception:
            continue
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
