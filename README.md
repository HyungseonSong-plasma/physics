# Physics

MOOSE Physics application for plasma and RF Maxwell coupling.

- `app/`: application source and Makefile.
- `assets/`: flat simulation inputs, one shared parent/Maxwell mesh, chemistry and lookup data.
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

The demonstrated S6-417 research case uses `OXYGEN_RESEARCH_400=1`, `OXYGEN_RESEARCH_FULL24=0`, `OXYGEN_RESEARCH_EI2738_FORMULA=0`, and `OXYGEN_RESEARCH_QUICK_5MIN=0`. For bounded CI, the solver is limited to one parent step (1 ns). This is not long-time scientific validation. The prior original-mesh flat-layout parity and the separate conformal-mesh comparison are recorded in `IMPORT_MANIFEST.json`. The unified mesh preserves all eight Parent volume blocks and adds six Maxwell-only blocks. Parent retains all 14 volume blocks for output, but its physical equations are restricted to their original domains. Maxwell removes imported Parent sidesets and generates its own. The original detached axis lines are reconstructed on actual element edges. Native requalification is pending; changes in Maxwell discretization may change RF results.

Imported historical checkers requiring excluded legacy tables or upstream-only contracts are outside this bounded acceptance. No `runtime-image/` directory is required or included.

### Exodus output

Parent writes one native Exodus file (`physics.e`, or the chosen `Outputs/file_base`) and CSV, including the full shared volume mesh and three surface blocks. `E_real_full` and `E_imag_full` are output-only fields transferred from the latest Maxwell solve; original Plasma RF variables are unchanged. `rf_absorbed_power_density` is the Parent's volume-averaged raw RF heating density in W/m^3. Plasma-only variables are meaningful only on their defined blocks; initial RF fields are unsolved initial values. Maxwell child Exodus and CSV are disabled by default. CI validates one-step numerical parity against the previous two-output layout on the feature branch and publishes only `physics.e`, `physics.csv` and manifest in `physics-exodus`. Native qualification of this full Parent mesh change is pending.
