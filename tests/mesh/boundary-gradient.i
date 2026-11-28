[Mesh]
  [mesh]
    type = FileMeshGenerator
    file = case.msh
  []
  [owner]
    type = ParsedGenerateSideset
    input = mesh
    combinatorial_geometry = '1'
    included_subdomains = active
    included_boundaries = interface
    new_sideset_name = active_interface
  []
  [remove_original]
    type = BoundaryDeletionGenerator
    input = owner
    boundary_names = interface
  []
[]
[Problem]
  kernel_coverage_check = ONLY_LIST
  kernel_coverage_block_list = active
[]
[Variables]
  [v]
    family = MONOMIAL
    order = CONSTANT
    fv = true
    block = active
    initial_condition = 1
    two_term_boundary_expansion = true
  []
[]
[Functions]
  [affine]
    type = ParsedFunction
    expression = '1+2*(x-2/3)+3*(y-1/3)'
  []
[]
[FVKernels]
  [diffusion]
    type = FVDiffusion
    variable = v
    coeff = 1
    block = active
  []
[]
[FVBCs]
  [dirichlet]
    type = FVFunctionDirichletBC
    variable = v
    boundary = 'outer active_interface'
    function = affine
  []
[]
[Postprocessors]
  [native_error]
    type = BoundaryGradientProbe
    variable = v
    boundary = active_interface
    metric = native_error
    execute_on = INITIAL
  []
  [corrected_error]
    type = BoundaryGradientProbe
    variable = v
    boundary = active_interface
    metric = corrected_error
    execute_on = INITIAL
  []
  [cell_error]
    type = BoundaryGradientProbe
    variable = v
    boundary = active_interface
    metric = cell_error
    execute_on = INITIAL
  []
  [native_flux_error]
    type = BoundaryGradientProbe
    variable = v
    boundary = active_interface
    metric = native_flux_error
    execute_on = INITIAL
  []
  [corrected_flux_error]
    type = BoundaryGradientProbe
    variable = v
    boundary = active_interface
    metric = corrected_flux_error
    execute_on = INITIAL
  []
  [active_owner]
    type = BoundaryGradientProbe
    variable = v
    boundary = active_interface
    metric = active_owner
    execute_on = INITIAL
  []
[]
[Executioner]
  type = Steady
  solve_type = NEWTON
  petsc_options_iname = '-pc_type'
  petsc_options_value = 'lu'
  nl_abs_tol = 1e-12
  nl_rel_tol = 1e-12
[]
[Outputs]
  csv = true
  execute_on = 'INITIAL TIMESTEP_END'
[]
