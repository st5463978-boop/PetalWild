"""Resolve System-1 decide URLs from ntfy discovery topics.

Order of live services:
  1. primary  — hef-dfc CPU DPO (~1.3–1.8s). Timeout ~15s.
  2. fallback — Pi CPU DPO (~4–5s warm, up to ~55s after idle). Timeout ~60s.
  3. last resort — existing hailo-decision :8766 hop. Timeout ~75s.

Each tier: discovery topic (last https:// line), /health check, then the env URL.
Quick-tunnel hosts are not hardcoded; they come from discovery or env.

Usage:  eval "$(python3 tools/hailo_decide_url.py --export)"
        from hailo_decide_url import resolve_decide_url, resolve_decide_tiers
"""
import json, os, sys, urllib.request

PRIMARY_DISCOVERY_DEFAULT = (
    "https://ntfy.sh/petalwild-hailojev-decide-hef-729b47676dfdd628/raw?poll=1&since=latest"
)
FALLBACK_DISCOVERY_DEFAULT = (
    "https://ntfy.sh/petalwild-hailojev-decide-picpu-78ede63f3f827400/raw?poll=1&since=latest"
)
LAST_RESORT_DISCOVERY_DEFAULT = (
    "https://ntfy.sh/petalwild-hailo-decide-b71128b262bf79cd/raw?poll=1&since=latest"
)
TAILSCALE_DEFAULT = "http://100.126.22.71:8766/v1/decide"

PRIMARY_TIMEOUT = 15.0
FALLBACK_TIMEOUT = 60.0
LAST_RESORT_TIMEOUT = 75.0


def _get(url, timeout=15):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.status, r.read().decode().strip()


def _origin(url):
    raw = (url or "").strip().rstrip("/")
    for suffix in ("/v1/decide", "/decide"):
        if raw.endswith(suffix):
            return raw[: -len(suffix)]
    return raw


def _as_decide(url):
    raw = (url or "").strip().rstrip("/")
    if not raw:
        return ""
    if raw.endswith("/v1/decide") or raw.endswith("/decide"):
        return raw
    return raw + "/v1/decide"


def _healthy(base):
    if not base:
        return False
    try:
        s, body = _get(base.rstrip("/") + "/health", 20)
        return s == 200 and json.loads(body).get("ok") is True
    except Exception:
        return False


def discover_base(topic_url):
    """Return the newest published tunnel base URL (no path) or None."""
    try:
        _, text = _get(topic_url)
        lines = [l.strip() for l in text.splitlines() if l.strip().startswith("https://")]
        return lines[-1].rstrip("/") if lines else None
    except Exception:
        return None


def _resolve_tier(discovery_env, url_env, discovery_default, last_default="", force=False):
    """Discovery (health-checked) then env. last_default is last-resort only."""
    env = os.environ.get(url_env, "").strip()
    topic = os.environ.get(discovery_env, discovery_default).strip() or discovery_default
    if env and not force and _healthy(_origin(env)):
        return _as_decide(env)
    base = discover_base(topic) if topic else None
    if base and _healthy(base):
        url = _as_decide(base)
        os.environ[url_env] = url
        return url
    if env:
        return _as_decide(env)
    if last_default:
        return _as_decide(last_default)
    return ""


def resolve_decide_tiers(force=False):
    """Return [(name, url, timeout), ...] skipping unresolved tiers."""
    tiers = []
    primary = _resolve_tier(
        "HAILO_DECIDE_PRIMARY_DISCOVERY_URL",
        "HAILO_DECIDE_PRIMARY_URL",
        PRIMARY_DISCOVERY_DEFAULT,
        force=force,
    )
    if primary:
        tiers.append(("primary", primary, PRIMARY_TIMEOUT))
    fallback = _resolve_tier(
        "HAILO_DECIDE_FALLBACK_DISCOVERY_URL",
        "HAILO_DECIDE_FALLBACK_URL",
        FALLBACK_DISCOVERY_DEFAULT,
        force=force,
    )
    if fallback:
        tiers.append(("fallback", fallback, FALLBACK_TIMEOUT))
    last = _resolve_tier(
        "HAILO_DECIDE_DISCOVERY_URL",
        "HAILO_DECIDE_LAST_URL",
        LAST_RESORT_DISCOVERY_DEFAULT,
        last_default=TAILSCALE_DEFAULT,
        force=force,
    )
    if last:
        # Do not let last-resort share HAILO_DECIDE_URL; that env is the active first tier.
        tiers.append(("last_resort", last, LAST_RESORT_TIMEOUT))
    return tiers


def resolve_decide_url(force=False):
    """First available tier. Also sets HAILO_DECIDE_URL for older callers."""
    tiers = resolve_decide_tiers(force)
    url = tiers[0][1] if tiers else TAILSCALE_DEFAULT
    os.environ["HAILO_DECIDE_URL"] = url
    return url


if __name__ == "__main__":
    tiers = resolve_decide_tiers(force=True)
    url = tiers[0][1] if tiers else TAILSCALE_DEFAULT
    os.environ["HAILO_DECIDE_URL"] = url
    if "--export" in sys.argv:
        print(f"export HAILO_DECIDE_URL={url}")
        for name, tier_url, _timeout in tiers:
            if name == "primary":
                print(f"export HAILO_DECIDE_PRIMARY_URL={tier_url}")
            elif name == "fallback":
                print(f"export HAILO_DECIDE_FALLBACK_URL={tier_url}")
            elif name == "last_resort":
                print(f"export HAILO_DECIDE_LAST_URL={tier_url}")
    elif "--tiers" in sys.argv:
        print(json.dumps([{"tier": n, "url": u, "timeout_s": t} for n, u, t in tiers]))
    else:
        print(url)
