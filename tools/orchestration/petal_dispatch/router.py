"""Validate a local model decision. The model does not run tools."""

from __future__ import annotations

import json
import re

from petal_dispatch.schema import CONFIDENCE, parse_decision, prompt_for

_FENCE = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL | re.IGNORECASE)

# Wrapper overrides. These are deterministic, and they are not a router.
_ARCHITECTURE = (
    "rewrite the simulation",
    "replace the architecture",
    "change the simulation lod",
    "foundational architecture",
)
_VISION = (
    "change the creative",
    "change petalwild into",
    "abandon the garden",
    "rewrite the vision",
)
_LICENCE_BLOCK = (
    "paste gpl",
    "paste the jelly-baby gpl",
    "jelly-baby gpl",
    "copy gpl",
    "copy the gpl",
    "jelly-baby source",
    "tip-recomp source",
    "tip-recomp",
)


def extract_json(text: str) -> dict | None:
    if not text:
        return None
    fenced = _FENCE.search(text)
    raw = fenced.group(1) if fenced else text
    start = raw.find("{")
    end = raw.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        payload = json.loads(raw[start : end + 1])
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    return payload


class Backend:
    """Local completion. Implementations must not receive a tool list."""

    name = "backend"

    def available(self) -> bool:
        return False

    def complete(self, prompt: str, timeout: float) -> str:
        raise RuntimeError("no backend")


def _absent(reason: str) -> dict:
    return {
        "owner": "ESCALATE_GROK",
        "secondary": "NONE",
        "priority": "HIGH",
        "parallel": False,
        "action": "ESCALATE_GROK",
        "escalate": True,
        "confidence": "LOW",
        "source": "wrapper",
        "reason": reason,
        "attempts": 0,
    }


def _apply_confidence(decision: dict) -> dict:
    # HIGH / MEDIUM / LOW are labels from the model, not calibrated probabilities.
    decision = dict(decision)
    decision["confidence_calibrated"] = False
    level = decision.get("confidence", "MEDIUM")
    if level not in CONFIDENCE:
        level = "LOW"
    if level == "LOW":
        decision["suggested_owner"] = decision["owner"]
        decision["owner"] = "ESCALATE_GROK"
        decision["action"] = "ESCALATE_GROK"
        decision["escalate"] = True
        decision["reason"] = "low_confidence_label"
    elif level == "MEDIUM" and decision.get("secondary") in (None, "", "NONE"):
        decision["secondary"] = "PETAL_00_INTEGRATION"
        decision["reason"] = "medium_confidence_needs_review"
    else:
        decision["reason"] = "model"
    return decision


def _wrapper_override(task: str, decision: dict) -> dict:
    text = task.lower()
    decision = dict(decision)
    if any(phrase in text for phrase in _LICENCE_BLOCK):
        decision["owner"] = "ESCALATE_GROK"
        decision["secondary"] = "PETAL_13_ASSETS"
        decision["action"] = "ESCALATE_GROK"
        decision["escalate"] = True
        decision["reason"] = "licence_block"
    elif any(phrase in text for phrase in _VISION):
        decision["owner"] = "ESCALATE_GROK"
        decision["action"] = "ESCALATE_GROK"
        decision["escalate"] = True
        decision["reason"] = "creative_vision"
    elif any(phrase in text for phrase in _ARCHITECTURE):
        decision["owner"] = "ESCALATE_GROK"
        decision["secondary"] = "PETAL_00_INTEGRATION"
        decision["action"] = "ESCALATE_GROK"
        decision["escalate"] = True
        decision["reason"] = "foundational_architecture"
    return decision


def decide(task: str, backend: Backend, event: str = "", timeout: float = 8.0) -> dict:
    forced = _wrapper_override(task, {
        "owner": "PETAL_00_INTEGRATION",
        "secondary": "NONE",
        "priority": "HIGH",
        "parallel": False,
        "action": "ROUTE_INTEGRATION",
        "escalate": False,
        "confidence": "HIGH",
    })
    if forced.get("reason") in ("licence_block", "creative_vision", "foundational_architecture"):
        forced["source"] = "wrapper"
        forced["attempts"] = 0
        forced["confidence_calibrated"] = False
        return forced
    if not backend.available():
        return _absent("backend_unavailable")
    prompt = prompt_for(task, event)
    last_error = "malformed"
    for attempt in (1, 2):
        try:
            raw = backend.complete(prompt if attempt == 1 else prompt + "JSON only.\n", timeout)
        except Exception as exc:  # noqa: BLE001 — backend failures escalate
            last_error = f"backend_error:{type(exc).__name__}"
            continue
        parsed = extract_json(raw or "")
        decision = parse_decision(parsed) if parsed is not None else None
        if decision is None:
            last_error = "malformed"
            continue
        decision = _apply_confidence(decision)
        decision = _wrapper_override(task, decision)
        decision["source"] = backend.name
        decision["attempts"] = attempt
        return decision
    result = _absent(last_error)
    result["attempts"] = 2
    return result
