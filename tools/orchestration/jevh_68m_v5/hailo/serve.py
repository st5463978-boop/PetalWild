"""Local decide HTTP service for the 68M v5 student.

Default bind is 127.0.0.1:8772. Port 8771 is the live Pi service and is
refused unless JEVH_ALLOW_LIVE_PORT=1. A Hailo miss falls back to ONNX when
the ONNX file is present; the response names which backend ran.
"""
from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from hailo.contract import ART, DEV_DECIDE_PORT, LIVE_DECIDE_PORT, ONNX_NAME
from hailo.decide import run_decision
from hailo.runtime import infer_pairs, probe

MODEL_LABEL = "JEV-H-68m-v5"


class BackendUnavailable(RuntimeError):
    pass


def port_allowed(port: int) -> None:
    if port == LIVE_DECIDE_PORT and os.environ.get("JEVH_ALLOW_LIVE_PORT") != "1":
        raise SystemExit(
            f"refusing to bind {LIVE_DECIDE_PORT}: that is the live JEV-H decide port. "
            "Use "
            f"{DEV_DECIDE_PORT}, or set JEVH_ALLOW_LIVE_PORT=1 to replace the live service."
        )


class OnnxPairScorer:
    def __init__(self, path: Path):
        import numpy as np
        import onnxruntime as ort

        self._np = np
        self.path = path
        self.name = f"onnx:{path.name}"
        self.session = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])

    def score_pair(self, ids: list[int], mask: list[int]) -> float:
        np = self._np
        feeds = {
            "input_ids": np.asarray(ids, dtype=np.int64)[None, :],
            "attention_mask": np.asarray(mask, dtype=np.int64)[None, :],
        }
        out = self.session.run(None, feeds)[0]
        return float(np.asarray(out).reshape(-1)[0])


def student_encode(question: str, options: list[str], context: str | None, qtype: str):
    from encode import StudentTok, build_input

    tok_path = os.environ.get("JEVH_TOKENIZER", str(Path(__file__).resolve().parents[1] / "data" / "tokenizer.json"))
    if not hasattr(student_encode, "_tok"):
        student_encode._tok = StudentTok(tok_path)  # type: ignore[attr-defined]
    _, text_a, stexts, _ = build_input(question, options, context, qtype)
    ids, masks, _, _ = student_encode._tok.encode(text_a, stexts)  # type: ignore[attr-defined]
    return list(zip(ids, masks))


def health_body(onnx_path: Path, hef_path: Path) -> dict:
    state = probe()
    return {
        "ok": True,
        "model": MODEL_LABEL,
        "onnx": onnx_path.is_file(),
        "onnx_path": str(onnx_path) if onnx_path.is_file() else "",
        "hef": hef_path.is_file(),
        "hef_path": str(hef_path) if hef_path.is_file() else "",
        "device": state["device"],
        "device_nodes": state["device_nodes"],
        "hailo_platform": state["hailo_platform"],
        "import_error": state["import_error"],
        "live_port_touched": False,
        "hardware_tested": False,
    }


def decide_body(payload: dict, scorer, encode, hef_error: str = "") -> dict:
    question = str(payload.get("question") or "")
    options = payload.get("options")
    if not question or not isinstance(options, list):
        raise ValueError("body needs question and options")
    body = run_decision(
        question,
        [str(option) for option in options],
        encode,
        scorer.score_pair,
        context=payload.get("context"),
        qtype=payload.get("qtype"),
    )
    body["model"] = MODEL_LABEL
    body["backend"] = scorer.name
    observed = hef_error or getattr(scorer, "hef_error", "")
    if observed:
        body["hef_error"] = observed
        body["cpu_fallback"] = True
    return body


def make_handler(onnx_path: Path, hef_path: Path):
    scorer_box: dict = {}

    def scorer():
        if "scorer" in scorer_box:
            return scorer_box["scorer"], scorer_box.get("hef_error", "")
        state = probe()
        cpu = OnnxPairScorer(onnx_path) if onnx_path.is_file() else None
        use_hef = hef_path.is_file() and state["device"] and not state["import_error"]

        class _Scorer:
            def __init__(self) -> None:
                self.name = f"hef:{hef_path.name}" if use_hef else (cpu.name if cpu else "unavailable")
                self.hef_error = ""

            def score_pair(self, ids, mask):
                if use_hef and not self.hef_error:
                    try:
                        return infer_pairs(str(hef_path), [(ids, mask)])[0]
                    except Exception as exc:
                        self.hef_error = f"{type(exc).__name__}: {exc}"
                        self.name = cpu.name if cpu else self.name
                        if cpu is None:
                            raise BackendUnavailable(self.hef_error) from exc
                if cpu is None:
                    raise BackendUnavailable("ONNX file is not on disk and no Hailo-10H HEF can run here")
                return cpu.score_pair(ids, mask)

        if not use_hef and cpu is None:
            raise BackendUnavailable("ONNX file is not on disk and no Hailo-10H HEF can run here")
        scorer_box["scorer"] = _Scorer()
        return scorer_box["scorer"], ""

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt: str, *args) -> None:
            return

        def _send(self, code: int, body: dict) -> None:
            raw = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self) -> None:  # noqa: N802
            if self.path.split("?", 1)[0] in ("/health", "/v1/health"):
                self._send(200, health_body(onnx_path, hef_path))
                return
            self._send(404, {"ok": False, "error": "not found"})

        def do_POST(self) -> None:  # noqa: N802
            path = self.path.split("?", 1)[0]
            if path not in ("/decide", "/v1/decide"):
                self._send(404, {"ok": False, "error": "not found"})
                return
            length = int(self.headers.get("Content-Length") or "0")
            try:
                payload = json.loads(self.rfile.read(length).decode() or "{}")
                model, hef_error = scorer()
                self._send(200, decide_body(payload, model, student_encode, hef_error))
            except BackendUnavailable as exc:
                self._send(503, {"ok": False, "error": str(exc), "cpu_fallback": False})
            except Exception as exc:
                self._send(400, {"ok": False, "error": f"{type(exc).__name__}: {exc}"})

    return Handler


def serve(host: str, port: int, onnx_path: Path, hef_path: Path) -> None:
    port_allowed(port)
    httpd = ThreadingHTTPServer((host, port), make_handler(onnx_path, hef_path))
    print(f"JEV-H 68M v5 decide on http://{host}:{port}/v1/decide", flush=True)
    httpd.serve_forever()


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="CPU/ONNX decide fallback for JEV-H 68M v5")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=DEV_DECIDE_PORT)
    parser.add_argument("--onnx", type=Path, default=ART / ONNX_NAME)
    parser.add_argument("--hef", type=Path, default=ART / "jevh_68m_v5_seq128.hef")
    args = parser.parse_args()
    serve(args.host, args.port, args.onnx, args.hef)


if __name__ == "__main__":
    main()
