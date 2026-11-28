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
  solve = false
  kernel_coverage_check = ONLY_LIST
  kernel_coverage_block_list = active
[]
[Variables]
  [u]
    type = BoundaryINSFVVelocityVariable
    block = active
    initial_condition = 2
  []
  [v]
    type = BoundaryINSFVVelocityVariable
    block = active
    initial_condition = 0
  []
  [pressure]
    type = BoundaryINSFVPressureVariable
    block = active
    initial_condition = 1
  []
  [q]
    type = MooseVariableFVReal
    block = active
    initial_condition = 3
  []
[]
[UserObjects]
  [rc]
    type = INSFVRhieChowInterpolator
    u = u
    v = v
    pressure = pressure
    block = active
    velocity_interp_method = average
  []
[]
[FVBCs]
  [u_value]
    type = FVDirichletBC
    variable = u
    boundary = 'outer active_interface'
    value = 2
  []
  [v_value]
    type = FVDirichletBC
    variable = v
    boundary = 'outer active_interface'
    value = 0
  []
  [q_value]
    type = FVDirichletBC
    variable = q
    boundary = 'outer active_interface'
    value = 3
  []
[]
[Postprocessors]
  [volume_flow]
    type = BoundaryVolumetricFlowRate
    boundary = active_interface
    vel_x = u
    vel_y = v
    advected_quantity = 1
    rhie_chow_user_object = rc
    velocity_interp_method = average
    advected_interp_method = upwind
    execute_on = INITIAL
  []
  [quantity_flow]
    type = BoundaryVolumetricFlowRate
    boundary = active_interface
    vel_x = u
    vel_y = v
    advected_quantity = q
    rhie_chow_user_object = rc
    velocity_interp_method = average
    advected_interp_method = upwind
    execute_on = INITIAL
  []
[]
[Executioner]
  type = Steady
[]
[Outputs]
  csv = true
  execute_on = INITIAL
[]
