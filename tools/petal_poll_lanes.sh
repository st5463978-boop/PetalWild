#!/usr/bin/env bash
# Poll campaign lane branches. Writes data/campaign_status.json.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
git fetch origin --prune >/dev/null 2>&1 || true
python3 - <<'PY'
import json, subprocess, datetime
from pathlib import Path
root = Path(__file__).resolve().parent.parent if False else Path(".")
lanes_path = Path("data/campaign_lanes.json")
status_path = Path("data/campaign_status.json")
spec = json.loads(lanes_path.read_text())
baseline = subprocess.check_output(["git", "rev-parse", spec["tag"]], text=True).strip()
lanes = {}
landed = 0
for row in spec["lanes"]:
    branch = row["branch"]
    probe = subprocess.run(
        ["git", "ls-remote", "--heads", "origin", branch],
        capture_output=True, text=True, check=False,
    )
    line = probe.stdout.strip()
    present = bool(line)
    commit = line.split()[0] if present else ""
    status = "waiting"
    if present:
        status = "landed"
        landed += 1
        subprocess.run(["git", "fetch", "origin", branch], check=False, capture_output=True)
    lanes[row["id"]] = {
        "branch": branch,
        "present": present,
        "commit": commit,
        "status": status,
        "name": row["name"],
    }
payload = {
    "checked_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "baseline_commit": baseline,
    "baseline_tag": spec["tag"],
    "landed": landed,
    "needed": len(spec["lanes"]),
    "complete": landed >= len(spec["lanes"]),
    "lanes": lanes,
}
status_path.write_text(json.dumps(payload, indent=2) + "\n")
print("campaign poll  %d/%d  complete=%s" % (landed, payload["needed"], payload["complete"]))
for id_, row in lanes.items():
    mark = row["commit"][:7] if row["present"] else "--------"
    print("  %s  %s  %s  %s" % (id_, row["status"].ljust(8), mark, row["branch"]))
PY
