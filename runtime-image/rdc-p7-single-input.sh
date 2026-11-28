#!/usr/bin/env bash
set -euo pipefail
ev="$RUNNER_TEMP/physics-evidence"
stage="$RUNNER_TEMP/newonly-417"
case_dir="$RUNNER_TEMP/p7-single"
single="$ev/single-input"
image="physics-runtime-jit:ci-$GITHUB_SHA"
cp -a "$stage" "$case_dir"
mkdir -p "$single/fields"
cp "$ev"/{newonly-stage.json,executable.sha256,jit-runtime-image.txt} "$single/"
mapfile -t layers < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["ordered"]))' "$ev/newonly-stage.json")
test "${#layers[@]}" -eq 11
parent="$(dirname "${layers[0]}")/input.i"
for layer in "${layers[@]}"; do
  test "$(dirname "$layer")" = "$(dirname "$parent")"
done
test ! -e "$case_dir/$parent"
# Run the pinned MOOSE HIT merger, not a hand-written text concatenation.
# Keep the merged file alongside the originals so relative references retain
# their meaning. No physical or solver parameter overrides during merge.
docker run --rm --network none --workdir /case --entrypoint /bin/bash \
  -v "$case_dir:/case" "$image" -lc '
    set -euo pipefail
    source /environment
    hit_dir=/opt/physics_vendor/moose/framework/contrib/hit
    if ! test -x "$hit_dir/hit"; then
      cp -a "$hit_dir" /tmp/p7-hit
      hit_dir=/tmp/p7-hit
      wasp_lib="$(find /opt -type f -name "libwasphit.so*" -print -quit)"
      if test -z "$wasp_lib"; then
        wasp_lib="$(find /opt -name "libwasp*.so" -print -quit)"
      fi
      test -n "$wasp_lib"
      wasp_dir="$(dirname "$(dirname "$wasp_lib")")"
      make -C "$hit_dir" hit WASP_DIR="$wasp_dir" CXX=c++
    fi
    "$hit_dir/hit" merge -output "$1" "${@:2}"
    test -s "$1"
  ' hit "$parent" "${layers[@]}" 2>&1 | tee "$single/hit-merge.log"
test -s "$case_dir/$parent"
cp "$case_dir/$parent" "$single/input.i"
sha256sum "$single/input.i" | tee "$single/input.sha256"
# Retain the exact public support inventory before running the candidate.
python3 - "$case_dir" "$parent" "$single" <<'PY'
import hashlib, json, sys
from pathlib import Path
case, parent, out = map(Path, sys.argv[1:])
receipt = json.loads((out / "newonly-stage.json").read_text())
files = {}
for path in sorted(case.rglob("*")):
    if path.is_symlink() or "private_rates" in path.relative_to(case).parts:
        raise ValueError("Unsafe or private staged input: " + str(path))
    if path.is_file():
        rel = path.relative_to(case).as_posix()
        files[rel] = {"bytes": path.stat().st_size,
                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
(out / "input-inventory.json").write_text(json.dumps(
    {"parent": str(parent), "original_layers": receipt["ordered"],
     "files": files, "science": "SCIENCE_HOLD"}, sort_keys=True, indent=2) + "\n")
PY
opts=(--network none --workdir /case
  --env OXYGEN_RESEARCH_400=1 --env OXYGEN_RESEARCH_FULL24=0
  --env OXYGEN_RESEARCH_EI2738_FORMULA=0 --env OXYGEN_RESEARCH_QUICK_5MIN=0
  --mount "type=bind,src=$case_dir,dst=/case"
  --mount "type=bind,src=$single,dst=/evidence")
output_args=(Executioner/num_steps=1
  Outputs/file_base=/evidence/fields/parent Outputs/exodus=true Outputs/csv=true
  Outputs/time_step_interval=1 'Outputs/execute_on=INITIAL TIMESTEP_END' Outputs/checkpoint=false)
timeout 480 docker run --rm "${opts[@]}" "$image" --check-input \
  -i "$parent" "${output_args[@]}" 2>&1 | tee "$single/newonly-check-input.log"
grep -q 'Syntax OK' "$single/newonly-check-input.log"
# A fresh staged copy for cold solve (check-input may generate JIT files).
rm -rf "$case_dir"
cp -a "$stage" "$case_dir"
cp "$single/input.i" "$case_dir/$parent"
timeout 1800 docker run --rm "${opts[@]}" "$image" \
  -i "$parent" "${output_args[@]}" 2>&1 | tee "$single/newonly-one-step.log"
docker run --rm --network none --entrypoint /bin/bash --user 0:0 \
  -v "$ev:/evidence" -v "$stage:/case:ro" \
  -v "$PWD/runtime-image/verify-newonly-output.py:/verify-newonly-output.py:ro" \
  -v "$PWD/runtime-image/rdc-p7-compare.py:/compare.py:ro" \
  "$BASE_IMAGE" -lc 'source /environment; python3 /verify-newonly-output.py /evidence/single-input 1e-9 /case; python3 /compare.py /evidence /evidence/single-input'
echo RDC_P7_SINGLE_INPUT_EQUIVALENCE_PASS
