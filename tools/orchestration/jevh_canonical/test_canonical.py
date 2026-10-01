"""Offline tests for the canonical-match miner. They do not call live decide."""

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

from jevh_canonical import AGENT, POST_KIND
from jevh_canonical.cases import EXCLUDED_FAMILIES, FAMILY, assert_bank_ok, gold, load_cases
from jevh_canonical.client import chip_block_reason, post_decide
from jevh_canonical.mine import drop_position_bias
from jevh_canonical.score import fingerprint, map_choice, numeric_confidence, score_attempt


def _chip(choice: str, index: int, confidence: float) -> dict:
    return {
        "choice": choice,
        "index": index,
        "scores": [0.05, 0.95] if index else [0.95, 0.05],
        "confidence": confidence,
        "npu_ms": 48.0,
        "model": "hailojev_student_ettin68m_seq128.hef",
    }


class BankTests(unittest.TestCase):
    def test_bank_is_canonical_match_only(self) -> None:
        cases = load_cases()
        assert_bank_ok(cases)
        self.assertGreaterEqual(len(cases), 20)
        self.assertEqual({case["family"] for case in cases}, {FAMILY})
        self.assertIn("modulo-slot", EXCLUDED_FAMILIES)
        for case in cases:
            self.assertFalse(case["training_eligible"])
            self.assertEqual(len(case["options"]), 2)
            self.assertIn(case["answer"], case["options"])
            self.assertNotIn(case["family"], EXCLUDED_FAMILIES)

    def test_gold_rule(self) -> None:
        self.assertEqual(gold("4", "4", "stale-client"), "consistent")
        self.assertEqual(gold("4", "4", "non-canonical"), "consistent")
        self.assertEqual(gold("4", "4", None), "consistent")
        self.assertEqual(gold("4", "9", "stale-client"), "contradicted")
        self.assertEqual(gold("4", "9", None), "contradicted")
        for case in load_cases():
            mark = None
            if "extra_marked=stale-client" in case["context"]:
                mark = "stale-client"
            elif "extra_marked=non-canonical" in case["context"]:
                mark = "non-canonical"
            canonical = case["context"].split()[0].split("=", 1)[1]
            replica = case["context"].split()[1].split("=", 1)[1]
            self.assertEqual(case["answer"], gold(canonical, replica, mark), case["id"])

    def test_fingerprints_are_unique(self) -> None:
        cases = load_cases()
        prints = [fingerprint(case) for case in cases]
        self.assertEqual(len(prints), len(set(prints)))


class ScoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.case = load_cases()[0]
        self.assertEqual(self.case["answer"], "consistent")

    def test_confident_wrong_chip_counts(self) -> None:
        wrong = self.case["options"].index("contradicted")
        payload = {
            "choice": "consistent",
            "index": self.case["options"].index("consistent"),
            "escalated": True,
            "decided_by": "teacher",
            "model": "teacher.gguf",
            "device": "cpu",
            "confidence": 0.99,
            "chip": _chip("contradicted", wrong, 0.93),
        }
        row = score_attempt(self.case, payload)
        self.assertTrue(row["counted_failure"])
        self.assertEqual(row["jev_choice"], "contradicted")
        self.assertGreaterEqual(row["jev_confidence"], 0.90)
        self.assertFalse(row["training_eligible"])
        self.assertEqual(row["bucket"], "QUARANTINE")

    def test_low_confidence_wrong_does_not_count(self) -> None:
        wrong = self.case["options"].index("contradicted")
        payload = {"chip": _chip("contradicted", wrong, 0.89), "escalated": False}
        row = score_attempt(self.case, payload)
        self.assertTrue(row["jev_wrong"])
        self.assertFalse(row["counted_failure"])

    def test_confident_correct_is_not_a_failure(self) -> None:
        right = self.case["options"].index("consistent")
        payload = {"chip": _chip("consistent", right, 0.96)}
        row = score_attempt(self.case, payload)
        self.assertFalse(row["counted_failure"])
        self.assertFalse(row["jev_wrong"])

    def test_teacher_without_chip_is_not_counted(self) -> None:
        payload = {
            "choice": "contradicted",
            "index": 0,
            "confidence": 0.98,
            "escalated": True,
            "decided_by": "teacher",
            "device": "cpu (Raspberry Pi 5, llama.cpp)",
            "model": "HailoJEV-Qwen3-1.7B-DPO-merged.gguf",
            "chip": None,
        }
        row = score_attempt(self.case, payload)
        self.assertFalse(row["counted_failure"])
        self.assertEqual(row["skip"], "no_forced_jev")
        self.assertIsNone(row["model"])

    def test_index_mismatch_is_not_counted(self) -> None:
        payload = {"chip": _chip("contradicted", 0, 0.99)}
        payload["chip"]["choice"] = "consistent"
        row = score_attempt(self.case, payload)
        self.assertFalse(row["counted_failure"])
        self.assertEqual(row["skip"], "index_choice_mismatch")

    def test_same_slot_on_flipped_options_is_position_bias(self) -> None:
        rows = [
            {
                "question": "Same facts.",
                "options": ["contradicted", "consistent"],
                "answer": "consistent",
                "jev_index": 0,
                "jev_choice": "contradicted",
                "counted_failure": True,
                "skip": None,
                "bucket": "QUARANTINE",
            },
            {
                "question": "Same facts.",
                "options": ["consistent", "contradicted"],
                "answer": "consistent",
                "jev_index": 0,
                "jev_choice": "consistent",
                "counted_failure": False,
                "skip": None,
                "bucket": "CANARY-EVAL",
            },
        ]
        drop_position_bias(rows)
        self.assertFalse(rows[0]["counted_failure"])
        self.assertEqual(rows[0]["skip"], "position_bias")

    def test_same_choice_text_on_both_orders_stays_counted(self) -> None:
        rows = [
            {
                "question": "Same facts.",
                "options": ["contradicted", "consistent"],
                "answer": "consistent",
                "jev_index": 0,
                "jev_choice": "contradicted",
                "counted_failure": True,
                "skip": None,
            },
            {
                "question": "Same facts.",
                "options": ["consistent", "contradicted"],
                "answer": "consistent",
                "jev_index": 1,
                "jev_choice": "contradicted",
                "counted_failure": True,
                "skip": None,
            },
        ]
        drop_position_bias(rows)
        self.assertTrue(all(row["counted_failure"] for row in rows))

    def test_duplicate_is_not_counted_twice(self) -> None:
        wrong = self.case["options"].index("contradicted")
        payload = {"chip": _chip("contradicted", wrong, 0.94)}
        first = score_attempt(self.case, payload)
        second = score_attempt(self.case, payload, {first["fingerprint"]})
        self.assertTrue(first["counted_failure"])
        self.assertFalse(second["counted_failure"])
        self.assertEqual(second["skip"], "duplicate")

    def test_map_choice_never_defaults_to_zero(self) -> None:
        mapped = map_choice({"choice": "neither"}, ["consistent", "contradicted"])
        self.assertFalse(mapped["ok"])
        self.assertNotEqual(mapped.get("option"), "consistent")

    def test_numeric_confidence(self) -> None:
        self.assertEqual(numeric_confidence({"confidence": 0.91}), 0.91)
        self.assertEqual(numeric_confidence({"scores": [0.2, 0.8]}), 0.8)
        self.assertIsNone(numeric_confidence({"confidence": "HIGH"}))


class ClientTests(unittest.TestCase):
    def test_chip_block_reason(self) -> None:
        blocked = {
            "detail": {
                "chip_cond": "probe_failed:HTTP 500",
                "last_probe": {"ok": False, "code": 500},
            }
        }
        self.assertIn("probe_failed", chip_block_reason(blocked) or "")
        ready = {"detail": {"last_probe": {"ok": True}, "chip_cond": "ok"}}
        self.assertIsNone(chip_block_reason(ready))

    def test_post_sends_adversarial_canonical_agent(self) -> None:
        captured = {}

        class _Resp:
            def read(self):
                return json.dumps({"choice": "consistent", "index": 1, "chip": {}}).encode()

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        def fake_urlopen(request, timeout=0):
            captured["url"] = request.full_url
            captured["body"] = json.loads(request.data.decode())
            return _Resp()

        with patch("jevh_canonical.client.urllib.request.urlopen", side_effect=fake_urlopen):
            post_decide(
                "https://discovery.example/v1/decide",
                "Canonical session is 4. Replica session is 4. Is canonical state contradicted?",
                ["contradicted", "consistent"],
                context="canonical=4 replica=4 extra=1 extra_marked=stale-client",
            )
        self.assertTrue(captured["url"].endswith("/decide"))
        self.assertEqual(captured["body"]["agent"], AGENT)
        self.assertEqual(captured["body"]["kind"], POST_KIND)
        self.assertEqual(captured["body"]["agent"], "jev-cursor-canonical")
        self.assertGreaterEqual(len(captured["body"]["options"]), 2)
        self.assertIn("context", captured["body"])


if __name__ == "__main__":
    unittest.main()
