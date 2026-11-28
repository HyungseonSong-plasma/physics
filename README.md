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

The demonstrated S6-417 research case uses `OXYGEN_RESEARCH_400=1`, `OXYGEN_RESEARCH_FULL24=0`, `OXYGEN_RESEARCH_EI2738_FORMULA=0`, and `OXYGEN_RESEARCH_QUICK_5MIN=0`. For bounded CI, the solver is limited to one parent step (1 ns). This is not long-time scientific validation. The prior original-mesh flat-layout parity and the separate conformal-mesh comparison are recorded in `IMPORT_MANIFEST.json`. The unified mesh preserves all eight Parent volume blocks and adds six Maxwell-only blocks. Parent retains only its eight blocks; Maxwell removes imported Parent sidesets and generates its own. The original detached axis lines are reconstructed on actual element edges. Native requalification is pending; changes in Maxwell discretization may change RF results.

Imported historical checkers requiring excluded legacy tables or upstream-only contracts are outside this bounded acceptance. No `runtime-image/` directory is required or included.

### Exodus output

Parent Exodus and CSV remain enabled. The Maxwell MultiApp now enables Exodus while leaving its CSV disabled. MOOSE derives the child output base from the parent output base and MultiApp name, avoiding a collision with the Parent. The existing FullSolveMultiApp output reset behavior is unchanged: the Maxwell file represents the latest steady solve, not a complete transient history. Maxwell steady output time is an execution index (0 initial, 1 solved for the bounded case), not plasma time in seconds. Use a unique parent `Outputs/file_base` for independent runs. CI publishes verified `parent.e`, `maxwell.e`, `parent.csv` and a manifest in the `physics-exodus` artifact for the bounded one-step run. No generated fields are committed.
