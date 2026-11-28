# Physics regression assets

The canonical Issue #397 graded coarse L1 parent mesh is a fixed public regression input, used by the S6-417 400 W case. Gmsh v2.2 ASCII; 1,739 used nodes, 3,155 triangles, 24 physical groups, 27 plasma-side wafer faces.

- File: `baseline_plasma_plus_unstructured_cover_plus_wafer.msh` (174352 bytes).
- Geometry source: [moose-test-repo@29d1acc](https://github.com/HyungseonSong-plasma/moose-test-repo/tree/29d1acc6ef7969908b86719e4b95c73a1565136d); canonical contract `experiments/Issue395_powered_chemistry_ladder/issue397_baseline_mesh.json`.
- Reproduced and independently verified by [Run 46087290460](https://github.com/HyungseonSong-plasma/physics/actions/runs/46087290460) using the pinned geometry scripts, NumPy 2.1.2 and SciPy 1.14.1. The exported mesh bytes were rehashed before Git import.

Verify before each use: `cd assets && sha256sum --check mesh.sha256`. Reuse the file without regeneration. This is a mesh identity guarantee, not scientific acceptance of the solver or any particular power condition.
