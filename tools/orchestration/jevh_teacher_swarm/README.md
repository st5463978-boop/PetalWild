# JEV-H teacher swarm

Queue, runner, and status for atomic decisions sent to the live JEV-H decide path.

The clean-core miner stays the scorer and the decide client. This package does not train, compile a HEF, or replace the chip model.

```bash
cd tools/orchestration
python3 -m jevh_teacher_swarm check
python3 -m jevh_teacher_swarm generate
python3 -m jevh_teacher_swarm run
python3 -m unittest jevh_teacher_swarm.test_swarm jevh_clean_core.test_clean_core
```

A counted failure is a new mechanism where the ettin68m chip (`352c0f6d`) is wrong at confidence >= 0.90. The deterministic interpreter has to agree with the teacher claim first. CPU-teacher fallbacks, index bugs, and near-duplicates do not count. JEV's choice is never the label.

`TRAIN` in the queue means "not in the held-out canary slice". `training_eligible` stays false.
