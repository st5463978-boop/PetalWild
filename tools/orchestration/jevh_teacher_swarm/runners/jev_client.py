"""Live JEV-H client.

POST goes through the clean-core miner. Discovery order is that client's:
explicit URL, localhost, then the ntfy topic. No tunnel host is hardcoded.
"""

from __future__ import annotations

from jevh_clean_core.client import _get_json, origin, post_decide, resolve_decide_url

AGENT = "jevh-teacher-swarm"


def context_for(case: dict) -> str:
    parts = []
    for key, value in (case.get("facts") or {}).items():
        parts.append(f"{key}={value}")
    return " ".join(parts)[:240]


def fetch_health(timeout: float = 20.0) -> dict:
    url = resolve_decide_url()
    root = origin(url)
    errors: list[str] = []
    for path in ("/health", "/v1/health"):
        try:
            payload = _get_json(root + path, timeout)
        except Exception as exc:  # noqa: BLE001 — health is best-effort evidence
            errors.append(f"{path}:{type(exc).__name__}")
            continue
        if payload.get("ok") is True:
            detail = payload.get("detail") if isinstance(payload.get("detail"), dict) else {}
            sha = str(detail.get("hef_sha256") or "")
            return {
                "ok": True,
                "model": payload.get("model"),
                "device": payload.get("device"),
                "hef_sha_prefix": sha[:8],
                "chip_cond": detail.get("chip_cond"),
                "chip_held": detail.get("chip_held"),
                "last_probe": detail.get("last_probe"),
                "threshold": detail.get("threshold"),
                "decisions": detail.get("decisions"),
                "escalated": detail.get("escalated"),
                "npu_fail_streak": detail.get("npu_fail_streak"),
            }
    raise RuntimeError("health failed: " + ",".join(errors))


def decide(case: dict, timeout: float) -> dict:
    url = resolve_decide_url()
    return post_decide(
        url,
        case["question"],
        list(case["presented_options"]),
        context=context_for(case),
        agent=AGENT,
        kind=case.get("kind") or "",
        timeout=timeout,
    )
