#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
BASELINE=$(realpath "${1:?Pass original project directory}")
CANDIDATE=$(realpath "${2:?Pass candidate project directory}")
GODOT=${GODOT:-godot}
mkdir -p "$ROOT/runtime/config" "$ROOT/runtime/cache" "$ROOT/runtime/data"
export XDG_CONFIG_HOME="$ROOT/runtime/config" XDG_CACHE_HOME="$ROOT/runtime/cache" XDG_DATA_HOME="$ROOT/runtime/data"
run() {
  local build=$1 project=$2 script=$3 name=$4 flag=${5:-}
  "$GODOT" --headless --path "$project" --script "$ROOT/bootstrap.gd" -- \
    --effects-harness="$ROOT/$script" --effects-out="$ROOT/$build-$name.json" $flag \
    > "$ROOT/$build-$name.log" 2>&1
  if grep -E 'SCRIPT ERROR|^ERROR:|\] FAIL ' "$ROOT/$build-$name.log"; then
    echo "QA failed: $build-$name" >&2; return 1
  fi
  test -s "$ROOT/$build-$name.json"
}
for build in baseline candidate; do
  project=$BASELINE; flag=""
  if [ "$build" = candidate ]; then project=$CANDIDATE; flag=--candidate; fi
  run "$build" "$project" effects_counts.gd counts "$flag"
  run "$build" "$project" effects_signature.gd signature
  run "$build" "$project" bullet_collision.gd collision
  run "$build" "$project" zombie_geometry.gd geometry
done
run candidate "$CANDIDATE" pool_teardown.gd teardown
python3 "$ROOT/compare_geometry.py"
python3 - "$ROOT" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1]);a=json.loads((root/'baseline-signature.json').read_text());b=json.loads((root/'candidate-signature.json').read_text())
report={k:{'appearance_parameters_identical':a[k]==b[k]} for k in a}
(root/'signature-comparison.json').write_text(json.dumps(report,indent=2))
assert all(v['appearance_parameters_identical'] for v in report.values()),report
for name in ['baseline-counts','candidate-counts','baseline-collision','candidate-collision','candidate-teardown']:
    assert json.loads((root/(name+'.json')).read_text())['result']=='PASS',name
print('PASS: structural, appearance, combat, geometry and lifecycle checks; no FPS claim')
PY
