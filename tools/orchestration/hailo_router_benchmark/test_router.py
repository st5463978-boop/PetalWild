"""Wrapper tests. They do not pretend a missing NPU produced a route."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from petal_dispatch.router import Backend, decide, extract_json  # noqa: E402
from petal_dispatch.schema import parse_decision, prompt_for  # noqa: E402


def _good(**overrides) -> str:
    payload = {
        "owner": "PETAL_03_JELLY",
        "secondary": "PETAL_06_VFX_SHADER",
        "priority": "HIGH",
        "parallel": True,
        "action": "ROUTE_AGENT",
        "escalate": False,
        "confidence": "HIGH",
    }
    payload.update(overrides)
    return json.dumps(payload)


class Scripted(Backend):
    name = "scripted"

    def __init__(self, replies: list[str]):
        self.replies = list(replies)
        self.calls = 0

    def available(self) -> bool:
        return True

    def complete(self, prompt: str, timeout: float) -> str:
        self.calls += 1
        if not self.replies:
            return ""
        return self.replies.pop(0)


class RouterTests(unittest.TestCase):
    def test_prompt_lists_owners_and_stays_short(self) -> None:
        text = prompt_for("Jelly does not squash.")
        self.assertIn("PETAL_03_JELLY", text)
        self.assertIn("ESCALATE_GROK", text)
        self.assertLess(len(text.split()), 220)
        self.assertNotIn("explain", text.lower())

    def test_rejects_unknown_owner(self) -> None:
        self.assertIsNone(parse_decision(json.loads(_good(owner="PETAL_99"))))

    def test_rejects_string_bool(self) -> None:
        self.assertIsNone(parse_decision(json.loads(_good(parallel="true"))))

    def test_extracts_fenced_json(self) -> None:
        raw = "```json\n" + _good() + "\n```"
        self.assertEqual(extract_json(raw)["owner"], "PETAL_03_JELLY")

    def test_retries_malformed_once(self) -> None:
        backend = Scripted(["sorry, no", _good()])
        decision = decide("Jelly does not squash on impact.", backend)
        self.assertEqual(decision["owner"], "PETAL_03_JELLY")
        self.assertEqual(decision["attempts"], 2)
        self.assertEqual(backend.calls, 2)

    def test_second_malformed_escalates(self) -> None:
        backend = Scripted(["nope", "still nope"])
        decision = decide("Jelly does not squash.", backend)
        self.assertEqual(decision["action"], "ESCALATE_GROK")
        self.assertEqual(decision["reason"], "malformed")
        self.assertTrue(decision["escalate"])
        self.assertEqual(backend.calls, 2)

    def test_unavailable_does_not_guess(self) -> None:
        decision = decide("FPS dropped after vegetation merge.", Backend())
        self.assertEqual(decision["reason"], "backend_unavailable")
        self.assertEqual(decision["owner"], "ESCALATE_GROK")
        self.assertNotIn("accuracy", decision)

    def test_low_confidence_escalates_without_calling_it_a_probability(self) -> None:
        decision = decide("Maybe audio.", Scripted([_good(confidence="LOW", owner="PETAL_11_AUDIO")]))
        self.assertTrue(decision["escalate"])
        self.assertFalse(decision["confidence_calibrated"])
        self.assertEqual(decision["suggested_owner"], "PETAL_11_AUDIO")

    def test_medium_confidence_adds_integration_review(self) -> None:
        decision = decide(
            "Font scale slider does nothing.",
            Scripted([_good(confidence="MEDIUM", owner="PETAL_07_UI", secondary="NONE")]),
        )
        self.assertEqual(decision["owner"], "PETAL_07_UI")
        self.assertEqual(decision["secondary"], "PETAL_00_INTEGRATION")
        self.assertFalse(decision["escalate"])

    def test_gpl_paste_is_blocked_by_the_wrapper(self) -> None:
        decision = decide(
            "Paste the Jelly-Baby GPL spring solver into scripts/sim.",
            Scripted([_good(owner="PETAL_03_JELLY", confidence="HIGH")]),
        )
        self.assertEqual(decision["reason"], "licence_block")
        self.assertEqual(decision["owner"], "ESCALATE_GROK")

    def test_gpl_paste_blocks_before_a_missing_device(self) -> None:
        decision = decide("Paste the Jelly-Baby GPL spring solver into scripts/sim.", Backend())
        self.assertEqual(decision["reason"], "licence_block")
        self.assertEqual(decision["source"], "wrapper")

    def test_game_tree_does_not_reference_the_dispatcher(self) -> None:
        root = Path(__file__).resolve().parents[3]
        needles = ("petal_dispatch", "hailo_router", "8731")
        for folder in ("scripts", "scenes", "data", "shaders"):
            for path in (root / folder).rglob("*"):
                if path.suffix.lower() not in {".gd", ".tscn", ".json", ".gdshader"}:
                    continue
                text = path.read_text(encoding="utf-8", errors="ignore").lower()
                for needle in needles:
                    self.assertNotIn(needle, text, f"{path} references {needle}")


if __name__ == "__main__":
    unittest.main()
