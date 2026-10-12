"""Wrapper tests. They do not pretend a missing NPU produced a route."""

from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent))

from petal_dispatch.hailo_backend import (  # noqa: E402
    DECIDE_MODEL,
    choice_from_payload,
    post_decide,
    question_for,
)
from hailo_decide_url import DecideUrlError, resolve_decide_url  # noqa: E402
from petal_dispatch.router import Backend, decide, extract_json  # noqa: E402
from petal_dispatch.schema import parse_decision, prompt_for  # noqa: E402


def _env_without(*names: str) -> dict[str, str]:
    return {k: v for k, v in os.environ.items() if k not in names}


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

    def test_decide_choice_uses_index_and_rejects_a_miss(self) -> None:
        options = ["PETAL_03_JELLY", "PETAL_12_QA"]
        self.assertEqual(choice_from_payload({"index": 1, "choice": "nope"}, options), "PETAL_12_QA")
        self.assertEqual(choice_from_payload({"choice": "B)"}, options), "PETAL_12_QA")
        with self.assertRaises(ValueError):
            choice_from_payload({"choice": "neither"}, options)

    def test_question_keeps_the_task_line(self) -> None:
        text = question_for(prompt_for("Jelly does not squash.", "build_failed"))
        self.assertIn("Jelly does not squash.", text)
        self.assertIn("build_failed", text)
        self.assertNotIn("PETAL_03_JELLY", text)

    def test_decide_model_is_jevh_without_hardcoded_hosts(self) -> None:
        import hailo_decide_url as hdu
        from petal_dispatch import hailo_backend as hb

        self.assertEqual(DECIDE_MODEL, "JEV-H")
        self.assertFalse(hasattr(hdu, "TAILSCALE_DEFAULT"))
        self.assertFalse(hasattr(hdu, "DISCOVERY_URL"))
        self.assertFalse(hasattr(hb, "DEFAULT_DECIDE_URL"))
        self.assertFalse(hasattr(hb, "MAGICDNS_DECIDE_URL"))
        for path in (
            Path(__file__).resolve().parents[2] / "hailo_decide_url.py",
            ROOT / "petal_dispatch" / "hailo_backend.py",
            Path(__file__).resolve(),
        ):
            text = path.read_text(encoding="utf-8")
            self.assertNotRegex(text, r"100\.\d{1,3}\.\d{1,3}\.\d{1,3}")
            self.assertNotRegex(text, r"ntfy\.sh/[A-Za-z0-9][A-Za-z0-9._-]{8,}")

    def test_resolve_fails_when_env_unset(self) -> None:
        env = _env_without("HAILO_DECIDE_URL", "HAILO_DECIDE_DISCOVERY_URL")
        with patch.dict(os.environ, env, clear=True):
            with self.assertRaises(DecideUrlError) as ctx:
                resolve_decide_url()
        msg = str(ctx.exception)
        self.assertIn("HAILO_DECIDE_URL", msg)
        self.assertIn("HAILO_DECIDE_DISCOVERY_URL", msg)
        self.assertIn("no in-tree", msg)

    def test_resolve_uses_hailo_decide_url_when_healthy(self) -> None:
        url = "http://piai-1:8771/v1/decide"
        env = _env_without("HAILO_DECIDE_DISCOVERY_URL")
        env["HAILO_DECIDE_URL"] = url
        with patch.dict(os.environ, env, clear=True):
            with patch("hailo_decide_url._healthy", return_value=True):
                self.assertEqual(resolve_decide_url(), url)
        self.assertIn(":8771/", url)
        self.assertNotIn(":8766", url)

    def test_resolve_uses_discovery_when_url_unset(self) -> None:
        env = _env_without("HAILO_DECIDE_URL")
        env["HAILO_DECIDE_DISCOVERY_URL"] = "https://example.test/discovery"
        with patch.dict(os.environ, env, clear=True):
            with patch("hailo_decide_url.discover_base", return_value="https://tunnel.example"):
                with patch("hailo_decide_url._healthy", return_value=True):
                    self.assertEqual(resolve_decide_url(), "https://tunnel.example/v1/decide")

    def test_resolve_fails_when_discovery_misses_and_url_unset(self) -> None:
        env = _env_without("HAILO_DECIDE_URL")
        env["HAILO_DECIDE_DISCOVERY_URL"] = "https://example.test/discovery"
        with patch.dict(os.environ, env, clear=True):
            with patch("hailo_decide_url.discover_base", return_value=None):
                with self.assertRaises(DecideUrlError):
                    resolve_decide_url()

    def test_post_decide_refreshes_once_when_origin_changes(self) -> None:
        from unittest.mock import patch

        from petal_dispatch import hailo_backend as hb

        calls: list[str] = []

        def fake_once(base_url, question, options, timeout):
            calls.append(base_url)
            if "stale.example" in base_url:
                raise RuntimeError("stale tunnel")
            return {"choice": options[1], "index": 1}

        with (
            patch.object(hb, "_post_decide_once", side_effect=fake_once),
            patch.object(hb, "refresh_decide_url", return_value="http://fresh.example:8771/v1/decide") as refresh,
        ):
            payload = post_decide("http://stale.example:8771/v1/decide", "pick", ["left", "right"], 5.0)
        self.assertEqual(payload["index"], 1)
        self.assertEqual(
            calls,
            ["http://stale.example:8771/v1/decide", "http://fresh.example:8771/v1/decide"],
        )
        refresh.assert_called_once()

    def test_post_decide_does_not_retry_same_origin(self) -> None:
        from unittest.mock import patch

        from petal_dispatch import hailo_backend as hb

        def fake_once(base_url, question, options, timeout):
            raise RuntimeError("still down")

        with (
            patch.object(hb, "_post_decide_once", side_effect=fake_once),
            patch.object(hb, "refresh_decide_url", return_value="http://same.example:8771/v1/decide") as refresh,
        ):
            with self.assertRaises(RuntimeError):
                post_decide("http://same.example:8771/decide", "pick", ["left", "right"], 5.0)
        refresh.assert_called_once()

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
