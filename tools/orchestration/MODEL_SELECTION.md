# Hailo router selection

Date: 2026-09-27

System-1 now uses the trained Qwen3-1.7B DPO CPU decide service (hef-dfc primary, Pi CPU fallback). The Pi Hailo-10H `Qwen3-1.7B.hef` hop is last resort. Do not switch this path to MinoJEV or 0.6B RLCD. Do not recompile the HEF.

HIGH / MEDIUM / LOW from the wrapper are routing labels. DPO `confidence` is a Platt-calibrated probability of the chosen option; log it with each decision.

## Earlier selection (2026-09-22)

Selected model: `Qwen3-1.7B.hef` (`qwen3:1.7b`) on the Pi Hailo-10H, via `hailo-decision`. The 174-task file is not a local bake-off.

