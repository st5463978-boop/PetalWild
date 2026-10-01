"""Offline tests. They do not call the live decide path."""

from __future__ import annotations

import json
import random
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ORCH = HERE.parent
if str(ORCH) not in sys.path:
    sys.path.insert(0, str(ORCH))

from jevh_teacher_swarm.analysis.dedupe import near_duplicate  # noqa: E402
from jevh_teacher_swarm.config import load_config  # noqa: E402
from jevh_teacher_swarm.historical import collapse_historical  # noqa: E402
from jevh_teacher_swarm.io_util import read_jsonl  # noqa: E402
from jevh_teacher_swarm.judge import chip_backed, empty_state, judge  # noqa: E402
from jevh_teacher_swarm.prepare import prepare_batch, validate_case  # noqa: E402
from jevh_teacher_swarm.runners.batch_runner import drain  # noqa: E402
from jevh_teacher_swarm.shuffle import mapping_ok, shuffle_options  # noqa: E402
from jevh_teacher_swarm.teachers.batch import authored_cases  # noqa: E402
from jevh_teacher_swarm.verifiers.deterministic.interpret import interpret  # noqa: E402

CFG = load_config()
FAILURES = ORCH / "jevh_clean_core" / "out" / "failures.jsonl"


def _chip(choice: str, index: int, confidence: float = 0.95) -> dict:
    return {
        "choice": choice,
        "index": index,
        "confidence": confidence,
        "scores": [0.05, 0.95] if index else [0.95, 0.05],
        "npu_ms": 47.0,
        "model": "hailojev_student_ettin68m_seq128.hef (352c0f6d)",
    }


def _payload(presented: list[str], chip_index: int, confidence: float = 0.95, *, escalated: bool = False) -> dict:
    chip = _chip(presented[chip_index], chip_index, confidence)
    if escalated:
        return {
            "choice": presented[0],
            "index": 0,
            "scores": [1.0, 0.0],
            "confidence": 0.97,
            "escalated": True,
            "decided_by": "teacher",
            "model": "HailoJEV-Qwen3-1.7B-DPO-merged.gguf",
            "device": "cpu (Raspberry Pi 5, llama.cpp)",
            "threshold": 0.7,
            "latency_ms": 18000.0,
            "shuffle_order": [0, 1],
            "chip": None,
        }
    return {
        "choice": chip["choice"],
        "index": chip_index,
        "scores": chip["scores"],
        "confidence": confidence,
        "escalated": False,
        "decided_by": "chip",
        "model": chip["model"],
        "device": "hailo-10h",
        "threshold": 0.7,
        "latency_ms": 52.0,
        "shuffle_order": list(range(len(presented))),
        "chip": chip,
    }


class PrepareTests(unittest.TestCase):
    def test_batch_verifies_and_shuffles(self) -> None:
        ready, quarantined = prepare_batch(authored_cases())
        self.assertEqual(quarantined, [])
        self.assertGreaterEqual(len(ready), 40)
        presented_slots = set()
        for case in ready:
            self.assertTrue(case["teacher_verifier_agree"])
            self.assertEqual(case["verifier_answer"], interpret(case["rule"], case["facts"]))
            self.assertTrue(mapping_ok(case))
            self.assertFalse(case["training_eligible"])
            self.assertIn(case["partition"], {"TRAIN", "CANARY"})
            presented_slots.add(case["answer_presented_index"])
            self.assertNotIn("too_hard", [option.lower() for option in case["presented_options"]])
        self.assertGreater(len(presented_slots), 1)
        self.assertTrue(any(case["partition"] == "CANARY" for case in ready))
        self.assertTrue(any(case["partition"] == "TRAIN" for case in ready))

    def test_disagreement_is_quarantine(self) -> None:
        case = dict(authored_cases()[0])
        case["teacher_answer"] = "valid" if case["teacher_answer"] == "invalid" else "invalid"
        prepared, reason = validate_case(case)
        self.assertIsNone(prepared)
        self.assertEqual(reason, "teacher_verifier_disagree")

    def test_new_cases_are_not_paraphrases_of_counted_failures(self) -> None:
        failures = read_jsonl(FAILURES)
        ready, _ = prepare_batch(authored_cases())
        hits = []
        for case in ready:
            if case["probe"]:
                continue
            for prior in failures:
                if near_duplicate(case["question"], prior["question"], 0.90, case["verifier_answer"], prior["answer"]):
                    hits.append((case["id"], prior["id"]))
        self.assertEqual(hits, [])


class ShuffleTests(unittest.TestCase):
    def test_mapping_roundtrip(self) -> None:
        rng = random.Random(7)
        for n in range(200):
            width = rng.randint(2, 6)
            options = [f"opt{i}-{n}" for i in range(width)]
            answer = options[rng.randint(0, width - 1)]
            mapping = shuffle_options(options, answer, f"case-{n}-{answer}")
            self.assertTrue(mapping_ok(mapping))
            for presented_index in range(width):
                original_index = mapping["presented_to_original"][presented_index]
                self.assertEqual(mapping["presented_options"][presented_index], options[original_index])


class HistoricalTests(unittest.TestCase):
    def test_clean_core_failures_collapse(self) -> None:
        unique, dupes = collapse_historical(read_jsonl(FAILURES))
        self.assertEqual(
            {row["id"] for row in unique},
            {"src-ttl-under", "apr-over-spend", "can-cache-same-version"},
        )
        self.assertEqual(len(unique) + len(dupes), 23)
        self.assertTrue(all(row["training_eligible"] is False for row in unique))
        self.assertTrue(all(row["counted_unique"] is False for row in dupes))


class JudgeTests(unittest.TestCase):
    def setUp(self) -> None:
        ready, _ = prepare_batch(authored_cases())
        self.case = next(case for case in ready if case["id"] == "ts-token-old")

    def test_teacher_fallback_is_not_a_counted_failure(self) -> None:
        payload = _payload(self.case["presented_options"], 0, escalated=True)
        self.assertFalse(chip_backed(payload))
        row = judge(self.case, payload, empty_state(), CFG)
        self.assertFalse(row["counted_failure"])
        self.assertFalse(row["counted_unique"])
        self.assertIsNone(row["jev_confidence"])
        self.assertEqual(row["skip"], "no_forced_jev")
        self.assertEqual(row["gold"], self.case["verifier_answer"])
        self.assertNotEqual(row["gold"], row["jev_choice"])

    def test_confident_wrong_chip_counts_once(self) -> None:
        presented = self.case["presented_options"]
        gold = self.case["verifier_answer"]
        wrong_index = next(i for i, option in enumerate(presented) if option != gold)
        payload = _payload(presented, wrong_index, 0.96)
        state = empty_state()
        row = judge(self.case, payload, state, CFG)
        self.assertTrue(row["counted_unique"])
        self.assertEqual(row["jev_choice"], presented[wrong_index])
        self.assertNotEqual(row["jev_choice"], gold)
        again = judge(self.case, payload, state, CFG)
        self.assertFalse(again["counted_unique"])
        self.assertEqual(again["skip"], "near_duplicate")

    def test_low_confidence_wrong_does_not_count(self) -> None:
        presented = self.case["presented_options"]
        gold = self.case["verifier_answer"]
        wrong_index = next(i for i, option in enumerate(presented) if option != gold)
        row = judge(self.case, _payload(presented, wrong_index, 0.40), empty_state(), CFG)
        self.assertFalse(row["counted_failure"])
        self.assertEqual(row["skip"], "below_confidence")

    def test_index_mismatch_is_harness(self) -> None:
        presented = self.case["presented_options"]
        payload = _payload(presented, 0, 0.99)
        payload["chip"]["choice"] = presented[1]
        payload["choice"] = presented[1]
        row = judge(self.case, payload, empty_state(), CFG)
        self.assertFalse(row["counted_failure"])
        self.assertEqual(row["bucket"], "QUARANTINE")


class DrainTests(unittest.TestCase):
    def test_drain_writes_buckets_and_does_not_trust_teacher(self) -> None:
        ready, _ = prepare_batch(authored_cases())
        root = Path(self.id().replace(".", "_"))
        # Use a temp dir under /tmp so the package tree stays clean.
        root = Path("/tmp/jevh-swarm-test")
        if root.exists():
            for path in root.rglob("*"):
                if path.is_file():
                    path.unlink()
        from jevh_teacher_swarm.prepare import tree
        from jevh_teacher_swarm.io_util import write_jsonl

        paths = tree(root)
        write_jsonl(paths["pending"], ready[:3])
        write_jsonl(paths["inflight"], [])
        write_jsonl(paths["accepted_failures"], [])
        calls = []

        def post(case):
            calls.append(list(case["presented_options"]))
            return _payload(case["presented_options"], 0, escalated=True)

        summary = drain(CFG, post, health={"chip_cond": "probe_failed:HTTP 500"}, root=root, limit=3)
        self.assertEqual(summary["sent"], 3)
        self.assertEqual(summary["chip_answers"], 0)
        self.assertEqual(len(calls), 3)
        quarantine = read_jsonl(paths["quarantine"])
        self.assertEqual(len(quarantine), 3)
        self.assertTrue(all(row["skip"] == "no_forced_jev" for row in quarantine))
        self.assertEqual(read_jsonl(paths["accepted_failures"]), [])
        self.assertEqual(read_jsonl(paths["pending"]), [])


class ClientTests(unittest.TestCase):
    def test_decide_sends_presented_options(self) -> None:
        from jevh_teacher_swarm.runners.jev_client import decide

        case = prepare_batch(authored_cases())[0][0]
        with patch("jevh_teacher_swarm.runners.jev_client.post_decide", return_value={"ok": True}) as post:
            with patch("jevh_teacher_swarm.runners.jev_client.resolve_decide_url", return_value="http://example/v1/decide"):
                decide(case, 5)
        self.assertEqual(post.call_args.args[2], case["presented_options"])
        body_options = post.call_args.args[2]
        self.assertNotIn(case["verifier_answer"], json.dumps({"context": post.call_args.kwargs["context"]}))
        self.assertIn(case["verifier_answer"], body_options)


if __name__ == "__main__":
    unittest.main()
