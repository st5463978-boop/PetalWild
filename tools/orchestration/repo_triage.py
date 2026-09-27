"""Bounded repository triage against the Pi Hailo decide service.

Prints one JSON decision. It does not clone, import, or run shell commands
from the model output. Licence and architecture overrides stay with the caller.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_TOOLS = Path(__file__).resolve().parents[1]
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))
_ORCH = Path(__file__).resolve().parent
if str(_ORCH) not in sys.path:
    sys.path.insert(0, str(_ORCH))

from petal_dispatch.hailo_backend import choice_from_payload, post_decide  # noqa: E402
from hailo_decide_url import resolve_decide_url  # noqa: E402

OPTIONS = (
    "DIRECT_IMPORT",
    "PORT_TECHNIQUE",
    "USE_AS_REFERENCE",
    "REJECT_LICENSE",
    "REJECT_TECHNICAL",
    "NEEDS_DEEP_REVIEW",
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Ask the Pi decide service how to treat one candidate.")
    parser.add_argument("--name", required=True)
    parser.add_argument("--facts", required=True)
    args = parser.parse_args()
    question = (
        f"CANDIDATE: {args.name}. "
        f"FACTS: {args.facts} "
        "Pick the integration decision."
    )[:500]
    url = resolve_decide_url()
    payload = post_decide(url, question, list(OPTIONS), 75.0)
    choice = choice_from_payload(payload, list(OPTIONS))
    print(json.dumps({
        "candidate": args.name,
        "decision": choice,
        "model": payload.get("model"),
        "latency_ms": payload.get("latency_ms"),
        "raw": payload.get("raw"),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
