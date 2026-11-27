# physics

Physics experiments and independent MOOSE Physics application build.

Initial imported snapshot: see [IMPORT_MANIFEST.json](IMPORT_MANIFEST.json). Source remains owned by the original repository until a separately approved cutover. Seven legacy reference tables are withheld pending provenance and redistribution qualification; this is not the complete original runtime dataset. Preserve the application LGPL 2.1 notices and original Apache-2.0 build recipes.

## Native build

`build-base/` contains the original dependency-image recipes. The first build uses the existing immutable image pinned in `physics_app/dependencies.lock`, rather than rebuilding MOOSE. [Native build workflow](.github/workflows/physics-build.yml) checks the lock, original source manifest, image labels, dependencies, native compilation and bounded smoke tests. As in the source repository's Native CI, compile with `make -j2 app_non_unity_dirs="%/utils"` to keep utility translation units separate; the default Unity build otherwise combines private symbols with identical names. The initial manifest comparison is a migration gate; future reviewed source changes will need a separate evolution of that gate. No runtime publication is part of this initial build. Runtime image recipes will live in `runtime-image/` after separate qualification.

The Python work-framework contract test remains independent of the native compiler and solver.
