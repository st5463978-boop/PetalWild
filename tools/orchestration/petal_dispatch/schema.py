"""Bounded routing schema. Unknown values are rejected."""

from __future__ import annotations

OWNERS = (
    "PETAL_01_GARDEN",
    "PETAL_02_ECOLOGY",
    "PETAL_03_JELLY",
    "PETAL_04_VEG_PEOPLE",
    "PETAL_05_WORLD",
    "PETAL_06_VFX_SHADER",
    "PETAL_07_UI",
    "PETAL_08_ECONOMY",
    "PETAL_09_TOWN",
    "PETAL_10_CAMERA",
    "PETAL_11_AUDIO",
    "PETAL_12_QA",
    "PETAL_13_ASSETS",
    "PETAL_14_CITY",
    "PETAL_15_PERFORMANCE",
    "PETAL_00_INTEGRATION",
    "ESCALATE_GROK",
)

ACTIONS = (
    "ROUTE_AGENT",
    "ROUTE_ASSET_HUNT",
    "ROUTE_QA",
    "ROUTE_LICENSE_REVIEW",
    "ROUTE_PERFORMANCE",
    "ROUTE_INTEGRATION",
    "PARALLELISE",
    "SERIALISE",
    "RETRY",
    "REQUEST_REVIEW",
    "ESCALATE_GROK",
    "BLOCK_PENDING_DEPENDENCY",
)

PRIORITIES = ("HIGH", "MEDIUM", "LOW")
CONFIDENCE = ("HIGH", "MEDIUM", "LOW")

# Action implied by an owner when the model omits a legal action.
# The wrapper still requires the model to send an action; this map is only
# used by the benchmark gold set, not to repair model output.
OWNER_ACTION = {
    "PETAL_13_ASSETS": "ROUTE_ASSET_HUNT",
    "PETAL_12_QA": "ROUTE_QA",
    "PETAL_15_PERFORMANCE": "ROUTE_PERFORMANCE",
    "PETAL_00_INTEGRATION": "ROUTE_INTEGRATION",
    "ESCALATE_GROK": "ESCALATE_GROK",
}


def prompt_for(task: str, event: str = "") -> str:
    owners = "|".join(OWNERS)
    actions = "|".join(ACTIONS)
    head = f"EVENT: {event}\n" if event else ""
    return (
        "PetalWild dev router. Reply with one JSON object and nothing else.\n"
        f"owner: {owners}\n"
        "secondary: owner or NONE\n"
        "priority: HIGH|MEDIUM|LOW\n"
        "parallel: true or false\n"
        f"action: {actions}\n"
        "escalate: true or false\n"
        "confidence: HIGH|MEDIUM|LOW\n"
        f"{head}TASK: {task.strip()}\n"
    )


def _as_bool(value) -> bool | None:
    if isinstance(value, bool):
        return value
    return None


def parse_decision(payload: dict) -> dict | None:
    if not isinstance(payload, dict):
        return None
    owner = payload.get("owner")
    secondary = payload.get("secondary", "NONE")
    priority = payload.get("priority")
    action = payload.get("action")
    confidence = payload.get("confidence", "MEDIUM")
    parallel = _as_bool(payload.get("parallel"))
    escalate = _as_bool(payload.get("escalate"))
    if owner not in OWNERS or priority not in PRIORITIES or action not in ACTIONS:
        return None
    if confidence not in CONFIDENCE or parallel is None or escalate is None:
        return None
    if secondary != "NONE" and secondary not in OWNERS:
        return None
    if secondary == owner:
        secondary = "NONE"
    return {
        "owner": owner,
        "secondary": secondary,
        "priority": priority,
        "parallel": parallel,
        "action": action,
        "escalate": escalate,
        "confidence": confidence,
    }
