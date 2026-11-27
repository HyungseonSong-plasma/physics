# Packaging/lookup smoke only. Not a plasma-science validation.
[Mesh]
  type = GeneratedMesh
  dim = 1
  nx = 2
[]
[Problem]
  solve = false
  kernel_coverage_check = false
[]
[FunctorMaterials]
  [state]
    type = ADGenericFunctorMaterial
    prop_names = 'e_energy_eV n_e c_O2 p T_g Y_O2 Y_O'
    prop_values = '3 1e15 1 100 300 0.5 0.5'
  []
  [electron]
    type = DDTransportMaterial
    species_id = e
    model = lookup
    table_file = /opt/physics/database/electron_moments.txt
    pressure = p
    gas_temperature = T_g
    bounds_policy = error
  []
  [reaction]
    type = EIRateCoefMaterial
    rate_table_file = /opt/physics/database/EI-401_O2_X.txt
    mean_energy = e_energy_eV
    electron_number_density = n_e
    target_molar_concentration = c_O2
    reaction_progress = R_test
  []
  [heavy]
    type = NVTransportMaterial
    temperature = T_g
    pressure = p
    transport_data_file = /opt/physics/database/neutral_transport.txt
    species = 'O2 O'
    mass_fractions = 'Y_O2 Y_O'
  []
[]
[Postprocessors]
  [mu]
    type = ElementAverageFunctorPostprocessor
    functor = e_mobility
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [diffusion]
    type = ElementAverageFunctorPostprocessor
    functor = e_diffusivity
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [reaction]
    type = ElementAverageFunctorPostprocessor
    functor = R_test
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [heavy_diffusion]
    type = ElementAverageFunctorPostprocessor
    functor = D_mix_O2
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]
[Executioner]
  type = Transient
  dt = 1
  num_steps = 1
[]
[Outputs]
  csv = true
[]
