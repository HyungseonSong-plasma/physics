# Diagnostic overlay only. Does not change any residual equations.
[FunctorMaterials]
  [audit_rho_momentum_x]
    type = ADParsedFunctorMaterial
    property_name = audit_rho_momentum_x
    functor_names = 'rho_neutral u'
    functor_symbols = 'rho vel'
    expression = 'rho*vel'
    block = plasma
  []
  [audit_rho_momentum_y]
    type = ADParsedFunctorMaterial
    property_name = audit_rho_momentum_y
    functor_names = 'rho_neutral v'
    functor_symbols = 'rho vel'
    expression = 'rho*vel'
    block = plasma
  []
[]
[Postprocessors]
  [audit_mass_time]
    type = ADElementIntegralFunctorPostprocessor
    functor = drho_neutral_dt
    evaluation_type = CELL_AVERAGE
    block = plasma
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_source_EI415]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_neutral_mass_EI415
    evaluation_type = CELL_AVERAGE
    block = plasma
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_source_EI401]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_neutral_mass_EI401
    evaluation_type = CELL_AVERAGE
    block = plasma
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_source_EI417]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_neutral_mass_EI417
    evaluation_type = CELL_AVERAGE
    block = plasma
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_source_H25]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_neutral_mass_H25
    evaluation_type = CELL_AVERAGE
    block = plasma
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_pressure_l_1]
    type = DiscreteVariableResidualNorm
    variable = pressure
    block = plasma
    norm_type = l_1
    include_scaling_factor = false
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_pressure_l_2]
    type = DiscreteVariableResidualNorm
    variable = pressure
    block = plasma
    norm_type = l_2
    include_scaling_factor = false
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_pressure_l_inf]
    type = DiscreteVariableResidualNorm
    variable = pressure
    block = plasma
    norm_type = l_inf
    include_scaling_factor = false
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_u_l_1]
    type = DiscreteVariableResidualNorm
    variable = u
    block = plasma
    norm_type = l_1
    include_scaling_factor = false
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_u_l_2]
    type = DiscreteVariableResidualNorm
    variable = u
    block = plasma
    norm_type = l_2
    include_scaling_factor = false
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_u_l_inf]
    type = DiscreteVariableResidualNorm
    variable = u
    block = plasma
    norm_type = l_inf
    include_scaling_factor = false
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_v_l_1]
    type = DiscreteVariableResidualNorm
    variable = v
    block = plasma
    norm_type = l_1
    include_scaling_factor = false
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_v_l_2]
    type = DiscreteVariableResidualNorm
    variable = v
    block = plasma
    norm_type = l_2
    include_scaling_factor = false
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_v_l_inf]
    type = DiscreteVariableResidualNorm
    variable = v
    block = plasma
    norm_type = l_inf
    include_scaling_factor = false
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_flux_outlet_mass]
    type = BoundaryVolumetricFlowRate
    boundary = 'outlet'
    vel_x = u
    vel_y = v
    advected_quantity = rho_neutral
    rhie_chow_user_object = rc
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_flux_outlet_momentum_x]
    type = BoundaryVolumetricFlowRate
    boundary = 'outlet'
    vel_x = u
    vel_y = v
    advected_quantity = audit_rho_momentum_x
    rhie_chow_user_object = rc
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_flux_outlet_momentum_y]
    type = BoundaryVolumetricFlowRate
    boundary = 'outlet'
    vel_x = u
    vel_y = v
    advected_quantity = audit_rho_momentum_y
    rhie_chow_user_object = rc
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_flux_wall_mass]
    type = BoundaryVolumetricFlowRate
    boundary = 'plasma_electrode plasma_metal plasma_right plasma_cover plasma_wafer plasma_focus_ring'
    vel_x = u
    vel_y = v
    advected_quantity = rho_neutral
    rhie_chow_user_object = rc
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_flux_wall_momentum_x]
    type = BoundaryVolumetricFlowRate
    boundary = 'plasma_electrode plasma_metal plasma_right plasma_cover plasma_wafer plasma_focus_ring'
    vel_x = u
    vel_y = v
    advected_quantity = audit_rho_momentum_x
    rhie_chow_user_object = rc
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
  [audit_flux_wall_momentum_y]
    type = BoundaryVolumetricFlowRate
    boundary = 'plasma_electrode plasma_metal plasma_right plasma_cover plasma_wafer plasma_focus_ring'
    vel_x = u
    vel_y = v
    advected_quantity = audit_rho_momentum_y
    rhie_chow_user_object = rc
    execute_on = TIMESTEP_END
    outputs = fvm_audit
  []
[]
[Outputs]
  [fvm_audit]
    type = CSV
    file_base = /evidence/fvm-audit
    execute_on = TIMESTEP_END
    show = 'audit_mass_time audit_source_EI415 audit_source_EI401 audit_source_EI417 audit_source_H25 audit_pressure_l_1 audit_pressure_l_2 audit_pressure_l_inf audit_u_l_1 audit_u_l_2 audit_u_l_inf audit_v_l_1 audit_v_l_2 audit_v_l_inf audit_flux_outlet_mass audit_flux_outlet_momentum_x audit_flux_outlet_momentum_y audit_flux_wall_mass audit_flux_wall_momentum_x audit_flux_wall_momentum_y'
  []
[]
