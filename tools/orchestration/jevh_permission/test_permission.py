"""Offline tests. They do not call decide or the Pi CPU teacher."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ORCH = HERE.parent
if str(ORCH) not in sys.path:
    sys.path.insert(0, str(ORCH))

from jevh_permission.cases import FORBIDDEN_OPTIONS, assert_bank_ok, expected_answer, load_cases
from jevh_permission.mine import COUNT_STOP, chip_blob, run, score_attempt


def _case():
    return {
        "id": "perm-spend-12000-1000",
        "kind": "permission",
        "family": "numeric_limit",
        "question": "Is approval required?",
        "options": ["not_required", "required"],
        "answer": "required",
        "why": "12000 is over 1000.",
        "amount": 12000,
        "limit": 1000,
        "training_eligible": False,
    }


class BankTests(unittest.TestCase):
    def test_bank_follows_the_over_limit_rule(self) -> None:
        cases = load_cases()
        assert_bank_ok(cases)
        self.assertGreaterEqual(len(cases), 40)
        answers = {case["answer"] for case in cases}
        self.assertEqual(answers, {"required", "not_required"})
        for case in cases:
            self.assertEqual(len(case["options"]), 2)
            self.assertFalse(case["training_eligible"])
            self.assertEqual(case["answer"], expected_answer(case["amount"], case["limit"]))
            self.assertEqual(case["family"], "numeric_limit")
            for option in case["options"]:
                self.assertNotIn(option.strip().lower(), FORBIDDEN_OPTIONS)

    def test_both_option_orders_exist(self) -> None:
        cases = load_cases()
        orders = {tuple(case["options"]) for case in cases}
        self.assertIn(("not_required", "required"), orders)
        self.assertIn(("required", "not_required"), orders)
        self.assertEqual(cases[1]["id"].endswith("-flip"), True)
        self.assertEqual(cases[0]["question"], cases[1]["question"])
        self.assertNotEqual(cases[0]["options"], cases[1]["options"])


class ScoreTests(unittest.TestCase):
    def test_confident_wrong_chip_counts(self) -> None:
        payload = {
            "choice": "required",
            "index": 1,
            "escalated": True,
            "decided_by": "teacher",
            "model": "teacher.gguf",
            "chip": {
                "choice": "not_required",
                "index": 0,
                "confidence": 0.94,
                "scores": [0.94, 0.06],
            },
        }
        row = score_attempt(_case(), payload)
        self.assertTrue(row["counted_failure"])
        self.assertEqual(row["jev_choice"], "not_required")
        self.assertEqual(row["jev_source"], "chip")
        self.assertFalse(row["training_eligible"])

    def test_low_confidence_wrong_does_not_count(self) -> None:
        payload = {
            "escalated": False,
            "chip": {"choice": "not_required", "index": 0, "confidence": 0.89, "scores": [0.89, 0.11]},
        }
        row = score_attempt(_case(), payload)
        self.assertTrue(row["jev_wrong"])
        self.assertFalse(row["counted_failure"])

    def test_confident_correct_does_not_count(self) -> None:
        payload = {
            "escalated": False,
            "model": "hailojev_student.hef",
            "device": "hailo-10h",
            "choice": "required",
            "index": 1,
            "confidence": 0.97,
            "scores": [0.03, 0.97],
        }
        row = score_attempt(_case(), payload)
        self.assertEqual(row["jev_source"], "top")
        self.assertFalse(row["jev_wrong"])
        self.assertFalse(row["counted_failure"])

    def test_cpu_teacher_alone_is_not_a_chip_failure(self) -> None:
        payload = {
            "choice": "not_required",
            "index": 0,
            "scores": [0.956, 0.044],
            "confidence": 0.61,
            "model": "HailoJEV-Qwen3-1.7B-DPO-merged.gguf",
            "device": "cpu (Raspberry Pi 5, llama.cpp)",
            "decided_by": "teacher",
            "escalated": True,
            "chip": None,
        }
        blob, source = chip_blob(payload)
        self.assertIsNone(blob)
        self.assertEqual(source, "teacher")
        row = score_attempt(_case(), payload)
        self.assertFalse(row["counted_failure"])
        self.assertEqual(row["skip"], "no_forced_jev")

    def test_index_mismatch_does_not_count(self) -> None:
        payload = {
            "escalated": False,
            "chip": {"choice": "not_required", "index": 1, "confidence": 0.99, "scores": [0.01, 0.99]},
        }
        row = score_attempt(_case(), payload)
        self.assertFalse(row["counted_failure"])
        self.assertEqual(row["skip"], "index_choice_mismatch")

    def test_run_stops_at_20_counted(self) -> None:
        sent = {"n": 0}

        def poster(case: dict) -> dict:
            sent["n"] += 1
            wrong_index = 0 if case["options"][0] != case["answer"] else 1
            return {
                "escalated": False,
                "model": "hailojev_student.hef",
                "device": "hailo-10h",
                "choice": case["options"][wrong_index],
                "index": wrong_index,
                "confidence": 0.95,
                "scores": [0.95, 0.05] if wrong_index == 0 else [0.05, 0.95],
            }

        summary = run(poster=poster, health_fn=lambda: {"ok": True})
        self.assertEqual(summary["counted_failures"], COUNT_STOP)
        self.assertEqual(summary["stop_reason"], "counted_20")
        self.assertEqual(sent["n"], COUNT_STOP)
        self.assertFalse(summary["training_eligible"])

    def test_run_stops_when_chip_is_missing(self) -> None:
        sent = {"n": 0}

        def poster(case: dict) -> dict:
            sent["n"] += 1
            return {
                "choice": "not_required",
                "index": 0,
                "confidence": 0.99,
                "scores": [0.99, 0.01],
                "escalated": True,
                "decided_by": "teacher",
                "device": "cpu",
                "model": "teacher.gguf",
                "chip": None,
            }

        summary = run(poster=poster, health_fn=lambda: {"ok": True})
        self.assertEqual(sent["n"], 1)
        self.assertEqual(summary["counted_failures"], 0)
        self.assertEqual(summary["stop_reason"], "chip_unavailable")


if __name__ == "__main__":
    unittest.main()
