#!/usr/bin/env bash
set -euo pipefail
ev="$RUNNER_TEMP/physics-evidence"
root="$PWD"
# Compare the immutable original mesh only during migration qualification.
# Ordinary main builds use the committed mesh directly.
kinds=(conformal)
if test "$GITHUB_REF" = refs/heads/migration/app-assets; then
  kinds=(baseline conformal)
  git show 054e99c90e95df9ea110b0244d10c7279a999f56:assets/maxwell.msh >"$RUNNER_TEMP/original-maxwell.msh"
  test "$(git hash-object "$RUNNER_TEMP/original-maxwell.msh")" = 28ff31220904ff81f426d0c2ed8dd18a7fd40b9e
  node tests/mesh/conform-maxwell.js assets/mesh.msh "$RUNNER_TEMP/original-maxwell.msh" "$RUNNER_TEMP/reproduced-maxwell.msh" >"$ev/conformal-replay.json"
  cmp assets/maxwell.msh "$RUNNER_TEMP/reproduced-maxwell.msh"
fi
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
    if test "$kind" = baseline; then cp "$RUNNER_TEMP/original-maxwell.msh" "$case_dir/assets/maxwell.msh"; fi
    expected=da8af4354d7cef5552bc7efccf3baf0da7d564bd
    if test "$kind" = baseline; then expected=28ff31220904ff81f426d0c2ed8dd18a7fd40b9e; fi
    test "$(git hash-object "$case_dir/assets/maxwell.msh")" = "$expected"
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
test "$(sha256sum app/physics-opt | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$ev/executable.sha256")"
if test "${#kinds[@]}" -eq 2; then
  docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$ev:/evidence" -v "$root/tests/mesh:/scripts:ro" "$BASE_IMAGE" -lc 'source /environment; python3 /scripts/compare-physics.py /evidence'
fi
echo NATIVE_FLAT_CONFORMAL_BOUNDED_PASS
