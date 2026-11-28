# Physics

MOOSE Physics application for plasma and RF Maxwell coupling.

- `app/`: application source and Makefile.
- `assets/`: flat simulation inputs, parent/Maxwell meshes, chemistry and lookup data.
- `build-base/`: pinned dependency build recipe.
- `tests/`: validation and work-contract checks.

Build from `app/` with the dependency environment in `app/dependencies.lock` (the native CI uses the pinned build-base image, without constructing a separate runtime image).

```bash
cd app
make -j2 app_non_unity_dirs="%/utils"
cd ..
# With the pinned dependencies and library paths loaded:
./app/physics-opt --check-input -i assets/input.i
./app/physics-opt -i assets/input.i
```

The demonstrated S6-417 research case uses `OXYGEN_RESEARCH_400=1`, `OXYGEN_RESEARCH_FULL24=0`, `OXYGEN_RESEARCH_EI2738_FORMULA=0`, and `OXYGEN_RESEARCH_QUICK_5MIN=0`. For bounded CI, the solver is limited to one parent step (1 ns). This is not long-time scientific validation. The prior original-mesh flat-layout parity and the separate conformal-mesh comparison are recorded in `IMPORT_MANIFEST.json`. The conformal mesh preserves the parent plasma coordinates and triangle connectivity; changing the mesh changes RF results, so exact numerical equivalence to the original mesh is not claimed.

Imported historical checkers requiring excluded legacy tables or upstream-only contracts are outside this bounded acceptance. No `runtime-image/` directory is required or included.
