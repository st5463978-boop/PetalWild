TOTAL GENERATED: 47
TOTAL SENT TO JEV: 0
QUEUE DEPTH: 47

JEV ACCURACY: n/a
JEV >= .90 CONFIDENT WRONG: 0
JEV >= .95 CONFIDENT WRONG: 0
JEV >= .98 CONFIDENT WRONG: 0

ACCEPTED UNIQUE FAILURES: 3
TARGET = 1000
TARGET REMAINING: 997

TEACHER AGREEMENT RATE: 1.000
QUARANTINE COUNT: 0
DUPLICATE REJECTION RATE: 0.000

P50 LATENCY: n/a
P95 LATENCY: n/a
DECISIONS / SECOND: n/a

CHIP ANSWERS THIS RUN: 0
NO FORCED JEV THIS RUN: 0
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

Queue is prepared. No decide call has been made in this run yet. Unique failures below are the clean-core chip ledger collapsed by mechanism, not new answers. Pending depth is the verified batch only. The high watermark blocks extra filler; the queue is not padded to the 2500 target with unverified rows.
