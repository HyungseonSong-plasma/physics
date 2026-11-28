# Issue #202 RF absorbed-power validation fixture
#
# Peak-phasor convention:
#   E(t) = Re{ E_hat exp(+i omega t) }
#   Q_RF = 0.5 * sigma_R * |E_hat|^2
#
# Live plasma conductivity is retained; copper skin/proximity effects are not modeled.

# Derived angular frequency for the existing live conductivity closure.
frequency = ${Physics/Plasmas/Maxwell/frequency_Hz}
omega = '${fparse 2*3.141592653589793*frequency}'

[Mesh]
  coord_type = RZ
  rz_coord_axis = Y
  [base]
    type = FileMeshGenerator
    file = 'mesh.msh'
  []
  [remove_parent_boundaries]
    type = BoundaryDeletionGenerator
    input = base
    boundary_names = 'axis inlet outlet plasma_electrode plasma_metal plasma_right plasma_cover plasma_wafer plasma_focus_ring cover_outer_right wafer_electrode focus_ring_ground vacuum_outer_ground cover_vacuum cover_coil_ground vacuum_coil_ground'
  []
  [axis]
    type = ParsedGenerateSideset
    input = remove_parent_boundaries
    combinatorial_geometry = 'abs(x) < 1e-12'
    normal = '-1 0 0'
    new_sideset_name = axis
  []
  [outer_right]
    type = ParsedGenerateSideset
    input = axis
    combinatorial_geometry = 'abs(x - 0.2565) < 1e-10'
    normal = '1 0 0'
    new_sideset_name = outer_right
  []
  [outer_bottom]
    type = ParsedGenerateSideset
    input = outer_right
    combinatorial_geometry = 'abs(y) < 1e-12'
    normal = '0 -1 0'
    new_sideset_name = outer_bottom
  []
  [outer_top]
    type = ParsedGenerateSideset
    input = outer_bottom
    combinatorial_geometry = 'abs(y - 0.45) < 1e-10'
    normal = '0 1 0'
    new_sideset_name = outer_top
  []
[]

[Materials]

  [muN_t6]
    type = PiecewiseLinearInterpolationMaterial
    property = muN_t6
    variable = mean_energy_state_t6
    x = '1.6582129080000001 4.31921 5.2325200000000001 5.7327599999999999 6.12087 6.4566100000000004 6.7604100000000003 7.0419400000000003 7.3067799999999998 7.5585100000000001 7.7996499999999997 8.0319599999999998 8.4752899999999993 9.0998699999999992 9.68886 10.251300000000001 10.792899999999999 11.3179 11.828900000000001 12.328200000000001 12.8177 13.298999999999999 13.773099999999999 14.241099999999999 14.703799999999999 15.1625 15.6172 16.069199999999999 16.5185 16.965800000000002 17.4117 17.856200000000001 18.299800000000001 18.7425 19.185300000000002 19.627400000000002 20.069700000000001 20.5122 20.954899999999999 21.398299999999999 21.841899999999999 22.331223300000001'
    y = '3.0042586232000003e+24 1.7499179042e+24 1.4948326315999999e+24 1.3869720680999999e+24 1.3145533836e+24 1.2582624532999999e+24 1.2117971918999999e+24 1.1720095009e+24 1.137135641e+24 1.1060251801000001e+24 1.0780525831e+24 1.0524721931000001e+24 1.007262315e+24 9.5055788050000002e+23 9.0339093596000006e+23 8.6318929905000003e+23 8.2824981644999999e+23 7.9751609413999999e+23 7.7016124748999996e+23 7.4559239682999998e+23 7.2334482191000001e+23 7.0305193737999997e+23 6.8444600384000001e+23 6.6728462917000001e+23 6.5138432280999995e+23 6.3657048886000002e+23 6.2273413703999998e+23 6.0974303515000004e+23 5.9751814679000003e+23 5.8597198555999999e+23 5.7502978823000002e+23 5.6464129884999998e+23 5.5474554420999998e+23 5.4530138736000001e+23 5.3625386323999999e+23 5.2758545944999998e+23 5.1924871533000003e+23 5.1121718204e+23 5.0346932378e+23 4.9596392571000001e+23 4.8869978227000001e+23 4.8094320496000002e+23'
    block = plasma
  []
  [sigma_real_t6]
    type = ParsedMaterial
    property_name = sigma_real_t6
    coupled_variables = 'electron_density_state_t6 pressure_state_t6'
    material_property_names = 'muN_t6'
    constant_names = 'qe me kb Tg om'
    constant_expressions = '1.602176634e-19 9.1093837015e-31 1.380649e-23 300 ${omega}'
    expression = '(electron_density_state_t6*qe^2*(qe/(me*(muN_t6/(pressure_state_t6/(kb*Tg))))))/(me*((qe/(me*(muN_t6/(pressure_state_t6/(kb*Tg)))))^2+om^2))'
    block = plasma
  []
  [sigma_imag_t6]
    type = ParsedMaterial
    property_name = sigma_imag_t6
    coupled_variables = 'electron_density_state_t6 pressure_state_t6'
    material_property_names = 'muN_t6'
    constant_names = 'qe me kb Tg om'
    constant_expressions = '1.602176634e-19 9.1093837015e-31 1.380649e-23 300 ${omega}'
    expression = '-(electron_density_state_t6*qe^2*om)/(me*((qe/(me*(muN_t6/(pressure_state_t6/(kb*Tg)))))^2+om^2))'
    block = plasma
  []
  [rf_power_density_t6]
    type = ParsedMaterial
    property_name = q_rf
    coupled_variables = 'E_real E_imag'
    material_property_names = 'sigma_real_t6'
    expression = '0.5*sigma_real_t6*(E_real^2 + E_imag^2)'
    block = plasma
  []
[]



[Postprocessors]
  [E_real_l2]
    type = ElementL2Norm
    variable = E_real
  []
  [E_imag_l2]
    type = ElementL2Norm
    variable = E_imag
  []
  [P_abs]
    type = ElementIntegralMaterialProperty
    mat_prop = q_rf
    block = plasma
  []
  [rf_drive_scale_child]
    type = Receiver
    default = 4.7406324819558936
  []
[]

[Preconditioning]
  [smp]
    type = SMP
    full = true
  []
[]

[Executioner]
  type = Steady
  solve_type = NEWTON
  nl_abs_tol = 1e-11
  nl_rel_tol = 1e-10
  nl_max_its = 20
  l_tol = 1e-12
  l_max_its = 500
  petsc_options_iname = '-pc_type'
  petsc_options_value = 'lu'
[]

[Outputs]
  exodus = true
  csv = true
[]
[AuxVariables]
  [electron_density_state_t6]
    family = LAGRANGE
    order = FIRST
    block = plasma
    initial_condition = 1.0e15
  []
  [mean_energy_state_t6]
    family = LAGRANGE
    order = FIRST
    block = plasma
    initial_condition = 4.0
  []
  [pressure_state_t6]
    family = MONOMIAL
    order = CONSTANT
    block = plasma
    initial_condition = 1.3322
  []
[]
# Action owns RF operators, grounded boundaries and the three driven coil sources.
[Physics]
  [Plasmas]
    [Maxwell]
      frequency_Hz = 13.56e6
      coil_blocks = 'coil1 coil2 coil3'
      coil_current_A = 10.0
      coil_cross_section_m2 = 0.000162
      plasma_blocks = plasma
      vacuum_blocks = 'vacuum metal electrode top right bottom port coil1 coil2 coil3'
      dielectric_blocks = 'cover wafer focus_ring'
      relative_permittivities = '3.6 12.5 8.0'
      ground_boundaries = 'axis outer_right outer_bottom outer_top'
    []
  []
[]
