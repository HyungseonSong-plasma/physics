#!/usr/bin/env bash
set -euo pipefail
ev="$RUNNER_TEMP/physics-evidence"
root="$PWD"
kinds=(conformal)
if test "$GITHUB_REF" = refs/heads/migration/unified-mesh; then
  kinds=(baseline conformal)
  mkdir "$RUNNER_TEMP/old-assets"
  for file in mesh.msh maxwell.msh input.i maxwell.i; do git show 95949734dc6954108d87deb5ed6e2f750bd990b7:assets/$file >"$RUNNER_TEMP/old-assets/$file"; done
  test "$(git hash-object "$RUNNER_TEMP/old-assets/mesh.msh")" = 1674286d95b5031651c74c0ff38667626d5549f5
  test "$(git hash-object "$RUNNER_TEMP/old-assets/maxwell.msh")" = da8af4354d7cef5552bc7efccf3baf0da7d564bd
  node tests/mesh/unify-mesh.js "$RUNNER_TEMP/old-assets/mesh.msh" "$RUNNER_TEMP/old-assets/maxwell.msh" "$RUNNER_TEMP/reproduced.msh" >"$ev/unified-replay.json"
  cmp assets/mesh.msh "$RUNNER_TEMP/reproduced.msh"
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
    if test "$kind" = baseline; then
      for file in mesh.msh maxwell.msh input.i maxwell.i; do cp "$RUNNER_TEMP/old-assets/$file" "$case_dir/assets/$file"; done
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
test "$(sha256sum app/physics-opt | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$ev/executable.sha256")"
if test "${#kinds[@]}" -eq 2; then
  docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$ev:/evidence" -v "$root/tests/mesh:/scripts:ro" "$BASE_IMAGE" -lc 'source /environment; python3 /scripts/compare-unified.py /evidence'
fi
# Only publish after the native and field gates pass.
mkdir -p "$RUNNER_TEMP/physics-exodus"
docker run --rm --network none --entrypoint /bin/bash --user 0:0 \
  -v "$ev/conformal:/evidence:ro" -v "$root/tests/mesh:/scripts:ro" \
  -v "$RUNNER_TEMP/physics-exodus:/results" "$BASE_IMAGE" -lc 'source /environment; python3 /scripts/verify-exodus.py /evidence/fields /results'
echo NATIVE_UNIFIED_MESH_BOUNDED_PASS
