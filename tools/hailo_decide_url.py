"""Resolve HAILO_DECIDE_URL from env, then the ntfy discovery topic.

JEV-H is port 8771. Port 8766 is the old Qwen3 chat decide service — do not use it.
Do not hardcode a trycloudflare host; the public base changes when the tunnel restarts.
Do not commit a Tailscale IP or ntfy topic.

Order: existing env HAILO_DECIDE_URL (health-checked) -> HAILO_DECIDE_DISCOVERY_URL
(live tunnel, /health-checked) -> existing env HAILO_DECIDE_URL. If both env vars
are unset, or discovery fails and HAILO_DECIDE_URL is unset, raise DecideUrlError.
Usage:  eval "$(python3 tools/hailo_decide_url.py --export)"   # at startup
        from hailo_decide_url import resolve_decide_url; url = resolve_decide_url(force=True)  # on failure
"""
import json, os, sys, urllib.request

MISSING_ENV = (
    "Cannot resolve Hailo decide URL: set HAILO_DECIDE_URL "
    "(for example http://piai-1:8771/v1/decide from MagicDNS or tailscale status) "
    "or HAILO_DECIDE_DISCOVERY_URL "
    "(https://ntfy.sh/<NTFY_TOPIC>/raw?poll=1&since=latest). "
    "There is no in-tree Tailscale or ntfy default."
)


class DecideUrlError(RuntimeError):
    """HAILO_DECIDE_URL / HAILO_DECIDE_DISCOVERY_URL missing or unusable."""


def _env(name: str) -> str:
    return os.environ.get(name, "").strip()


def discovery_url() -> str:
    """Return HAILO_DECIDE_DISCOVERY_URL, or empty if unset."""
    return _env("HAILO_DECIDE_DISCOVERY_URL")


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
    url = discovery_url()
    if not url:
        return None
    try:
        _, text = _get(url)
        lines = [l.strip() for l in text.splitlines() if l.strip().startswith("https://")]
        return lines[-1].rstrip("/") if lines else None
    except Exception:
        return None


def resolve_decide_url(force=False):
    env = _env("HAILO_DECIDE_URL")
    if env and not force and _healthy(env.split("/v1/decide")[0].split("/decide")[0]):
        return env
    base = discover_base()
    if base and _healthy(base):
        url = base + "/v1/decide"
    elif env:
        url = env
    else:
        raise DecideUrlError(MISSING_ENV)
    os.environ["HAILO_DECIDE_URL"] = url
    return url


if __name__ == "__main__":
    try:
        url = resolve_decide_url(force=True)
    except DecideUrlError as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
    print(f"export HAILO_DECIDE_URL={url}" if "--export" in sys.argv else url)
