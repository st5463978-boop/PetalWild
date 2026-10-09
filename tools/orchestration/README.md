# Local Hailo dispatcher

This directory is the PetalWild development foreman. It is not part of the Godot game. `scripts/`, `scenes/`, `data/`, and `shaders/` do not reference it. `.gdignore` keeps Godot from importing it.

System-1 routing calls JEV-H on the Pi (port 8771), not the Qwen3 chat decide service on port 8766. With no `HAILO_DECIDE_URL`, the client resolves the live tunnel from `https://ntfy.sh/jevh-decide-05923aed092556ed/raw?poll=1&since=latest` (last `https://` line). After discovery fails: existing `HAILO_DECIDE_URL` if set, then Tailscale `http://100.126.22.71:8771/v1/decide`. MagicDNS `http://piai-1:8771/v1/decide` is the same service. `GET /health` (also `/v1/health`) should report JEV-H on Hailo-10H. `POST /v1/decide` (also `/decide`) takes `{"question","options"}` with at least two options. The client waits 75s. After a failed decide it refreshes the address once and retries once if the origin changed. The wrapper maps `choice` / `index` onto a lane. No auth. HIGH / MEDIUM / LOW labels are not calibrated probabilities. Set `HAILO_DECIDE_URL` to override. Do not hardcode a trycloudflare host.

## What this machine showed

Probed on 2026-09-22 from this cloud VM:

- PCI bus has no Hailo vendor `0x1e60`
- `/dev/hailo0` is absent
- `hailortcli` is not installed
- no `.hef` files under the usual Hailo directories
- `127.0.0.1:8000` and `127.0.0.1:11434` are closed

`hailo_router_benchmark/latest_results.json` records `not_run` / `no_hailo_device`. No model was selected. No routing accuracy is claimed.

`python3 -m petal_dispatch.hailo_backend` from this directory probes `GET /health` and one `POST /decide` against the default tunnel. The benchmark does not rank local models.

JEV-H-trading (offline paper-only student, no HEF / no Pi / no broker) lives in `jevh_trading/`.

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
