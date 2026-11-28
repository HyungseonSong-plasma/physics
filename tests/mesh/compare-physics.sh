#!/usr/bin/env bash
set -euo pipefail
ev="$RUNNER_TEMP/physics-evidence"
stage="$RUNNER_TEMP/newonly-417"
image="physics-runtime-jit:ci-$GITHUB_SHA"
mesh=experiments/Issue18_qvt_plasma_mapping/qvt.msh
mapfile -t layers < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["ordered"]))' "$ev/newonly-stage.json")
test "${#layers[@]}" -eq 11
opts=(--network none --workdir /case --env OXYGEN_RESEARCH_400=1 --env OXYGEN_RESEARCH_FULL24=0 --env OXYGEN_RESEARCH_EI2738_FORMULA=0 --env OXYGEN_RESEARCH_QUICK_5MIN=0)
output_args=(Executioner/num_steps=1 Outputs/file_base=/evidence/fields/parent Outputs/exodus=true Outputs/csv=true Outputs/time_step_interval=1 'Outputs/execute_on=INITIAL TIMESTEP_END' Outputs/checkpoint=false)
for kind in baseline conformal; do
  out="$ev/$kind"
  mkdir -p "$out/fields"
  cp "$ev"/{newonly-stage.json,executable.sha256,jit-runtime-image.txt} "$out/"
  for phase in check solve; do
    case_dir="$RUNNER_TEMP/mesh-$kind-$phase"
    cp -a "$stage" "$case_dir"
    if test "$kind" = conformal; then
      cp tests/mesh/maxwell-conformal.msh "$case_dir/$mesh"
      test "$(git hash-object "$case_dir/$mesh")" = da8af4354d7cef5552bc7efccf3baf0da7d564bd
    fi
    if test "$phase" = check; then
      timeout 480 docker run --rm "${opts[@]}" -v "$case_dir:/case" -v "$out:/evidence" "$image" --check-input -i "${layers[@]}" "${output_args[@]}" 2>&1 | tee "$out/newonly-check-input.log"
      grep -q 'Syntax OK' "$out/newonly-check-input.log"
    else
      sha256sum "$case_dir/$mesh" >"$out/maxwell-mesh.sha256"
      timeout 1800 docker run --rm "${opts[@]}" -v "$case_dir:/case" -v "$out:/evidence" "$image" -i "${layers[@]}" "${output_args[@]}" 2>&1 | tee "$out/newonly-one-step.log"
      docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$out:/evidence" -v "$stage:/case:ro" -v "$PWD/runtime-image/verify-newonly-output.py:/verify-newonly-output.py:ro" "$BASE_IMAGE" -lc 'source /environment; python3 /verify-newonly-output.py /evidence 1e-9 /case'
    fi
  done
done
docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$ev:/evidence" -v "$PWD/runtime-image/rdc-p7-compare.py:/scripts/rdc-p7-compare.py:ro" -v "$PWD/tests/mesh/compare-physics.py:/scripts/compare-physics.py:ro" "$BASE_IMAGE" -lc 'source /environment; python3 /scripts/compare-physics.py /evidence'
