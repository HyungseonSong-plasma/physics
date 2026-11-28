#!/usr/bin/env bash
set -euo pipefail
for type in BoundaryINSFVVelocityVariable BoundaryINSFVPressureVariable BoundaryINSFVScalarFieldVariable; do
  ev="/evidence/gradient/$type"
  mkdir -p "$ev"
  python3 /workspace/tests/mesh/verify-boundary-gradient.py prepare "$ev"
  for kind in exterior internal_active_first internal_passive_first; do
    cp /workspace/tests/mesh/boundary-gradient.i "$ev/$kind/probe.i"
    (cd "$ev/$kind"; timeout 180 /workspace/app/physics-opt -i probe.i Variables/v/type="$type" Outputs/file_base="$ev/$kind/probe") 2>&1 | tee "$ev/$kind/solve.log"
  done
  python3 /workspace/tests/mesh/verify-boundary-gradient.py compare "$ev"
done
