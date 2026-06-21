#!/usr/bin/env bash
# Exit 0 if the unified file was generated within MAX_AGE seconds, else 1.
# Usage: check_fresh.sh <acm_export.json> [max_age_seconds]
set -euo pipefail
FILE="${1:?file}"; MAX_AGE="${2:-90}"
python3 - "$FILE" "$MAX_AGE" <<'PY'
import json, sys, time
file, max_age = sys.argv[1], int(sys.argv[2])
try:
    with open(file) as fh: data = json.load(fh)
except Exception as e:
    print(f"unreadable: {e}"); sys.exit(1)
gen = data.get("generated_irl")
if not isinstance(gen, (int, float)):
    print("no generated_irl"); sys.exit(1)
age = time.time() - gen
print(f"age={age:.0f}s (max={max_age}s)")
sys.exit(0 if age <= max_age else 1)
PY
