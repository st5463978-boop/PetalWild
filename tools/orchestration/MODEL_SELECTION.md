# Hailo router selection

Date: 2026-09-29

Selected model: JEV-H (ettin68m student HEF) on the Pi Hailo-10H, port 8771.

Live decide is JEV-H, not the Qwen3 chat decide service on port 8766. `HAILO_DECIDE_URL` overrides when set. With no env, resolve from `https://ntfy.sh/jevh-decide-05923aed092556ed/raw?poll=1&since=latest` (last `https://` line, health-checked). Else Tailscale `http://100.126.22.71:8771/v1/decide`. MagicDNS `http://piai-1:8771/v1/decide` is the same Pi. Health is `GET /health` (also `/v1/health`). A choice is `POST /v1/decide` (also `/decide`) with `question` and `options` (at least two). The client waits 75s. Do not hardcode a trycloudflare host. Do not recompile the HEF. The 174-task file is not a local bake-off.

HIGH / MEDIUM / LOW from the model are routing labels. They have not been calibrated against outcomes.
