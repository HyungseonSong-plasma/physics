#!/usr/bin/env bash
set -euo pipefail
ev="$RUNNER_TEMP/physics-evidence"
root="$PWD"
kinds=(candidate)
if test "$GITHUB_REF" = refs/heads/feature/parent-exodus; then
  kinds=(baseline candidate candidate_rf_capture)
  git show 33195c79338b0597b462800109b81d6fbe75c932:assets/input.i >"$RUNNER_TEMP/baseline-input.i"
  # Match the intentional momentum model change in the A/B reference.
  # Extract the exact two canonical blocks; historical Git input stays intact.
  python3 - "$RUNNER_TEMP/baseline-input.i" <<'PY'
import re,sys
from pathlib import Path
candidate=Path("assets/input.i").read_text()
p=Path(sys.argv[1])
baseline=p.read_text()
blocks=[]
for var,axis in (("u","x"),("v","y")):
    pattern=rf"(?m)^  \[{var}_momentum_time\]\n(?:(?!^  \[).+\n)*^  \[\]\n"
    matches=re.findall(pattern,candidate)
    assert len(matches)==1,(var,len(matches))
    block=matches[0]
    assert "type = WCNSFVMomentumTimeDerivative" in block
    assert f"variable = {var}" in block and f"momentum_component = {axis}" in block
    assert "rho = rho_neutral" in block and "drho_dt = drho_neutral_dt" in block
    assert f"[{var}_momentum_time]" not in baseline
    blocks.append(block)
assert baseline.count("  [u_advection]\n")==1
assert "scheme = implicit-euler" in baseline and "scheme = implicit-euler" in candidate
p.write_text(baseline.replace("  [u_advection]\n","".join(blocks)+"\n  [u_advection]\n"))
print("MATCHED_TRANSIENT_MOMENTUM_BASELINE_PASS")
PY
fi
opts=(--network none --workdir /case --entrypoint /bin/bash --user 0:0
  --env OXYGEN_RESEARCH_400=1 --env OXYGEN_RESEARCH_FULL24=0 --env OXYGEN_RESEARCH_EI2738_FORMULA=0 --env OXYGEN_RESEARCH_QUICK_5MIN=0
  --mount "type=bind,src=$root,dst=/workspace,readonly")
args=(Executioner/num_steps=1 Outputs/file_base=/evidence/fields/parent Outputs/exodus=true Outputs/csv=true Outputs/time_step_interval=1 'Outputs/execute_on=INITIAL TIMESTEP_END' Outputs/checkpoint=false)

for kind in "${kinds[@]}"; do
  out="$ev/$kind"; mkdir -p "$out/fields"
  for phase in check solve; do
    case_dir="$RUNNER_TEMP/parent-exodus-$kind-$phase"
    mkdir "$case_dir"; cp -a assets "$case_dir/assets"
    if test "$kind" = baseline; then cp "$RUNNER_TEMP/baseline-input.i" "$case_dir/assets/input.i"; fi
    test ! -e "$case_dir/assets/maxwell.msh"
    extra=()
    if test "$phase" = check; then extra=(--check-input); limit=480; log=newonly-check-input.log; else limit=1800; log=newonly-one-step.log; fi
    if test "$kind" = candidate_rf_capture; then extra+=('MultiApps/maxwell_t6/cli_args=Outputs/exodus=true;Outputs/csv=false'); fi
    timeout "$limit" docker run --rm "${opts[@]}" -v "$case_dir:/case" -v "$out:/evidence" "$BASE_IMAGE" -lc '
      set -euo pipefail
      source /environment
      export LD_LIBRARY_PATH=/workspace/app/test/lib:/workspace/app/lib:${LD_LIBRARY_PATH:-}
      exec /workspace/app/physics-opt "$@"
    ' physics-opt "${extra[@]}" -i assets/input.i /workspace/tests/mesh/fvm-conservation.i "${args[@]}" 2>&1 | tee "$out/$log"
    if test "$phase" = check; then grep -q 'Syntax OK' "$out/$log"; fi
  done
  docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$out:/evidence" -v "$root/tests/mesh:/scripts:ro" "$BASE_IMAGE" -lc 'source /environment; python3 /scripts/verify-flat.py /evidence'
done
test "$(sha256sum app/physics-opt | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$ev/executable.sha256")"
if test "$GITHUB_REF" = refs/heads/feature/parent-exodus; then
  # Separate child-enabled run: normal candidate still has exactly one output.
  docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$ev:/evidence" -v "$root/tests/mesh:/scripts:ro" "$BASE_IMAGE" -lc 'source /environment; python3 /scripts/diagnose-fvm-conservation.py /evidence'
  docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$ev:/evidence" -v "$root/tests/mesh:/scripts:ro" "$BASE_IMAGE" -lc 'source /environment; python3 /scripts/diagnose-rf-transfer.py /evidence'
fi
mkdir "$RUNNER_TEMP/physics-exodus"
docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$ev:/evidence" -v "$root/tests/mesh:/scripts:ro" -v "$RUNNER_TEMP/physics-exodus:/results" "$BASE_IMAGE" -lc 'source /environment; python3 /scripts/verify-parent-exodus.py /evidence /results'
echo NATIVE_PARENT_EXODUS_PASS
