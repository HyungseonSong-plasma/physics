#!/usr/bin/env bash
set -euo pipefail
ev="$RUNNER_TEMP/physics-evidence"
stage="$RUNNER_TEMP/newonly-417"
layout="$PWD/layout"
chem=experiments/Issue395_powered_chemistry_ladder
mapfile -t layers < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["ordered"]))' "$ev/newonly-stage.json")
test "${#layers[@]}" -eq 11
test "$(git hash-object "$stage/$chem/issue397_maxwell_steady_abs1e11.i")" != ""
python3 - "$stage" "$RUNNER_TEMP/verified-parent.zip" <<'PY'
import sys,zipfile,json,hashlib,pathlib
stage=pathlib.Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2]) as z: inv=json.loads(z.read("single-input/input-inventory.json"))
for name in ("issue397_maxwell_steady_abs1e11.i","rf_elastic_multiapp_maxwell_400w_100us_dt1000ns_overlay.i","rf_elastic_multiapp_maxwell_400w_100us_dt1000ns_child.i"):
    rel="experiments/Issue395_powered_chemistry_ladder/"+name
    assert hashlib.sha256((stage/rel).read_bytes()).hexdigest()==inv["files"][rel]["sha256"]
PY
# Official pinned HIT merger for the two included Maxwell layers.
docker run --rm --network none --workdir /case --entrypoint /bin/bash \
  -v "$stage:/case:ro" -v "$ev:/evidence" "$BASE_IMAGE" -lc '
    set -euo pipefail
    source /environment
    hit_dir=/opt/physics_vendor/moose/framework/contrib/hit
    if ! test -x "$hit_dir/hit"; then
      cp -a "$hit_dir" /tmp/flat-hit
      hit_dir=/tmp/flat-hit
      wasp_lib="$(find /opt -type f -name "libwasphit.so*" -print -quit)"
      if test -z "$wasp_lib"; then wasp_lib="$(find /opt -name "libwasp*.so" -print -quit)"; fi
      test -n "$wasp_lib"
      make -C "$hit_dir" hit WASP_DIR="$(dirname "$(dirname "$wasp_lib")")" CXX=c++
    fi
    "$hit_dir/hit" merge -output /evidence/maxwell-merged-original.i "$@"
  ' hit "$chem/issue397_maxwell_steady_abs1e11.i" "$chem/rf_elastic_multiapp_maxwell_400w_100us_dt1000ns_overlay.i" 2>&1 | tee "$ev/child-hit-merge.log"
python3 tests/flat-assets/normalize.py "$stage" "$layout" "$RUNNER_TEMP/verified-parent.zip" "$ev/maxwell-merged-original.i" "$RUNNER_TEMP/flat-case" "$ev/newonly-stage.json"
docker image inspect "$BASE_IMAGE" --format '{{.Id}} {{.Size}} {{.Os}}/{{.Architecture}}' >"$ev/jit-runtime-image.txt"
opts=(--network none --workdir /case --entrypoint /bin/bash --user 0:0
  --env OXYGEN_RESEARCH_400=1 --env OXYGEN_RESEARCH_FULL24=0 --env OXYGEN_RESEARCH_EI2738_FORMULA=0 --env OXYGEN_RESEARCH_QUICK_5MIN=0
  --mount "type=bind,src=$layout,dst=/workspace,readonly")
args=(Executioner/num_steps=1 Outputs/file_base=/evidence/fields/parent Outputs/exodus=true Outputs/csv=true Outputs/time_step_interval=1 'Outputs/execute_on=INITIAL TIMESTEP_END' Outputs/checkpoint=false)
for kind in baseline flat; do
  out="$ev/$kind"; mkdir -p "$out/fields"
  cp "$ev"/{newonly-stage.json,executable.sha256,jit-runtime-image.txt} "$out/"
  if test "$kind" = baseline; then src="$stage"; inputs=("${layers[@]}"); else src="$RUNNER_TEMP/flat-case"; inputs=(assets/input.i); cp "$src/assets/input.i" "$out/input.i"; fi
  for phase in check solve; do
    case_dir="$RUNNER_TEMP/flat-$kind-$phase"
    cp -a "$src" "$case_dir"
    test ! -e "$case_dir/.jitcache"
    extra=()
    if test "$phase" = check; then extra=(--check-input); limit=480; log=newonly-check-input.log; else limit=1800; log=newonly-one-step.log; fi
    timeout "$limit" docker run --rm "${opts[@]}" -v "$case_dir:/case" -v "$out:/evidence" "$BASE_IMAGE" -lc '
      set -euo pipefail
      source /environment
      export LD_LIBRARY_PATH=/workspace/app/test/lib:/workspace/app/lib:${LD_LIBRARY_PATH:-}
      exec /workspace/app/physics-opt "$@"
    ' physics-opt "${extra[@]}" -i "${inputs[@]}" "${args[@]}" 2>&1 | tee "$out/$log"
    if test "$phase" = check; then grep -q 'Syntax OK' "$out/$log"; fi
  done
  docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$out:/evidence" -v "$stage:/case:ro" -v "$PWD/runtime-image/verify-newonly-output.py:/verify.py:ro" "$BASE_IMAGE" -lc 'source /environment; python3 /verify.py /evidence 1e-9 /case'
done
docker run --rm --network none --entrypoint /bin/bash --user 0:0 -v "$ev:/evidence" -v "$PWD/runtime-image/rdc-p7-compare.py:/compare.py:ro" "$BASE_IMAGE" -lc 'source /environment; python3 /compare.py /evidence/baseline /evidence/flat'
test "$(sha256sum "$layout/app/physics-opt" | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$ev/executable.sha256")"
python3 - "$RUNNER_TEMP/flat-case/assets" "$ev/flat/equivalence.json" "$RUNNER_TEMP/qualified-flat-inputs" <<'PY'
import hashlib,json,os,pathlib,shutil,sys
assets,eq,out=map(pathlib.Path,sys.argv[1:])
r=json.loads(eq.read_text())
assert r["status"]=="SINGLE_INPUT_NUMERICAL_EQUIVALENCE_PASS"
out.mkdir()
names=("input.i","maxwell.i","chemistry.json")
for name in names: shutil.copyfile(assets/name,out/name)
files={name:hashlib.sha256((out/name).read_bytes()).hexdigest() for name in names}
assert r["input_sha256"]==files["input.i"]
receipt={"status":"FLAT_ASSETS_NUMERICAL_EQUIVALENCE_PASS","science":"SCIENCE_HOLD","layout_commit":"bbe1d53f35dca500e508dbf33aab095b0e1c950a","qualification_commit":os.environ["GITHUB_SHA"],"source_parent_artifact":15240938520,"source_parent_sha256":"7f221b51e81c39812bafa635e2f3e0fe6eeee8c0a9f8586bfd1b2ec2333fffce","source_chemistry_sha256":"8e9c5e45f3c644c20baab66936fd3d9a495ab07b5facf06d795af08d6b8b3859","maxwell_mesh":"ORIGINAL","files":files,"numerical_comparison":r}
(out/"receipt.json").write_text(json.dumps(receipt,indent=2,sort_keys=True)+"\n")
print("FLAT_ASSETS_NUMERICAL_EQUIVALENCE_PASS")
PY
