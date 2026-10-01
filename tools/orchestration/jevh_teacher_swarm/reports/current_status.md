TOTAL GENERATED: 47
TOTAL SENT TO JEV: 47
QUEUE DEPTH: 0

JEV ACCURACY: n/a
JEV >= .90 CONFIDENT WRONG: 0
JEV >= .95 CONFIDENT WRONG: 0
JEV >= .98 CONFIDENT WRONG: 0

ACCEPTED UNIQUE FAILURES: 3
TARGET = 1000
TARGET REMAINING: 997

TEACHER AGREEMENT RATE: 1.000
QUARANTINE COUNT: 47
DUPLICATE REJECTION RATE: 0.000

P50 LATENCY: n/a
P95 LATENCY: n/a
DECISIONS / SECOND: n/a

CHIP ANSWERS THIS RUN: 0
NO FORCED JEV THIS RUN: 47
WIRE DECIDED_BY: teacher
WIRE MODEL: HailoJEV-Qwen3-1.7B-DPO-merged.gguf
WIRE DEVICE: cpu (Raspberry Pi 5, llama.cpp)
CPU TEACHER MATCHED VERIFIER (not counted): 31
CPU TEACHER DIFFERED (not counted): 16
LATENCY SOURCE: no_chip_latency_this_run
PRIOR CHIP ROWS: 71
PRIOR NPU P50 MS: 45.8
PRIOR NPU P95 MS: 56.6
PRIOR SERVER LATENCY <200ms: 45 p50=52.8
PRIOR SERVER LATENCY >=200ms: 26 p50=15370.2

TOP FAILURE MECHANISMS:
- approval_spend_over n=1 max_conf=0.903 ids=apr-over-spend
- fresh_within_limit n=1 max_conf=0.950 ids=src-ttl-under
- nonauthoritative_not_contradiction n=1 max_conf=0.933 ids=can-cache-same-version

Live decide health model=JEV-H ettin68m student HEF (old, 352c0f6d) + Qwen3 CPU teacher fallback device=hailo-10h (JEV-H student) + cpu teacher hef_sha_prefix=352c0f6d chip_cond=probe_failed:HTTP 500 as of 2026-10-01T09:41:53Z. All 47 decide calls returned decided_by=teacher, chip=null, model=HailoJEV-Qwen3-1.7B-DPO-merged.gguf on cpu (Raspberry Pi 5, llama.cpp). No ettin68m choice was observed, so this batch added no counted failures. The CPU teacher wire choice is not JEV and is not ground truth. The tunnel dropped mid-batch with HTTP 502 then 530; the unfinished cases were sent after rediscovery. Further counted mining is blocked until the HEF probe stops returning HTTP 500. The three unique failures below are the earlier clean-core chip ledger, collapsed so near-duplicates count once.
