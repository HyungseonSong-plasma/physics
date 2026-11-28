#!/usr/bin/env bash
set -euo pipefail
root="$PWD"
ev="$RUNNER_TEMP/physics-evidence/gradient"
mkdir -p "$ev"
python3 tests/mesh/verify-boundary-gradient.py prepare "$ev"
for kind in exterior internal_active_first internal_passive_first; do
  cp tests/mesh/boundary-gradient.i "$ev/$kind/probe.i"
  docker run --rm --network none --entrypoint /bin/bash --user 0:0 --workdir /case \
    -v "$root:/workspace:ro" -v "$ev/$kind:/case" "$BASE_IMAGE" -lc '
      set -euo pipefail
      source /environment
      export LD_LIBRARY_PATH=/workspace/app/test/lib:/workspace/app/lib:${LD_LIBRARY_PATH:-}
      timeout 180 /workspace/app/physics-opt -i probe.i Outputs/file_base=/case/probe
    ' 2>&1 | tee "$ev/$kind/solve.log"
done
python3 tests/mesh/verify-boundary-gradient.py compare "$ev"
