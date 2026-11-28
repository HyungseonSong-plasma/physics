#!/usr/bin/env bash
set -euo pipefail
ev="$RUNNER_TEMP/physics-evidence"
stage="$RUNNER_TEMP/newonly-417"
trace="$RUNNER_TEMP/rdc-p7-trace"
mkdir "$trace" "$ev/fields"
# Preserve staged input hashes; run each workload with its own copy.
cp -a "$stage" "$RUNNER_TEMP/p7-check"
cp -a "$stage" "$RUNNER_TEMP/p7-native"
image="physics-runtime-jit:ci-$GITHUB_SHA"
mapfile -t layers < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["ordered"]))' "$ev/newonly-stage.json")
test "${#layers[@]}" -eq 11
opts=(--network none --workdir /case
  --env OXYGEN_RESEARCH_400=1 --env OXYGEN_RESEARCH_FULL24=0
  --env OXYGEN_RESEARCH_EI2738_FORMULA=0 --env OXYGEN_RESEARCH_QUICK_5MIN=0)
# Validate the exact same output and solver overrides before tracing.
output_args=(Executioner/num_steps=1
  Outputs/file_base=/evidence/fields/parent Outputs/exodus=true Outputs/csv=true
  Outputs/time_step_interval=1 'Outputs/execute_on=INITIAL TIMESTEP_END' Outputs/checkpoint=false)
timeout 480 docker run --rm "${opts[@]}" \
  --mount "type=bind,src=$RUNNER_TEMP/p7-check,dst=/case" \
  --mount "type=bind,src=$ev,dst=/evidence" \
  "$image" --check-input -i "${layers[@]}" "${output_args[@]}" 2>&1 | tee "$ev/newonly-check-input.log"
grep -q 'Syntax OK' "$ev/newonly-check-input.log"
# Attach the runner's own strace to the trusted container process
# before executing Physics, avoiding package changes to the pinned base.
cid="$(docker create "${opts[@]}" --entrypoint /bin/bash \
  --mount "type=bind,src=$RUNNER_TEMP/p7-native,dst=/case" \
  --mount "type=bind,src=$ev,dst=/evidence" \
  "$image" -lc 'set -euo pipefail; source /environment
    export LD_LIBRARY_PATH=/opt/physics/test/lib:/opt/physics/lib:${LD_LIBRARY_PATH:-}
    for key in PATH LD_LIBRARY_PATH LIBRARY_PATH CPATH CPLUS_INCLUDE_PATH C_INCLUDE_PATH GCC_EXEC_PREFIX COMPILER_PATH; do
      if test -v "$key"; then printf "%s=%s\n" "$key" "${!key}"; fi
    done >/evidence/rdc-p7-toolchain-env.txt
    touch /evidence/rdc-p7-ready
    until test -f /evidence/rdc-p7-go; do sleep 0.1; done
    exec /opt/physics/physics-opt "$@"' physics-opt \
  -i "${layers[@]}" "${output_args[@]}")"
trap 'docker logs "$cid" >"$ev/newonly-one-step.log" 2>&1 || true; docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
docker start "$cid"
for i in $(seq 1 100); do test -f "$ev/rdc-p7-ready" && break; sleep 0.1; done
test -f "$ev/rdc-p7-ready"
pid="$(docker inspect --format '{{.State.Pid}}' "$cid")"
test "$pid" -gt 1
sudo -n timeout 1900 strace -ff -qq -s 65535 -xx \
  -e trace=open,openat,openat2,creat,execve,execveat \
  -o "$trace/events" -p "$pid" 2>"$ev/rdc-p7-tracer.log" &
tracer=$!
attached=0
for i in $(seq 1 100); do
  if sudo -n awk '/^TracerPid:/ { exit !($2>0) }' "/proc/$pid/status"; then attached=1; break; fi
  kill -0 "$tracer" || break
  sleep 0.1
done
test "$attached" = 1
touch "$ev/rdc-p7-go"
rc="$(timeout 1800 docker wait "$cid")"
docker logs "$cid" 2>&1 | tee "$ev/newonly-one-step.log"
tracer_rc=0
wait "$tracer" || tracer_rc=$?
docker rm "$cid"
trap - EXIT
# Preserve separate solver, tracer, parser, and numerical gate outcomes.
parse_rc=0
sudo -n PYTHONPATH="$PWD/rdc/src" python3 runtime-image/rdc-p7-trace.py "$trace" "$ev/rdc-p7-trace.json" || parse_rc=$?
numerical_rc=not-run
if test "$rc" = 0; then
  numerical_rc=0
  docker run --rm --network none --entrypoint /bin/bash --user 0:0 \
    -v "$ev:/evidence" -v "$stage:/case:ro" \
    -v "$PWD/runtime-image/verify-newonly-output.py:/verify-newonly-output.py:ro" \
    "$BASE_IMAGE" -lc 'source /environment; python3 /verify-newonly-output.py /evidence 1e-9 /case' || numerical_rc=$?
fi
printf 'solver=%s\ntracer=%s\nparser=%s\nnumerical=%s\n' "$rc" "$tracer_rc" "$parse_rc" "$numerical_rc" | tee "$ev/rdc-p7-gates.txt"
test "$rc" = 0 && test "$tracer_rc" = 0 && test "$parse_rc" = 0 && test "$numerical_rc" = 0 || exit 1
echo RDC_P7_FULL_RUNTIME_BASELINE_AND_TRACE_PASS
df -h /
