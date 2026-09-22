# Local Hailo dispatcher

This directory is the PetalWild development foreman. It is not part of the Godot game. `scripts/`, `scenes/`, `data/`, and `shaders/` do not reference it. `.gdignore` keeps Godot from importing it.

The pattern is system-one routing: a small local model returns one JSON object, and ordinary Python validates it. The model is not Jev, it is not an RLCD policy, and its HIGH / MEDIUM / LOW labels are not calibrated probabilities.

## What this machine showed

Probed on 2026-09-22 from this cloud VM:

- PCI bus has no Hailo vendor `0x1e60`
- `/dev/hailo0` is absent
- `hailortcli` is not installed
- no `.hef` files under the usual Hailo directories
- `127.0.0.1:8000` and `127.0.0.1:11434` are closed

`hailo_router_benchmark/latest_results.json` records `not_run` / `no_hailo_device`. No model was selected. No routing accuracy is claimed.

When a Hailo chip and a localhost genai server are both present, the benchmark scores every model that server lists. Preferred names are `Qwen3-1.7B-Instruct` and `Qwen2-1.5B-Instruct-FC`, but the winner is the highest owner accuracy, then JSON validity, then lower latency. Set `HAILO_GENAI_URL` if the server is not on port 8000.

## Run

```bash
cd tools/orchestration
python3 hailo_router_benchmark/run_benchmark.py
python3 -m unittest hailo_router_benchmark.test_router
python3 -m petal_dispatch.service
```

The service listens on `127.0.0.1:8731`.

- `GET /health` returns the probe
- `POST /route` with `{"task":"...","event":"build_failed"}` appends a decision to `runtime/queue.jsonl`
- If the NPU is absent, the decision is `ESCALATE_GROK` with reason `backend_unavailable`

Accepted events: `agent_finished`, `agent_failed`, `build_failed`, `test_failed`, `merge_conflict`, `issue_created`, `performance_regression`, `asset_request`, `visual_qa_failed`.

The model cannot run shell commands. Invalid JSON is retried once. A second failure escalates. LOW confidence escalates. MEDIUM confidence keeps the owner and adds integration review when no secondary was named. Tasks that ask to paste GPL code, change the creative direction, or rewrite the simulation architecture are escalated by the wrapper even if the model is confident.

## Actions

`ROUTE_AGENT`, `ROUTE_ASSET_HUNT`, `ROUTE_QA`, `ROUTE_LICENSE_REVIEW`, `ROUTE_PERFORMANCE`, `ROUTE_INTEGRATION`, `PARALLELISE`, `SERIALISE`, `RETRY`, `REQUEST_REVIEW`, `ESCALATE_GROK`, `BLOCK_PENDING_DEPENDENCY`.
