"""Offline tests for the clean-core miner. They do not call live decide."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ORCH = HERE.parent
if str(ORCH) not in sys.path:
    sys.path.insert(0, str(ORCH))

from jevh_clean_core.cases import FORBIDDEN_OPTIONS, KINDS, assert_bank_ok, load_cases
from jevh_clean_core.client import DEFAULT_DECIDE_URL, post_decide
from jevh_clean_core.score import map_choice, numeric_confidence, score_attempt


def _chip(choice: str, index: int, confidence: float, scores=None) -> dict:
    return {
        "choice": choice,
        "index": index,
        "scores": scores if scores is not None else [confidence, 1.0 - confidence],
        "confidence": confidence,
        "npu_ms": 47.0,
    }


def _payload(options: list[str], answer_index: int, *, chip_index=None, chip_conf=0.95, escalated=False):
    idx = answer_index if chip_index is None else chip_index
    choice = options[idx]
    body = {
        "choice": options[answer_index],
        "index": answer_index,
        "scores": [1.0, 0.0],
        "confidence": 0.92,
        "escalated": escalated,
        "decided_by": "teacher" if escalated else "chip",
        "model": "teacher" if escalated else "hef",
        "shuffle_order": list(range(len(options))),
        "chip": _chip(choice, idx, chip_conf),
    }
    return body


class BankTests(unittest.TestCase):
    def test_bank_is_diagnostic_and_complete(self) -> None:
        cases = load_cases()
        assert_bank_ok(cases)
        self.assertGreaterEqual(len(cases), 8 * 5)
        self.assertEqual({c["kind"] for c in cases}, set(KINDS))
        for case in cases:
            self.assertFalse(case["training_eligible"])
            self.assertGreaterEqual(len(case["options"]), 2)
            self.assertIn(case["answer"], case["options"])
            for option in case["options"]:
                self.assertNotIn(option.strip().lower(), FORBIDDEN_OPTIONS)
            text = (case["question"] + " " + case["context"]).lower()
            self.assertNotIn("too_hard", text)
            self.assertNotIn("jelly squash", text)

    def test_answers_are_not_all_first_option(self) -> None:
        cases = load_cases()
        first = sum(1 for case in cases if case["answer"] == case["options"][0])
        self.assertLess(first, len(cases))
        self.assertGreater(first, 0)


class ScoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.case = {
            "id": "src-ttl-over",
            "kind": "source_stale",
            "family": "ttl_arithmetic",
            "question": "Is the source stale?",
            "options": ["fresh", "stale"],
            "answer": "stale",
            "why": "age > ttl",
            "training_eligible": False,
        }

    def test_confident_wrong_chip_counts(self) -> None:
        payload = _payload(self.case["options"], 1, chip_index=0, chip_conf=0.94, escalated=True)
        row = score_attempt(self.case, payload)
        self.assertTrue(row["counted_failure"])
        self.assertEqual(row["jev_source"], "chip")
        self.assertEqual(row["jev_choice"], "fresh")
        self.assertGreaterEqual(row["jev_confidence"], 0.90)
        self.assertFalse(row["training_eligible"])
        self.assertEqual(row["bucket"], "QUARANTINE")
        self.assertTrue(row["production_escalated"])
        self.assertFalse(row["routing_should_escalate"])

    def test_teacher_right_does_not_excuse_chip(self) -> None:
        payload = _payload(self.case["options"], 1, chip_index=0, chip_conf=0.96, escalated=True)
        row = score_attempt(self.case, payload)
        self.assertEqual(row["teacher_choice"], "stale")
        self.assertEqual(row["jev_choice"], "fresh")
        self.assertTrue(row["counted_failure"])

    def test_low_confidence_wrong_does_not_count(self) -> None:
        payload = _payload(self.case["options"], 1, chip_index=0, chip_conf=0.52, escalated=True)
        row = score_attempt(self.case, payload)
        self.assertTrue(row["jev_wrong"])
        self.assertFalse(row["counted_failure"])
        self.assertEqual(row["skip"], None)

    def test_confident_correct_is_not_a_failure(self) -> None:
        payload = _payload(self.case["options"], 1, chip_index=1, chip_conf=0.97)
        row = score_attempt(self.case, payload)
        self.assertFalse(row["jev_wrong"])
        self.assertFalse(row["counted_failure"])

    def test_index_choice_mismatch_is_quarantined(self) -> None:
        payload = _payload(self.case["options"], 1, chip_index=1, chip_conf=0.99, escalated=True)
        payload["chip"]["choice"] = "fresh"
        payload["chip"]["index"] = 1
        row = score_attempt(self.case, payload)
        self.assertFalse(row["counted_failure"])
        self.assertEqual(row["skip"], "index_choice_mismatch")
        self.assertEqual(row["bucket"], "QUARANTINE")

    def test_duplicate_is_not_counted_twice(self) -> None:
        payload = _payload(self.case["options"], 1, chip_index=0, chip_conf=0.95, escalated=True)
        first = score_attempt(self.case, payload)
        seen = {first["fingerprint"]}
        second = score_attempt(self.case, payload, seen)
        self.assertTrue(first["counted_failure"])
        self.assertFalse(second["counted_failure"])
        self.assertEqual(second["skip"], "duplicate")

    def test_missing_chip_on_escalation_is_not_a_counted_failure(self) -> None:
        payload = {
            "choice": "stale",
            "index": 1,
            "escalated": True,
            "decided_by": "teacher",
            "confidence": 0.99,
        }
        row = score_attempt(self.case, payload)
        self.assertFalse(row["counted_failure"])
        self.assertEqual(row["skip"], "no_forced_jev")

    def test_map_choice_never_defaults_to_zero(self) -> None:
        mapped = map_choice({"choice": "neither"}, ["fresh", "stale"])
        self.assertFalse(mapped["ok"])
        self.assertNotIn("option", mapped)
        empty = map_choice({}, ["fresh", "stale"])
        self.assertFalse(empty["ok"])
        self.assertNotEqual(empty.get("option"), "fresh")

    def test_numeric_confidence_reads_chip(self) -> None:
        self.assertEqual(numeric_confidence({"confidence": 0.91}), 0.91)
        self.assertEqual(numeric_confidence({"scores": [0.2, 0.8]}), 0.8)
        self.assertIsNone(numeric_confidence({"confidence": "HIGH"}))


class ClientTests(unittest.TestCase):
    def test_post_sends_kind_and_refuses_one_option(self) -> None:
        with self.assertRaises(ValueError):
            post_decide(DEFAULT_DECIDE_URL, "q", ["only"])

        captured = {}

        class _Resp:
            def read(self):
                return json.dumps({"choice": "stale", "index": 1}).encode()

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        def fake_urlopen(request, timeout=0):
            captured["url"] = request.full_url
            captured["body"] = json.loads(request.data.decode())
            captured["timeout"] = timeout
            return _Resp()

        with patch("jevh_clean_core.client.urllib.request.urlopen", side_effect=fake_urlopen):
            payload = post_decide(
                "http://127.0.0.1:8771/v1/decide",
                "Is the source stale?",
                ["fresh", "stale"],
                context="age=9 ttl=6",
                kind="source_stale",
                timeout=5.0,
            )
        self.assertEqual(payload["choice"], "stale")
        self.assertTrue(captured["url"].endswith("/decide"))
        self.assertEqual(captured["body"]["kind"], "source_stale")
        self.assertEqual(captured["body"]["agent"], "jevh-clean-core")
        self.assertGreaterEqual(len(captured["body"]["options"]), 2)


if __name__ == "__main__":
    unittest.main()
