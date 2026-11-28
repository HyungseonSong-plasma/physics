#!/usr/bin/env bash
# Runs in the SAME container as the rebuilt MOOSE library.
set -euo pipefail
ev=/evidence/gradient
mkdir -p "$ev"
python3 /workspace/tests/mesh/verify-boundary-gradient.py prepare "$ev"
for kind in exterior internal_active_first internal_passive_first; do
  cp /workspace/tests/mesh/boundary-gradient.i "$ev/$kind/probe.i"
  (cd "$ev/$kind"; timeout 180 /workspace/app/physics-opt -i probe.i Outputs/file_base="$ev/$kind/probe") 2>&1 | tee "$ev/$kind/solve.log"
done
python3 /workspace/tests/mesh/verify-boundary-gradient.py compare "$ev"
