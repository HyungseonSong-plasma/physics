# physics

Physics experiments and independent MOOSE Physics application build.

Owner-selected source snapshot: moose-test-repo draft PR #903 at `f55bd9fe32023f21a4c2d0c571b51e9e077f5475`. See [IMPORT_MANIFEST.json](IMPORT_MANIFEST.json). Source remains owned by the original repository until a separately approved cutover. Seven legacy reference tables are intentionally excluded by the owner; the selected database contains 23 files (19 EI candidates, two transport tables and two documentation files). Legacy checks requiring excluded tables are outside this acceptance. Preserve the application LGPL 2.1 notices and original Apache-2.0 build recipes.

## Native build

`build-base/` contains the original dependency-image recipes. The first build uses the existing immutable image pinned in `physics_app/dependencies.lock`, rather than rebuilding MOOSE. [Native build workflow](.github/workflows/physics-build.yml) checks the lock, original source manifest, image labels, dependencies, native compilation and bounded smoke tests. As in the source repository's Native CI, compile with `make -j2 app_non_unity_dirs="%/utils"` to keep utility translation units separate; the default Unity build otherwise combines private symbols with identical names. The initial manifest comparison is a migration gate; future reviewed source changes will need a separate evolution of that gate. The same CI job collects the runtime closure using `runtime-image/`, builds a local scratch image and validates its database contents and native/runtime lookup equivalence. No GHCR push occurs in this validation job.

The Python work-framework contract test remains independent of the native compiler and solver.
