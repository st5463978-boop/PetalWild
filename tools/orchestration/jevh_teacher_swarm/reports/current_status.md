TOTAL GENERATED: 479
TOTAL SENT TO JEV: 365
QUEUE DEPTH: 0

JEV ACCURACY: 0.509
JEV >= .90 CONFIDENT WRONG: 70
JEV >= .95 CONFIDENT WRONG: 38
JEV >= .98 CONFIDENT WRONG: 16

ACCEPTED UNIQUE FAILURES: 158
TARGET = 1000
TARGET REMAINING: 842

TEACHER AGREEMENT RATE: 1.000
QUARANTINE COUNT: 161
DUPLICATE REJECTION RATE: 0.002

P50 LATENCY: 44.7
P95 LATENCY: 52.6
DECISIONS / SECOND: 8.39

CHIP ANSWERS THIS RUN: 318
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
- approval_spend_over n=1 max_conf=0.903 ids=apr-over-spend
- async_lag_over n=1 max_conf=0.912 ids=w-async-1
- atp_covers_order n=1 max_conf=0.966 ids=w-atp-1
- audience_exact n=1 max_conf=0.862 ids=w-audience-1
- avs_mismatch n=1 max_conf=0.865 ids=w-avs-0
- az_capacity_short n=1 max_conf=0.767 ids=w-az-1
- backup_older_than_rpo n=1 max_conf=0.931 ids=w-backup-1

Live decide health model=JEV-H ettin68m student HEF (old, 352c0f6d) + Qwen3 CPU teacher fallback device=hailo-10h (JEV-H student) + cpu teacher hef_sha_prefix=352c0f6d chip_cond=ok. Sent 316 decide calls. A row counts only when the ettin68m chip answer is wrong at confidence >= 0.90 and the mechanism is new. CPU teacher fallbacks are quarantine, not JEV. Wall mined against the live student.
