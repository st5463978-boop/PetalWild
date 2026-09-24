# Hailo router selection

Date: 2026-09-22

Selected model: `Qwen3-1.7B.hef` (`qwen3:1.7b`) on the Pi Hailo-10H, via `hailo-decision`.

`HAILO_DECIDE_URL` defaults to `https://fibre-especially-theaters-aerospace.trycloudflare.com`. Tailscale `http://100.126.22.71:8766` is an on-tailnet override only. Health is `GET /health`. A choice is `POST /decide` with `question` and `options` (at least two). The client waits 75s. Do not switch this path to MinoJEV, 0.6B RLCD, or a local CPU Qwen. Do not recompile the HEF. The 174-task file is not a local bake-off.

HIGH / MEDIUM / LOW from the model are routing labels. They have not been calibrated against outcomes.
