#!/usr/bin/env bash
set -euo pipefail
ev="$RUNNER_TEMP/physics-evidence"
root="$PWD"
kinds=(candidate)
if test "$GITHUB_REF" = refs/heads/feature/parent-exodus; then
  kinds=(baseline candidate)
  git show 33195c79338b0597b462800109b81d6fbe75c932:assets/input.i >"$RUNNER_TEMP/baseline-input.i"
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
test "$(sha256sum app/physics-opt | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$ev/executable.sha256")"
mkdir "$RUNNER_TEMP/physics-exodus"
docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$ev:/evidence:ro" -v "$root/tests/mesh:/scripts:ro" -v "$RUNNER_TEMP/physics-exodus:/results" "$BASE_IMAGE" -lc 'source /environment; python3 /scripts/verify-parent-exodus.py /evidence /results'
echo NATIVE_PARENT_EXODUS_PASS
