"""Offline tests for the ownership miner. They do not call live decide."""

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

from jevh_owner.cases import FAMILY, FORBIDDEN_OPTIONS, assert_bank_ok, load_cases
from jevh_owner.client import AGENT, KIND, chip_probe_ok, post_decide, refuse_teacher
from jevh_owner.score import clear_position_bias, numeric_confidence, score_attempt


def _chip(choice: str, index: int, confidence: float) -> dict:
    return {
        "choice": choice,
        "index": index,
        "confidence": confidence,
        "scores": [confidence, round(1.0 - confidence, 6)]
        if index == 0
        else [round(1.0 - confidence, 6), confidence],
        "npu_ms": 48.0,
    }


def _case() -> dict:
    return {
        "id": "own-short",
        "kind": "adversarial",
        "family": "ownership",
        "contrast": "short-rule",
        "named": "Vesper",
        "bystander": "Calder",
        "question": "Who owns the task?",
        "options": ["Calder", "Vesper"],
        "answer": "Vesper",
        "why": "Vesper is the named worker.",
        "training_eligible": False,
    }


class BankTests(unittest.TestCase):
    def test_bank_is_ownership_only(self) -> None:
        cases = load_cases()
        assert_bank_ok(cases)
        self.assertGreaterEqual(len(cases), 40)
        for case in cases:
            self.assertEqual(case["family"], FAMILY)
            self.assertEqual(case["kind"], "adversarial")
            self.assertFalse(case["training_eligible"])
            self.assertEqual(len(case["options"]), 2)
            self.assertEqual(case["answer"], case["named"])
            self.assertIn(case["bystander"], case["options"])
            for option in case["options"]:
                self.assertNotIn(option.strip().lower(), FORBIDDEN_OPTIONS)
            blob = (case["question"] + case["context"]).lower()
            self.assertNotIn("too_hard", blob)
            self.assertNotIn("escalate", blob)


class ScoreTests(unittest.TestCase):
    def test_confident_wrong_chip_counts(self) -> None:
        case = _case()
        payload = {
            "choice": "Vesper",
            "index": 1,
            "confidence": 0.99,
            "escalated": True,
            "decided_by": "teacher",
            "model": "teacher.gguf",
            "chip": _chip("Calder", 0, 0.94),
        }
        row = score_attempt(case, payload)
        self.assertTrue(row["counted_failure"])
        self.assertEqual(row["jev_choice"], "Calder")
        self.assertGreaterEqual(row["jev_confidence"], 0.90)
        self.assertFalse(row["training_eligible"])
        self.assertEqual(row["bucket"], "QUARANTINE")

    def test_low_confidence_wrong_does_not_count(self) -> None:
        payload = {"chip": _chip("Calder", 0, 0.75), "decided_by": "chip"}
        row = score_attempt(_case(), payload)
        self.assertTrue(row["jev_wrong"])
        self.assertFalse(row["counted_failure"])

    def test_confident_correct_is_not_a_failure(self) -> None:
        payload = {"chip": _chip("Vesper", 1, 0.97), "decided_by": "chip"}
        row = score_attempt(_case(), payload)
        self.assertFalse(row["counted_failure"])
        self.assertFalse(row["jev_wrong"])

    def test_teacher_without_chip_is_not_counted(self) -> None:
        payload = {
            "choice": "Calder",
            "index": 0,
            "confidence": 0.99,
            "escalated": True,
            "decided_by": "teacher",
            "model": "HailoJEV-Qwen3-1.7B-DPO-merged.gguf",
            "device": "cpu (Raspberry Pi 5, llama.cpp)",
        }
        row = score_attempt(_case(), payload)
        self.assertFalse(row["counted_failure"])
        self.assertEqual(row["skip"], "no_forced_jev")

    def test_index_mismatch_is_not_counted(self) -> None:
        chip = _chip("Vesper", 1, 0.99)
        chip["choice"] = "Calder"
        row = score_attempt(_case(), {"chip": chip, "decided_by": "chip"})
        self.assertFalse(row["counted_failure"])
        self.assertEqual(row["skip"], "index_choice_mismatch")

    def test_same_slot_on_flip_is_not_counted(self) -> None:
        base = _case()
        flip = dict(base)
        flip["id"] = "own-short-flip"
        flip["options"] = ["Vesper", "Calder"]
        rows = [
            score_attempt(base, {"chip": _chip("Calder", 0, 0.96)}),
            score_attempt(flip, {"chip": _chip("Vesper", 0, 0.96)}),
        ]
        self.assertTrue(rows[0]["counted_failure"])
        clear_position_bias(rows)
        self.assertFalse(rows[0]["counted_failure"])
        self.assertEqual(rows[0]["skip"], "position_index_bias")

    def test_same_person_across_flip_stays_counted(self) -> None:
        base = _case()
        flip = dict(base)
        flip["id"] = "own-short-flip"
        flip["options"] = ["Vesper", "Calder"]
        rows = [
            score_attempt(base, {"chip": _chip("Calder", 0, 0.95)}),
            score_attempt(flip, {"chip": _chip("Calder", 1, 0.93)}),
        ]
        clear_position_bias(rows)
        self.assertTrue(rows[0]["counted_failure"])
        self.assertTrue(rows[1]["counted_failure"])

    def test_duplicate_is_not_counted_twice(self) -> None:
        payload = {"chip": _chip("Calder", 0, 0.95)}
        first = score_attempt(_case(), payload)
        second = score_attempt(_case(), payload, {first["fingerprint"]})
        self.assertTrue(first["counted_failure"])
        self.assertFalse(second["counted_failure"])
        self.assertEqual(second["skip"], "duplicate")

    def test_numeric_confidence(self) -> None:
        self.assertEqual(numeric_confidence({"confidence": 0.91}), 0.91)
        self.assertEqual(numeric_confidence({"scores": [0.2, 0.8]}), 0.8)
        self.assertIsNone(numeric_confidence({"confidence": "HIGH"}))


class ClientTests(unittest.TestCase):
    def test_refuses_teacher_ports(self) -> None:
        with self.assertRaises(RuntimeError):
            refuse_teacher("http://127.0.0.1:8769/decide")
        with self.assertRaises(RuntimeError):
            refuse_teacher("http://100.126.22.71:8766/v1/decide")

    def test_probe_requires_a_live_chip(self) -> None:
        self.assertFalse(chip_probe_ok({"ok": True, "detail": {"chip_cond": "probe_failed:HTTP 500"}}))
        self.assertFalse(chip_probe_ok({"ok": True}))
        self.assertTrue(
            chip_probe_ok({"ok": True, "detail": {"last_probe": {"ok": True}, "chip_cond": "ready"}})
        )

    def test_post_sends_owner_agent_and_two_options(self) -> None:
        with self.assertRaises(ValueError):
            post_decide("http://127.0.0.1:8771/v1/decide", "q", ["only"])
        captured = {}

        class _Resp:
            def read(self):
                return json.dumps({"choice": "Vesper", "index": 1, "chip": {"choice": "Vesper", "index": 1}}).encode()

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        def fake_urlopen(request, timeout=0):
            captured["url"] = request.full_url
            captured["body"] = json.loads(request.data.decode())
            return _Resp()

        with patch("jevh_owner.client.urllib.request.urlopen", side_effect=fake_urlopen):
            post_decide(
                "http://127.0.0.1:8771/v1/decide",
                "Who owns it?",
                ["Calder", "Vesper"],
                context="named=Vesper bystander=Calder",
            )
        self.assertTrue(captured["url"].endswith("/decide"))
        self.assertEqual(captured["body"]["agent"], AGENT)
        self.assertEqual(captured["body"]["kind"], KIND)
        self.assertEqual(captured["body"]["context"], "named=Vesper bystander=Calder")
        self.assertEqual(len(captured["body"]["options"]), 2)


if __name__ == "__main__":
    unittest.main()
