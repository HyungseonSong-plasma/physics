#!/usr/bin/env bash
set -euo pipefail
ev="$RUNNER_TEMP/physics-evidence"
root="$PWD"
# Identical unified mesh and executable for baseline and candidate.
kinds=(baseline conformal)
mkdir "$RUNNER_TEMP/old-assets"
for file in input.i maxwell.i chemistry.json; do git show 33195c79338b0597b462800109b81d6fbe75c932:assets/$file >"$RUNNER_TEMP/old-assets/$file"; done
opts=(--network none --workdir /case --entrypoint /bin/bash --user 0:0
  --env OXYGEN_RESEARCH_400=1 --env OXYGEN_RESEARCH_FULL24=0 --env OXYGEN_RESEARCH_EI2738_FORMULA=0 --env OXYGEN_RESEARCH_QUICK_5MIN=0
  --mount "type=bind,src=$root,dst=/workspace,readonly")
args=(Executioner/num_steps=1 Outputs/file_base=/evidence/fields/parent Outputs/exodus=true Outputs/csv=true Outputs/time_step_interval=1 'Outputs/execute_on=INITIAL TIMESTEP_END' Outputs/checkpoint=false)
for kind in "${kinds[@]}"; do
  out="$ev/$kind"; mkdir -p "$out/fields"
  for phase in check solve; do
    case_dir="$RUNNER_TEMP/flat-$kind-$phase"
    mkdir "$case_dir"
    cp -a assets "$case_dir/assets"
    if test "$kind" = baseline; then
      for file in input.i maxwell.i chemistry.json; do cp "$RUNNER_TEMP/old-assets/$file" "$case_dir/assets/$file"; done
    else
      test ! -e "$case_dir/assets/maxwell.msh"
      test "$(git hash-object "$case_dir/assets/mesh.msh")" = c8967084bdaace3c4178f364b6f402db2b1358a5
    fi
    test ! -e "$case_dir/.jitcache"
    extra=()
    if test "$phase" = check; then extra=(--check-input); limit=480; log=newonly-check-input.log; else limit=1800; log=newonly-one-step.log; fi
    timeout "$limit" docker run --rm "${opts[@]}" -v "$case_dir:/case" -v "$out:/evidence" "$BASE_IMAGE" -lc '
      set -euo pipefail
      source /environment
      export LD_LIBRARY_PATH=/workspace/app/test/lib:/workspace/app/lib:${LD_LIBRARY_PATH:-}
      exec /workspace/app/physics-opt "$@"
    ' physics-opt "${extra[@]}" -i assets/input.i "${args[@]}" 2>&1 | tee "$out/$log"
    if test "$phase" = check; then grep -q 'Syntax OK' "$out/$log"; fi
  done
  docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$out:/evidence" -v "$root/tests/mesh:/scripts:ro" "$BASE_IMAGE" -lc 'source /environment; python3 /scripts/verify-flat.py /evidence'
done
# Verify declared SCCM area against actual geometry and conservative feed.
python3 - "$ev" <<'PY'
import csv, math, pathlib, sys
root=pathlib.Path(sys.argv[1])
for kind in ("baseline","conformal"):
    with (root/kind/"fields/parent.csv").open() as f:
        rows=list(csv.DictReader(f))
    for row in rows:
        area=float(row["neutral_inlet_area"])
        mdot=float(row["neutral_inlet_mdot"])
        parts=sum(float(row["neutral_inlet_mdot_"+s]) for s in ("O2","O2s","O","Os"))
        assert math.isclose(area,0.05954574715614091,rel_tol=1e-10),area
        assert math.isclose(mdot,4.758967769568476e-6,rel_tol=1e-12),mdot
        assert math.isclose(parts,mdot,rel_tol=1e-12),(parts,mdot)
print("SOLVED_NEUTRAL_SCCM_FEED_AND_GEOMETRY_PASS")
PY
# Negative control: incomplete inlet fraction must fail native construction.
bad="$RUNNER_TEMP/flat-neutral-negative"
mkdir "$bad"; cp -a assets "$bad/assets"
sed -i "s/neutral_inlet_fractions = '.*/neutral_inlet_fractions = '0.5 0 0 0'/" "$bad/assets/input.i"
set +e
timeout 480 docker run --rm "${opts[@]}" -v "$bad:/case" "$BASE_IMAGE" -lc '
  source /environment
  export LD_LIBRARY_PATH=/workspace/app/test/lib:/workspace/app/lib:${LD_LIBRARY_PATH:-}
  exec /workspace/app/physics-opt "$@"
' physics-opt --check-input -i assets/input.i >"$ev/neutral-negative.log" 2>&1
rc=$?
set -e
test "$rc" -ne 0 && test "$rc" -ne 124
grep -q "Invalid solved neutral mixture" "$ev/neutral-negative.log"
echo SOLVED_NEUTRAL_NEGATIVE_PASS
# Exact projection: only species metadata mass columns and explanatory comments change.
python3 - <<'PY'
from pathlib import Path
def rows(path):
    return [l.split() for l in Path(path).read_text().splitlines() if l.strip() and not l.lstrip().startswith("#")]
old=rows("assets/neutral_transport.txt")
new=rows("assets/neutral_transport_aliases.txt")
assert len(old)==len(new)
for a,b in zip(old,new):
    assert b==([a[0],a[1],a[3]] if a[0]=="species" else a),(a,b)
print("NV_COLLISION_ALIAS_PROJECTION_PASS")
PY
badnv="$RUNNER_TEMP/flat-nv-negative"
mkdir "$badnv"; cp -a assets "$badnv/assets"
sed -i "s/neutral_collision_file = 'neutral_transport_aliases.txt'/neutral_collision_file = 'neutral_transport.txt'/" "$badnv/assets/input.i"
set +e
timeout 480 docker run --rm "${opts[@]}" -v "$badnv:/case" "$BASE_IMAGE" -lc '
  source /environment
  export LD_LIBRARY_PATH=/workspace/app/test/lib:/workspace/app/lib:${LD_LIBRARY_PATH:-}
  exec /workspace/app/physics-opt "$@"
' physics-opt --check-input -i assets/input.i >"$ev/nv-negative.log" 2>&1
rc=$?
set -e
test "$rc" -ne 0 && test "$rc" -ne 124
grep -q "External molar masses require alias-only species rows" "$ev/nv-negative.log"
echo NV_TRANSPORT_NEGATIVE_PASS
test "$(sha256sum app/physics-opt | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$ev/executable.sha256")"
if test "${#kinds[@]}" -eq 2; then
  docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$ev:/evidence" -v "$root/tests/mesh:/scripts:ro" "$BASE_IMAGE" -lc 'source /environment; python3 /scripts/compare-unified.py /evidence'
fi
# Only publish after the native and field gates pass.
mkdir -p "$RUNNER_TEMP/physics-exodus"
docker run --rm --network none --entrypoint /bin/bash --user 0:0 \
  -v "$ev/conformal:/evidence:ro" -v "$root/tests/mesh:/scripts:ro" \
  -v "$RUNNER_TEMP/physics-exodus:/results" "$BASE_IMAGE" -lc 'source /environment; python3 /scripts/verify-exodus.py /evidence/fields /results'
echo NEW_ONLY_POISSON_MAXWELL_BOUNDED_PASS
