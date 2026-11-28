#!/usr/bin/env bash
# Exact native executable, unchanged canonical 400 W case, full time sequence.
set -euo pipefail
root="$PWD"
out="$RUNNER_TEMP/physics-400w-100us"
case_dir="$RUNNER_TEMP/physics-400w-100us-case"
mkdir -p "$out/fields" "$case_dir"
cp -a assets "$case_dir/assets"
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
test "$(sha256sum app/physics-opt | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$RUNNER_TEMP/physics-evidence/executable.sha256")"
{ git rev-parse HEAD; sha256sum app/physics-opt assets/input.i assets/maxwell.i assets/mesh.msh; echo "$BASE_IMAGE"; } >"$out/provenance.txt"
opts=(--network none --workdir /case --entrypoint /bin/bash --user 0:0
  --env OXYGEN_RESEARCH_400=1 --env OXYGEN_RESEARCH_FULL24=0 --env OXYGEN_RESEARCH_EI2738_FORMULA=0 --env OXYGEN_RESEARCH_QUICK_5MIN=0
  --mount "type=bind,src=$root,dst=/workspace,readonly"
  -v "$case_dir:/case" -v "$out:/evidence")
# Preserve the production time sequence, all accepted frames and default child-output disable.
# The additional CSV contains only numerical diagnostics. No equation changes.
timeout 14400 docker run --rm "${opts[@]}" "$BASE_IMAGE" -lc '
  set -euo pipefail
  source /environment
  export LD_LIBRARY_PATH=/workspace/app/test/lib:/workspace/app/lib:${LD_LIBRARY_PATH:-}
  exec /workspace/app/physics-opt "$@"
' physics-opt -i assets/input.i /workspace/tests/mesh/fvm-conservation.i \
  Executioner/end_time=1e-4 Outputs/file_base=/evidence/fields/physics \
  Outputs/exodus=true Outputs/csv=true Outputs/checkpoint=false Outputs/time_step_interval=1 \
  'Outputs/execute_on=INITIAL TIMESTEP_END' 2>&1 | tee "$out/transient.log"
docker run --rm "${opts[@]}" "$BASE_IMAGE" -lc 'source /environment; python3 /workspace/tests/mesh/verify-transient-100us.py /evidence /case/assets/input.i'
