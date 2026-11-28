#!/usr/bin/env bash
# Same container as the unmodified MOOSE and native application.
set -euo pipefail
ev=/evidence/flow
mkdir -p "$ev"
python3 /workspace/tests/mesh/verify-boundary-gradient.py prepare "$ev"
for kind in exterior internal_active_first internal_passive_first; do
  for direction in outflow inflow; do
    d="$ev/$kind/$direction"
    mkdir -p "$d"
    cp "$ev/$kind/case.msh" "$d/case.msh"
    cp /workspace/tests/mesh/boundary-flow.i "$d/flow.i"
    extra=()
    if test "$direction" = inflow; then
      extra=(Variables/u/initial_condition=-2 FVBCs/u_value/value=-2)
    fi
    (cd "$d"; timeout 180 /workspace/app/physics-opt -i flow.i Outputs/file_base="$d/flow" "${extra[@]}") 2>&1 | tee "$d/solve.log"
  done
done
python3 /workspace/tests/mesh/verify-boundary-flow.py "$ev"
