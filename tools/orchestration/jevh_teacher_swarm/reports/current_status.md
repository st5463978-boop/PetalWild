TOTAL GENERATED: 1041
TOTAL SENT TO JEV: 786
QUEUE DEPTH: 0

JEV ACCURACY: 0.510
JEV >= .90 CONFIDENT WRONG: 160
JEV >= .95 CONFIDENT WRONG: 88
JEV >= .98 CONFIDENT WRONG: 43

ACCEPTED UNIQUE FAILURES: 364
TARGET = 1000
TARGET REMAINING: 636

TEACHER AGREEMENT RATE: 1.000
QUARANTINE COUNT: 302
DUPLICATE REJECTION RATE: 0.001

P50 LATENCY: 44.8
P95 LATENCY: 52.0
DECISIONS / SECOND: 8.77

CHIP ANSWERS THIS RUN: 739
NO FORCED JEV THIS RUN: 47
WIRE DECIDED_BY: chip, teacher
WIRE MODEL: HailoJEV-Qwen3-1.7B-DPO-merged.gguf, hailojev_student_ettin68m_seq128.hef (352c0f6d)
WIRE DEVICE: cpu (Raspberry Pi 5, llama.cpp), hailo-10h
CPU TEACHER MATCHED VERIFIER (not counted): 31
CPU TEACHER DIFFERED (not counted): 16
LATENCY SOURCE: this_run_chip
PRIOR CHIP ROWS: 71
PRIOR NPU P50 MS: 45.8
PRIOR NPU P95 MS: 56.6
PRIOR SERVER LATENCY <200ms: 45 p50=52.8
PRIOR SERVER LATENCY >=200ms: 26 p50=15370.2

TOP FAILURE MECHANISMS:
- above_seasonal n=1 max_conf=0.986 ids=w-season-1
- account_quota_hit n=1 max_conf=0.977 ids=w-quota-1
- action_overdue n=1 max_conf=0.794 ids=w-action-1
- aisle_blocked n=1 max_conf=0.716 ids=w-osha-1
- anchor_hold n=1 max_conf=0.912 ids=w-anchor-1
- anvil_too_cold n=1 max_conf=0.951 ids=w-anvil-1
- apple_ripe n=1 max_conf=0.941 ids=w-orchard-1
- approval_spend_over n=1 max_conf=0.903 ids=apr-over-spend
- async_lag_over n=1 max_conf=0.912 ids=w-async-1
- atp_covers_order n=1 max_conf=0.966 ids=w-atp-1

Live decide health model=JEV-H ettin68m student HEF (old, 352c0f6d) + Qwen3 CPU teacher fallback device=hailo-10h (JEV-H student) + cpu teacher hef_sha_prefix=352c0f6d chip_cond=ok. Sent 202 decide calls. A row counts only when the ettin68m chip answer is wrong at confidence >= 0.90 and the mechanism is new. CPU teacher fallbacks are quarantine, not JEV. Wall mined against the live student.
