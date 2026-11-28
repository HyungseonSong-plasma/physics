# Issue #3 practical baseline dielectric pilot
# Derived from the accepted Issue #331 15 us Stage-B4 baseline evidence.
# Retains the first 100 x 1 ns baseline timesteps for a clean A/B discriminator.
# Cover relative permittivity eps_r=3.6 follows the original QVT geometry/material provenance.
# SEE is disabled in this first practical pilot; cover bulk-conductivity leakage is not yet modeled.

# Maxwell-only regions carry output fields, not Parent nonlinear equations.
# Keep kernel/material coverage checks active everywhere else.
[Problem]
  kernel_coverage_check = SKIP_LIST
  kernel_coverage_block_list = 'electrode top metal right bottom port'
  material_coverage_check = SKIP_LIST
  material_coverage_block_list = 'electrode top metal right bottom port'
[]

[Mesh]
  coord_type = RZ
  rz_coord_axis = Y
  [main]
    type = FileMeshGenerator
    file = 'mesh.msh'
  []
  # Keep the original boundary geometry, but retain only the Parent owner side.
  [owner_inlet]
    type = SideSetsBetweenSubdomainsGenerator
    input = main
    primary_block = plasma
    paired_block = 'port'
    included_boundaries = inlet
    new_boundary = parent_inlet
  []
  [owner_outlet]
    type = SideSetsBetweenSubdomainsGenerator
    input = owner_inlet
    primary_block = plasma
    paired_block = 'bottom'
    included_boundaries = outlet
    new_boundary = parent_outlet
  []
  [owner_plasma_electrode]
    type = SideSetsBetweenSubdomainsGenerator
    input = owner_outlet
    primary_block = plasma
    paired_block = 'electrode'
    included_boundaries = plasma_electrode
    new_boundary = parent_plasma_electrode
  []
  [owner_plasma_metal]
    type = SideSetsBetweenSubdomainsGenerator
    input = owner_plasma_electrode
    primary_block = plasma
    paired_block = 'metal'
    included_boundaries = plasma_metal
    new_boundary = parent_plasma_metal
  []
  [owner_plasma_right]
    type = SideSetsBetweenSubdomainsGenerator
    input = owner_plasma_metal
    primary_block = plasma
    paired_block = 'right'
    included_boundaries = plasma_right
    new_boundary = parent_plasma_right
  []
  [owner_wafer_electrode]
    type = SideSetsBetweenSubdomainsGenerator
    input = owner_plasma_right
    primary_block = wafer
    paired_block = 'electrode'
    included_boundaries = wafer_electrode
    new_boundary = parent_wafer_electrode
  []
  [owner_focus_ring_ground]
    type = SideSetsBetweenSubdomainsGenerator
    input = owner_wafer_electrode
    primary_block = focus_ring
    paired_block = 'electrode bottom metal'
    included_boundaries = focus_ring_ground
    new_boundary = parent_focus_ring_ground
  []
  [owner_cover_outer_right]
    type = SideSetsBetweenSubdomainsGenerator
    input = owner_focus_ring_ground
    primary_block = cover
    paired_block = 'top'
    included_boundaries = cover_outer_right
    new_boundary = parent_cover_outer_right
  []
  [owner_vacuum_outer_ground]
    type = SideSetsBetweenSubdomainsGenerator
    input = owner_cover_outer_right
    primary_block = vacuum
    paired_block = 'top'
    included_boundaries = vacuum_outer_ground
    new_boundary = parent_vacuum_outer_ground
  []
  [drop_two_sided_cut_boundaries]
    type = BoundaryDeletionGenerator
    input = owner_vacuum_outer_ground
    boundary_names = 'inlet outlet plasma_electrode plasma_metal plasma_right wafer_electrode focus_ring_ground cover_outer_right vacuum_outer_ground'
  []
  [restore_parent_boundary_names]
    type = RenameBoundaryGenerator
    input = drop_two_sided_cut_boundaries
    old_boundary = 'parent_inlet parent_outlet parent_plasma_electrode parent_plasma_metal parent_plasma_right parent_wafer_electrode parent_focus_ring_ground parent_cover_outer_right parent_vacuum_outer_ground'
    new_boundary = 'inlet outlet plasma_electrode plasma_metal plasma_right wafer_electrode focus_ring_ground cover_outer_right vacuum_outer_ground'
  []
  [plasma_cover_owner]
    type = SideSetsBetweenSubdomainsGenerator
    primary_block = plasma
    paired_block = cover
    new_boundary = plasma_cover_owner
    input = restore_parent_boundary_names
  []
  [plasma_wafer_owner]
    type = SideSetsBetweenSubdomainsGenerator
    primary_block = plasma
    paired_block = wafer
    new_boundary = plasma_wafer_owner
    input = plasma_cover_owner
  []
  [plasma_focus_ring_owner]
    type = SideSetsBetweenSubdomainsGenerator
    primary_block = plasma
    paired_block = focus_ring
    new_boundary = plasma_focus_ring_owner
    input = plasma_wafer_owner
  []
  [cover_surface_block]
    type = LowerDBlockFromSidesetGenerator
    input = plasma_focus_ring_owner
    sidesets = plasma_cover_owner
    new_block_id = 30
    new_block_name = cover_surface
  []
  [wafer_surface_block]
    type = LowerDBlockFromSidesetGenerator
    input = cover_surface_block
    sidesets = plasma_wafer_owner
    new_block_id = 31
    new_block_name = wafer_surface
  []
  [focus_ring_surface_block]
    type = LowerDBlockFromSidesetGenerator
    input = wafer_surface_block
    sidesets = plasma_focus_ring_owner
    new_block_id = 32
    new_block_name = focus_ring_surface
  []
[]

[GlobalParams]
  rhie_chow_user_object = rc
  advected_interp_method = upwind
  velocity_interp_method = rc
  two_term_boundary_expansion = true
[]

[UserObjects]
  [rc]
    type = INSFVRhieChowInterpolator
    u = u
    v = v
    pressure = pressure
    block = plasma
  []
[]

[Variables]
  [u]
    type = BoundaryINSFVVelocityVariable
    initial_condition = 0.0
    block = plasma
  []
  [v]
    type = BoundaryINSFVVelocityVariable
    initial_condition = 0.0
    block = plasma
  []
  [pressure]
    type = BoundaryINSFVPressureVariable
    block = plasma
  []
  [w_O2s]
    type = BoundaryINSFVScalarFieldVariable
    initial_condition = 1.000010000100001e-05
    block = plasma
  []
  [w_O]
    type = BoundaryINSFVScalarFieldVariable
    initial_condition = 5.0000500005000049e-06
    block = plasma
  []
  [w_Os]
    type = BoundaryINSFVScalarFieldVariable
    initial_condition = 5.0000500005000049e-06
    block = plasma
  []
  [potential]
    family = LAGRANGE
    order = FIRST
    initial_condition = 0.0
    block = 'plasma cover wafer focus_ring vacuum coil1 coil2 coil3'
  []
  [sigma_s]
    family = MONOMIAL
    order = CONSTANT
    initial_condition = 0.0
    block = cover_surface
  []
  [sigma_wafer]
    family = MONOMIAL
    order = CONSTANT
    initial_condition = 0.0
    block = wafer_surface
  []
  [sigma_focus_ring]
    family = MONOMIAL
    order = CONSTANT
    initial_condition = 0.0
    block = focus_ring_surface
  []
[]

[FunctorMaterials]
  [constants]
    type = ADGenericFunctorMaterial
    prop_names = 'carrier_one'
    prop_values = '1.0'
    block = plasma
  []
  [electron_molar_density]
    type = ADParsedFunctorMaterial
    property_name = electron_molar_density
    functor_names = 'log_e'
    functor_symbols = 'u'
    expression = 'exp(u)'
    block = plasma
  []
  [ion_molar_density]
    type = ADParsedFunctorMaterial
    property_name = ion_molar_density
    functor_names = 'log_O2p'
    functor_symbols = 'u'
    expression = 'exp(u)'
    block = plasma
  []
  [ion_physical_density]
    type = ADParsedFunctorMaterial
    property_name = n_i_physical
    functor_names = 'ion_molar_density'
    functor_symbols = 'ci'
    expression = '6.02214076e23*ci'
    block = plasma
  []
  [negative_ion_molar_density]
    type = ADParsedFunctorMaterial
    property_name = negative_ion_molar_density
    functor_names = 'log_Om'
    functor_symbols = 'u'
    expression = 'exp(u)'
    block = plasma
  []
  [negative_ion_physical_density]
    type = ADParsedFunctorMaterial
    property_name = n_m_physical
    functor_names = 'negative_ion_molar_density'
    functor_symbols = 'cm'
    expression = '6.02214076e23*cm'
    block = plasma
  []
  [atomic_positive_ion_molar_density]
    type = ADParsedFunctorMaterial
    property_name = atomic_positive_ion_molar_density
    functor_names = 'log_Op'
    functor_symbols = 'u'
    expression = 'exp(u)'
    block = plasma
  []
  [atomic_positive_ion_physical_density]
    type = ADParsedFunctorMaterial
    property_name = n_op_physical
    functor_names = 'atomic_positive_ion_molar_density'
    functor_symbols = 'cop'
    expression = '6.02214076e23*cop'
    block = plasma
  []
  [electron_molar_energy_density]
    type = ADParsedFunctorMaterial
    property_name = electron_molar_energy_density
    functor_names = 'log_e_energy'
    functor_symbols = 'ue'
    expression = 'exp(ue)'
    block = plasma
  []
  [electron_physical_energy_density]
    type = ADParsedFunctorMaterial
    property_name = electron_energy_density_eV_m3
    functor_names = 'electron_molar_energy_density'
    functor_symbols = 'we'
    expression = '6.02214076e23*we'
    block = plasma
  []
  [charge_number_density]
    type = ADParsedFunctorMaterial
    property_name = charge_number_density
    functor_names = 'n_i_physical n_op_physical n_e_physical n_m_physical'
    functor_symbols = 'ni nop ne nm'
    expression = 'ni+nop-ne-nm'
    block = plasma
  []
  [charge_density]
    type = ADParsedFunctorMaterial
    property_name = charge_density_C_m3
    functor_names = 'charge_number_density'
    functor_symbols = 'nq'
    expression = '1.602176634e-19*nq'
    block = plasma
  []
  [poisson_source]
    type = ADParsedFunctorMaterial
    property_name = poisson_source
    functor_names = 'charge_number_density'
    functor_symbols = 'nq'
    expression = '1.8095128179727827e-08*nq'
    block = plasma
  []

  [neutral_flow_constants]
    type = ADGenericFunctorMaterial
    prop_names = 'mu_flow'
    prop_values = '2.0000000000000002e-05'
    block = plasma
  []

  [neutral_state_dot_aliases]
    type = ADGenericFunctorMaterial
    prop_names = 'p_state wO_state wOs_state'
    prop_values = 'pressure w_O w_Os'
    define_dot_functors = true
    block = plasma
  []

  [neutral_O2_constraint]
    type = ADParsedFunctorMaterial
    property_name = w_O2_constraint
    functor_names = 'w_O2s w_O w_Os'
    functor_symbols = 's o a'
    expression = '1.0-s-o-a'
    block = plasma
  []

  [neutral_mean_molar_mass]
    type = ADParsedFunctorMaterial
    property_name = Mn_neutral
    functor_names = 'w_O2_constraint w_O2s w_O w_Os'
    functor_symbols = 'm0 m1 m2 m3'
    expression = '1.0/(m0/0.032+m1/0.032+m2/0.016+m3/0.016)'
    block = plasma
  []

  [neutral_density]
    type = ADParsedFunctorMaterial
    property_name = rho_neutral
    functor_names = 'pressure Mn_neutral temperature'
    functor_symbols = 'prs mol tmp'
    expression = 'prs*mol/(8.31446*tmp)'
    block = plasma
  []

  # A = w_O + w_O*. Molecular redistribution O2 <-> O2* leaves Mn unchanged.
  # Mn = 0.032/(1+A), hence dMn/dt = -31.25*Mn^2*dA/dt.
  [neutral_mean_molar_mass_dot]
    type = ADParsedFunctorMaterial
    property_name = dMn_neutral_dt
    functor_names = 'Mn_neutral dwO_state_dt dwOs_state_dt'
    functor_symbols = 'mn dwo dwos'
    expression = '-31.25*mn*mn*(dwo+dwos)'
    block = plasma
  []

  # Isothermal Stage-B flow: rho = pressure*Mn/(R*Tg).
  [neutral_density_dot]
    type = ADParsedFunctorMaterial
    property_name = drho_neutral_dt
    functor_names = 'pressure Mn_neutral dp_state_dt dMn_neutral_dt temperature'
    functor_symbols = 'prs mn dp dmn tmp'
    expression = '(mn*dp+prs*dmn)/(8.31446*tmp)'
    block = plasma
  []

  [neutral_sum_w]
    type = ADParsedFunctorMaterial
    property_name = neutral_sum_w_functor
    functor_names = 'w_O2_constraint w_O2s w_O w_Os'
    functor_symbols = 'q0 q1 q2 q3'
    expression = 'q0+q1+q2+q3'
    block = plasma
  []

  [rho_w_O2]
    type = ADParsedFunctorMaterial
    property_name = rho_w_O2
    functor_names = 'rho_neutral w_O2_constraint'
    functor_symbols = 'rho w'
    expression = 'rho*w'
    block = plasma
  []
  [rho_w_O2s]
    type = ADParsedFunctorMaterial
    property_name = rho_w_O2s
    functor_names = 'rho_neutral w_O2s'
    functor_symbols = 'rho w'
    expression = 'rho*w'
    block = plasma
  []
  [rho_w_O]
    type = ADParsedFunctorMaterial
    property_name = rho_w_O
    functor_names = 'rho_neutral w_O'
    functor_symbols = 'rho w'
    expression = 'rho*w'
    block = plasma
  []
  [rho_w_Os]
    type = ADParsedFunctorMaterial
    property_name = rho_w_Os
    functor_names = 'rho_neutral w_Os'
    functor_symbols = 'rho w'
    expression = 'rho*w'
    block = plasma
  []

  [neutral_transport]
    type = NVTransportMaterial
    temperature = temperature
    pressure = pressure
    transport_data_file = 'neutral_transport.txt'
    species = 'O2 O2s O Os'
    mass_fractions = 'w_O2_constraint w_O2s w_O w_Os'
    D_mix_names = 'D_mix_O2 D_mix_O2s D_mix_O D_mix_Os'
    D_T_names = 'D_T_O2 D_T_O2s D_T_O D_T_Os'
    kT_names = 'kT_O2 kT_O2s kT_O kT_Os'
    block = plasma
  []
  [ei02_o2_concentration]
    type = ADParsedFunctorMaterial
    property_name = c_O2_EI02
    functor_names = 'rho_neutral w_O2_constraint'
    functor_symbols = 'rho w'
    expression = 'rho*w/0.032000000000000001'
    block = plasma
  []
  [ei02_progress]
    type = EIRateCoefMaterial
    rate_table_file = o2_elastic.txt
    mean_energy = e_energy_eV
    electron_number_density = n_e_physical
    target_molar_concentration = c_O2_EI02
    reaction_progress = R_EI02
    block = plasma
  []
  [ei02_delta_e]
    type = ADParsedFunctorMaterial
    property_name = delta_epsilon_EI02_eV
    functor_names = 'e_energy_eV temperature'
    functor_symbols = 'eps Tg'
    expression = '5.1429366456827657e-05*((2.0/3.0)*eps-8.6173332621449999e-05*Tg)'
    block = plasma
  []
  [ei02_energy_source]
    type = ADParsedFunctorMaterial
    property_name = elastic_energy_source_EI02
    functor_names = 'delta_epsilon_EI02_eV R_EI02'
    functor_symbols = 'de R'
    expression = '-de*R'
    block = plasma
  []
  [ei17_o_concentration]
    type = ADParsedFunctorMaterial
    property_name = c_O_EI17
    functor_names = 'rho_neutral w_O'
    functor_symbols = 'rho w'
    expression = 'rho*w/0.016'
    block = plasma
  []
  [ei17_progress]
    type = EIRateCoefMaterial
    rate_table_file = o_elastic.txt
    mean_energy = e_energy_eV
    electron_number_density = n_e_physical
    target_molar_concentration = c_O_EI17
    reaction_progress = R_EI17
    block = plasma
  []
  [ei17_delta_energy]
    type = ADParsedFunctorMaterial
    property_name = delta_epsilon_EI17_eV
    functor_names = 'e_energy_eV temperature'
    functor_symbols = 'eps Tg'
    expression = '0.00010285873291365531*((2.0/3.0)*eps-8.6173332621449999e-05*Tg)'
    block = plasma
  []
  [ei17_electron_energy_exchange]
    type = ADParsedFunctorMaterial
    property_name = S_electron_energy_EI17
    functor_names = 'delta_epsilon_EI17_eV R_EI17'
    functor_symbols = 'de R'
    expression = '-de*R'
    block = plasma
  []
  [ei415_o2_concentration]
    type = ADParsedFunctorMaterial
    property_name = c_O2_EI415
    functor_names = 'rho_neutral w_O2_constraint'
    functor_symbols = 'rho w'
    expression = 'rho*w/0.032000000000000001'
    block = plasma
  []
  [ei415_progress]
    type = EIRateCoefMaterial
    rate_table_file = 'EI-415_O2_X.txt'
    mean_energy = e_energy_eV
    electron_number_density = n_e_physical
    target_molar_concentration = c_O2_EI415
    reaction_progress = R_EI415
    block = plasma
  []
  [ei415_electron_source]
    type = ADParsedFunctorMaterial
    property_name = S_electron_molar_EI415
    functor_names = 'R_EI415'
    functor_symbols = 'R'
    expression = 'R'
    block = plasma
  []
  [ei415_o2p_source]
    type = ADParsedFunctorMaterial
    property_name = S_O2p_molar_EI415
    functor_names = 'R_EI415'
    functor_symbols = 'R'
    expression = 'R'
    block = plasma
  []
  [ei415_neutral_mass_source]
    type = ADParsedFunctorMaterial
    property_name = S_neutral_mass_EI415
    functor_names = 'R_EI415'
    functor_symbols = 'R'
    expression = '-0.032000000000000001*R'
    block = plasma
  []
  [ei415_o2p_mass_source]
    type = ADParsedFunctorMaterial
    property_name = S_O2p_mass_EI415
    functor_names = 'R_EI415'
    functor_symbols = 'R'
    expression = '0.032000000000000001*R'
    block = plasma
  []
  [ei415_energy_source]
    type = ADParsedFunctorMaterial
    property_name = S_electron_energy_molar_EI415
    functor_names = 'R_EI415'
    functor_symbols = 'R'
    expression = '-12.06*R'
    block = plasma
  []
  [ei415_heavy_mass_closure]
    type = ADParsedFunctorMaterial
    property_name = S_heavy_mass_closure_EI415
    functor_names = 'S_neutral_mass_EI415 S_O2p_mass_EI415'
    functor_symbols = 'Sn Si'
    expression = 'Sn+Si'
    block = plasma
  []
  [ei415_charge_closure]
    type = ADParsedFunctorMaterial
    property_name = S_charge_molar_closure_EI415
    functor_names = 'S_electron_molar_EI415 S_O2p_molar_EI415'
    functor_symbols = 'Se Si'
    expression = 'Si-Se'
    block = plasma
  []
  [ei401_o2_concentration]
    type = ADParsedFunctorMaterial
    property_name = c_O2_EI401
    functor_names = 'rho_neutral w_O2_constraint'
    functor_symbols = 'rho w'
    expression = 'rho*w/0.032000000000000001'
    block = plasma
  []
  [ei401_progress]
    type = EIRateCoefMaterial
    rate_table_file = 'EI-401_O2_X.txt'
    mean_energy = e_energy_eV
    electron_number_density = n_e_physical
    target_molar_concentration = c_O2_EI401
    reaction_progress = R_EI401
    block = plasma
  []
  [ei401_electron_source]
    type = ADParsedFunctorMaterial
    property_name = S_electron_molar_EI401
    functor_names = 'R_EI401'
    functor_symbols = 'R'
    expression = '-R'
    block = plasma
  []
  [ei401_om_source]
    type = ADParsedFunctorMaterial
    property_name = S_Om_molar_EI401
    functor_names = 'R_EI401'
    functor_symbols = 'R'
    expression = 'R'
    block = plasma
  []
  [ei401_o_mass_source]
    type = ADParsedFunctorMaterial
    property_name = S_O_mass_EI401
    functor_names = 'R_EI401'
    functor_symbols = 'R'
    expression = '0.016*R'
    block = plasma
  []
  [ei401_om_mass_source]
    type = ADParsedFunctorMaterial
    property_name = S_Om_mass_EI401
    functor_names = 'R_EI401'
    functor_symbols = 'R'
    expression = '0.016*R'
    block = plasma
  []
  [ei401_o2_mass_source_implicit]
    type = ADParsedFunctorMaterial
    property_name = S_O2_mass_implicit_EI401
    functor_names = 'R_EI401'
    functor_symbols = 'R'
    expression = '-0.032000000000000001*R'
    block = plasma
  []
  [ei401_neutral_mass_source]
    type = ADParsedFunctorMaterial
    property_name = S_neutral_mass_EI401
    functor_names = 'R_EI401'
    functor_symbols = 'R'
    expression = '-0.016*R'
    block = plasma
  []
  [ei401_heavy_mass_closure]
    type = ADParsedFunctorMaterial
    property_name = S_heavy_mass_closure_EI401
    functor_names = 'S_O2_mass_implicit_EI401 S_O_mass_EI401 S_Om_mass_EI401'
    functor_symbols = 'So2 So Som'
    expression = 'So2+So+Som'
    block = plasma
  []
  [ei401_charge_molar_closure]
    type = ADParsedFunctorMaterial
    property_name = S_charge_molar_closure_EI401
    functor_names = 'S_electron_molar_EI401 S_Om_molar_EI401'
    functor_symbols = 'Se Som'
    expression = 'Se+Som'
    block = plasma
  []
  [legacy8_h05_ei417_o2_target]
    type = ADParsedFunctorMaterial
    property_name = c_O2_EI417
    functor_names = 'rho_neutral w_O2_constraint'
    functor_symbols = 'rho w'
    expression = 'rho*w/0.032'
    block = plasma
  []
  [legacy8_h05_ei417_progress]
    type = EIRateCoefMaterial
    rate_table_file = 'EI-417_O2_X.txt'
    mean_energy = e_energy_eV
    electron_number_density = n_e_physical
    target_molar_concentration = c_O2_EI417
    reaction_progress = R_EI417
    block = plasma
  []
  [legacy8_h05_ei417_electron_source]
    type = ADParsedFunctorMaterial
    property_name = S_e_molar_EI417
    functor_names = 'R_EI417'
    functor_symbols = 'R'
    expression = 'R'
    block = plasma
  []
  [legacy8_h05_ei417_op_source]
    type = ADParsedFunctorMaterial
    property_name = S_Op_molar_EI417
    functor_names = 'R_EI417'
    functor_symbols = 'R'
    expression = 'R'
    block = plasma
  []
  [legacy8_h05_ei417_o_mass_source]
    type = ADParsedFunctorMaterial
    property_name = S_O_mass_EI417
    functor_names = 'R_EI417'
    functor_symbols = 'R'
    expression = '0.016*R'
    block = plasma
  []
  [legacy8_h05_ei417_constrained_o2_mass_sink]
    type = ADParsedFunctorMaterial
    property_name = S_O2_mass_EI417
    functor_names = 'R_EI417'
    functor_symbols = 'R'
    expression = '-0.032*R'
    block = plasma
  []
  [legacy8_h05_ei417_op_mass_source]
    type = ADParsedFunctorMaterial
    property_name = S_Op_mass_EI417
    functor_names = 'R_EI417'
    functor_symbols = 'R'
    expression = '0.016*R'
    block = plasma
  []
  [legacy8_h05_ei417_neutral_mass_sink]
    type = ADParsedFunctorMaterial
    property_name = S_neutral_mass_EI417
    functor_names = 'R_EI417'
    functor_symbols = 'R'
    expression = '-0.016*R'
    block = plasma
  []
  [legacy8_h05_ei417_energy_sink]
    type = ADParsedFunctorMaterial
    property_name = S_energy_EI417
    functor_names = 'R_EI417'
    functor_symbols = 'R'
    expression = '-17.0*R'
    block = plasma
  []
  [legacy8_h05_ei417_heavy_mass_closure]
    type = ADParsedFunctorMaterial
    property_name = S_heavy_mass_closure_EI417
    functor_names = 'S_O2_mass_EI417 S_O_mass_EI417 S_Op_mass_EI417'
    functor_symbols = 'a b c'
    expression = 'a+b+c'
    block = plasma
  []
  [legacy8_h05_ei417_neutral_mass_closure]
    type = ADParsedFunctorMaterial
    property_name = S_neutral_mass_closure_EI417
    functor_names = 'S_O2_mass_EI417 S_O_mass_EI417 S_neutral_mass_EI417'
    functor_symbols = 'a b c'
    expression = 'a+b-c'
    block = plasma
  []
  [legacy8_h05_ei417_charge_closure]
    type = ADParsedFunctorMaterial
    property_name = S_charge_closure_EI417
    functor_names = 'S_e_molar_EI417 S_Op_molar_EI417'
    functor_symbols = 'el op'
    expression = 'op-el'
    block = plasma
  []
  [legacy8_407_o2_target]
    type = ADParsedFunctorMaterial
    property_name = c_O2_EI407
    functor_names = 'rho_neutral w_O2_constraint'
    functor_symbols = 'rho w'
    expression = 'rho*w/0.032'
    block = plasma
  []
  [legacy8_407_progress]
    type = EIRateCoefMaterial
    rate_table_file = 'EI-407_O2_X.txt'
    mean_energy = e_energy_eV
    electron_number_density = n_e_physical
    target_molar_concentration = c_O2_EI407
    reaction_progress = R_EI407
    block = plasma
  []
  [legacy8_407_o2s_mass]
    type = ADParsedFunctorMaterial
    property_name = S_O2s_mass_EI407
    functor_names = 'R_EI407'
    functor_symbols = 'R'
    expression = '0.032*R'
    block = plasma
  []
  [legacy8_407_o2_constrained_sink]
    type = ADParsedFunctorMaterial
    property_name = S_O2_implicit_EI407
    functor_names = 'R_EI407'
    functor_symbols = 'R'
    expression = '-0.032*R'
    block = plasma
  []
  [legacy8_407_energy]
    type = ADParsedFunctorMaterial
    property_name = S_energy_EI407
    functor_names = 'R_EI407'
    functor_symbols = 'R'
    expression = '-0.977*R'
    block = plasma
  []
  [legacy8_407_mass_closure]
    type = ADParsedFunctorMaterial
    property_name = S_mass_closure_EI407
    functor_names = 'S_O2s_mass_EI407 S_O2_implicit_EI407'
    functor_symbols = 'a b'
    expression = 'a+b'
    block = plasma
  []
  [ei2069_o2a_molar_concentration]
    type = ADParsedFunctorMaterial
    property_name = c_O2a_EI2069
    functor_names = 'rho_neutral w_O2s'
    functor_symbols = 'rho wa'
    expression = 'rho*wa/0.032'
    block = plasma
  []
  [ei2069_progress]
    type = EIRateCoefMaterial
    rate_table_file = 'EI-2069_O2_a1Delta.txt'
    mean_energy = e_energy_eV
    electron_number_density = n_e_physical
    target_molar_concentration = c_O2a_EI2069
    reaction_progress = R_EI2069
    block = plasma
  []
  [ei2069_o2a_mass_sink]
    type = ADParsedFunctorMaterial
    property_name = S_O2a_mass_EI2069
    functor_names = 'R_EI2069'
    functor_symbols = 'R'
    expression = '-0.032*R'
    block = plasma
  []
  [ei2069_atomic_oxygen_birth]
    type = ADParsedFunctorMaterial
    property_name = S_O_mass_EI2069
    functor_names = 'R_EI2069'
    functor_symbols = 'R'
    expression = '0.032*R'
    block = plasma
  []
  [ei2069_energy_sink]
    type = ADParsedFunctorMaterial
    property_name = S_energy_EI2069
    functor_names = 'R_EI2069'
    functor_symbols = 'R'
    expression = '-5.02*R'
    block = plasma
  []
  [ei2069_heavy_mass_closure]
    type = ADParsedFunctorMaterial
    property_name = S_heavy_mass_closure_EI2069
    functor_names = 'S_O2a_mass_EI2069 S_O_mass_EI2069'
    functor_symbols = 'a b'
    expression = 'a+b'
    block = plasma
  []
  [h25_op_target]
    type = ADParsedFunctorMaterial
    property_name = c_Op_H25
    functor_names = 'log_Op'
    functor_symbols = 'lncp'
    expression = 'exp(lncp)'
    block = plasma
  []
  [h25_o2_target]
    type = ADParsedFunctorMaterial
    property_name = c_O2_H25
    functor_names = 'rho_neutral w_O2_constraint'
    functor_symbols = 'rho w2'
    expression = 'rho*w2/0.032'
    block = plasma
  []
  [h25_fixed_tgas]
    type = ADParsedFunctorMaterial
    property_name = Tg_H25_K
    expression = '300.0'
    block = plasma
  []
  [h25_progress]
    type = ADParsedFunctorMaterial
    property_name = R_H25
    functor_names = 'c_Op_H25 c_O2_H25 Tg_H25_K'
    functor_symbols = 'cp c2 tg'
    expression = '1.204428152e7*(300.0/tg)^0.4*cp*c2'
    block = plasma
  []
  [h25_op_loss]
    type = ADParsedFunctorMaterial
    property_name = S_Op_molar_H25
    functor_names = 'R_H25'
    functor_symbols = 'R'
    expression = '-R'
    block = plasma
  []
  [h25_o2p_birth]
    type = ADParsedFunctorMaterial
    property_name = S_O2p_molar_H25
    functor_names = 'R_H25'
    functor_symbols = 'R'
    expression = 'R'
    block = plasma
  []
  [h25_o_mass]
    type = ADParsedFunctorMaterial
    property_name = S_O_mass_H25
    functor_names = 'R_H25'
    functor_symbols = 'R'
    expression = '0.016*R'
    block = plasma
  []
  [h25_o2_mass_implicit]
    type = ADParsedFunctorMaterial
    property_name = S_O2_mass_H25_implicit
    functor_names = 'R_H25'
    functor_symbols = 'R'
    expression = '-0.032*R'
    block = plasma
  []
  [h25_neutral_mass]
    type = ADParsedFunctorMaterial
    property_name = S_neutral_mass_H25
    functor_names = 'R_H25'
    functor_symbols = 'R'
    expression = '-0.016*R'
    block = plasma
  []
  [h25_charge_closure]
    type = ADParsedFunctorMaterial
    property_name = S_charge_closure_H25
    functor_names = 'S_Op_molar_H25 S_O2p_molar_H25'
    functor_symbols = 'op ip'
    expression = 'op+ip'
    block = plasma
  []
  [h25_heavy_mass_closure]
    type = ADParsedFunctorMaterial
    property_name = S_heavy_mass_closure_H25
    functor_names = 'S_Op_molar_H25 S_O2p_molar_H25 S_O_mass_H25 S_O2_mass_H25_implicit'
    functor_symbols = 'op ip o o2'
    expression = '0.016*op+0.032*ip+o+o2'
    block = plasma
  []
  [h25_neutral_mass_closure]
    type = ADParsedFunctorMaterial
    property_name = S_neutral_mass_closure_H25
    functor_names = 'S_neutral_mass_H25 S_O_mass_H25 S_O2_mass_H25_implicit'
    functor_symbols = 'total o o2'
    expression = 'total-o-o2'
    block = plasma
  []
  [h25_oxygen_atoms_closure]
    type = ADParsedFunctorMaterial
    property_name = S_oxygen_nuclei_closure_H25
    functor_names = 'S_Op_molar_H25 S_O2p_molar_H25 R_H25'
    functor_symbols = 'op ip prog'
    expression = 'op+2*ip-prog'
    block = plasma
  []
[]

[Materials]
  [eps_plasma]
    type = ADGenericConstantMaterial
    prop_names = 'relative_permittivity'
    prop_values = '1.0'
    block = plasma
  []
  [eps_cover]
    type = ADGenericConstantMaterial
    prop_names = 'relative_permittivity'
    prop_values = '3.6'
    block = cover
  []
  [eps_wafer]
    type = ADGenericConstantMaterial
    prop_names = 'relative_permittivity'
    prop_values = '12.5'
    block = wafer
  []
  [eps_focus_ring]
    type = ADGenericConstantMaterial
    prop_names = 'relative_permittivity'
    prop_values = '8.0'
    block = focus_ring
  []
  [eps_vacuum]
    type = ADGenericConstantMaterial
    prop_names = 'relative_permittivity'
    prop_values = '1.0'
    block = 'vacuum coil1 coil2 coil3'
  []
  [cover_surface_anchor]
    type = ADGenericConstantMaterial
    prop_names = 'cover_surface_anchor'
    prop_values = '0.0'
    block = cover_surface
  []
  [wafer_surface_anchor]
    type = ADGenericConstantMaterial
    prop_names = 'wafer_surface_anchor'
    prop_values = '0.0'
    block = wafer_surface
  []
  [focus_ring_surface_anchor]
    type = ADGenericConstantMaterial
    prop_names = 'focus_ring_surface_anchor'
    prop_values = '0.0'
    block = focus_ring_surface
  []
  [muN_rf_t6]
    type = PiecewiseLinearInterpolationMaterial
    property = muN_rf_t6
    variable = mean_energy_rf_state_t6
    x = '1.6582129080000001 4.31921 5.2325200000000001 5.7327599999999999 6.12087 6.4566100000000004 6.7604100000000003 7.0419400000000003 7.3067799999999998 7.5585100000000001 7.7996499999999997 8.0319599999999998 8.4752899999999993 9.0998699999999992 9.68886 10.251300000000001 10.792899999999999 11.3179 11.828900000000001 12.328200000000001 12.8177 13.298999999999999 13.773099999999999 14.241099999999999 14.703799999999999 15.1625 15.6172 16.069199999999999 16.5185 16.965800000000002 17.4117 17.856200000000001 18.299800000000001 18.7425 19.185300000000002 19.627400000000002 20.069700000000001 20.5122 20.954899999999999 21.398299999999999 21.841899999999999 22.331223300000001'
    y = '3.0042586232000003e+24 1.7499179042e+24 1.4948326315999999e+24 1.3869720680999999e+24 1.3145533836e+24 1.2582624532999999e+24 1.2117971918999999e+24 1.1720095009e+24 1.137135641e+24 1.1060251801000001e+24 1.0780525831e+24 1.0524721931000001e+24 1.007262315e+24 9.5055788050000002e+23 9.0339093596000006e+23 8.6318929905000003e+23 8.2824981644999999e+23 7.9751609413999999e+23 7.7016124748999996e+23 7.4559239682999998e+23 7.2334482191000001e+23 7.0305193737999997e+23 6.8444600384000001e+23 6.6728462917000001e+23 6.5138432280999995e+23 6.3657048886000002e+23 6.2273413703999998e+23 6.0974303515000004e+23 5.9751814679000003e+23 5.8597198555999999e+23 5.7502978823000002e+23 5.6464129884999998e+23 5.5474554420999998e+23 5.4530138736000001e+23 5.3625386323999999e+23 5.2758545944999998e+23 5.1924871533000003e+23 5.1121718204e+23 5.0346932378e+23 4.9596392571000001e+23 4.8869978227000001e+23 4.8094320496000002e+23'
    block = plasma
  []
  [sigma_real_rf_t6]
    type = ParsedMaterial
    property_name = sigma_real_rf_t6
    coupled_variables = 'log_ne_rf_state_t6 pressure_rf_state_t6'
    material_property_names = 'muN_rf_t6'
    constant_names = 'NA qe me kb Tg om'
    constant_expressions = '6.02214076e23 1.602176634e-19 9.1093837015e-31 1.380649e-23 300 85199992.765355185'
    expression = '(exp(log_ne_rf_state_t6)*NA*qe^2*(qe/(me*(muN_rf_t6/(pressure_rf_state_t6/(kb*Tg))))))/(me*((qe/(me*(muN_rf_t6/(pressure_rf_state_t6/(kb*Tg)))))^2+om^2))'
    block = plasma
  []
  [q_rf_raw_t6]
    type = ParsedMaterial
    property_name = q_rf_raw_t6
    coupled_variables = 'E_real_rf_t6 E_imag_rf_t6'
    material_property_names = 'sigma_real_rf_t6'
    expression = '0.5*sigma_real_rf_t6*(E_real_rf_t6^2 + E_imag_rf_t6^2)'
    block = plasma
  []
  [q_rf_scaled_t6]
    type = ParsedMaterial
    property_name = q_rf_scaled_t6
    coupled_variables = 'E_real_rf_t6 E_imag_rf_t6'
    material_property_names = 'sigma_real_rf_t6'
    constant_names = 'scale'
    constant_expressions = '${rf_scale_t6}'
    expression = 'scale*0.5*sigma_real_rf_t6*(E_real_rf_t6^2 + E_imag_rf_t6^2)'
    block = plasma
  []
  [q_rf_eV_mol_t6]
    type = ParsedMaterial
    property_name = q_rf_eV_mol_t6
    coupled_variables = 'E_real_rf_t6 E_imag_rf_t6'
    material_property_names = 'sigma_real_rf_t6'
    constant_names = 'scale enabled F'
    constant_expressions = '${rf_scale_t6} ${source_enable_t6} ${faraday_t6}'
    expression = 'enabled*scale*0.5*sigma_real_rf_t6*(E_real_rf_t6^2 + E_imag_rf_t6^2)/F'
    block = plasma
  []
[]

[Kernels]
  [phi_diffusion]
    type = ADMatDiffusion
    variable = potential
    diffusivity = relative_permittivity
    block = 'plasma cover wafer focus_ring vacuum coil1 coil2 coil3'
  []
  [phi_source]
    type = FunctorKernel
    variable = potential
    functor = poisson_source
    functor_on_rhs = true
    block = plasma
  []
  [sigma_time]
    type = ADTimeDerivative
    variable = sigma_s
    block = cover_surface
  []
  [sigma_surface_current]
    type = PhysicsLowerDSurfaceCurrent
    variable = sigma_s
    surface_current_density = cover_net_surface_current_density
    block = cover_surface
  []
  [sigma_wafer_time]
    type = ADTimeDerivative
    variable = sigma_wafer
    block = wafer_surface
  []
  [sigma_wafer_surface_current]
    type = PhysicsLowerDSurfaceCurrent
    variable = sigma_wafer
    surface_current_density = wafer_net_surface_current_density
    block = wafer_surface
  []
  [sigma_focus_ring_time]
    type = ADTimeDerivative
    variable = sigma_focus_ring
    block = focus_ring_surface
  []
  [sigma_focus_ring_surface_current]
    type = PhysicsLowerDSurfaceCurrent
    variable = sigma_focus_ring
    surface_current_density = focus_ring_net_surface_current_density
    block = focus_ring_surface
  []
  [rf_heating_t6]
    type = MatBodyForce
    variable = log_e_energy
    material_property = q_rf_eV_mol_t6
    block = plasma
  []
[]

[FVKernels]
  [neutral_mass_time]
    type = WCNSFVMassTimeDerivative
    variable = pressure
    drho_dt = drho_neutral_dt
    block = plasma
  []
  [neutral_mass_advection]
    type = INSFVMassAdvection
    variable = pressure
    rho = rho_neutral
    block = plasma
  []

  [u_advection]
    type = INSFVMomentumAdvection
    variable = u
    rho = rho_neutral
    momentum_component = x
    block = plasma
  []
  [u_diffusion]
    type = INSFVMomentumDiffusion
    variable = u
    mu = mu_flow
    momentum_component = x
    block = plasma
  []
  [u_pressure]
    type = INSFVMomentumPressure
    variable = u
    pressure = pressure
    momentum_component = x
    block = plasma
  []
  [v_advection]
    type = INSFVMomentumAdvection
    variable = v
    rho = rho_neutral
    momentum_component = y
    block = plasma
  []
  [v_diffusion]
    type = INSFVMomentumDiffusion
    variable = v
    mu = mu_flow
    momentum_component = y
    block = plasma
  []
  [v_pressure]
    type = INSFVMomentumPressure
    variable = v
    pressure = pressure
    momentum_component = y
    block = plasma
  []
  [u_rz_viscous_source]
    type = INSFVMomentumViscousSourceRZ
    variable = u
    mu = mu_flow
    momentum_component = x
    block = plasma
  []

  [O2s_time]
    type = PhysicsFVConservativeMassFractionTimeDerivative
    variable = w_O2s
    rho = rho_neutral
    block = plasma
  []
  [O2s_advection]
    type = PhysicsFVMassFractionAdvection
    variable = w_O2s
    rho = rho_neutral
    block = plasma
  []
  [O2s_diffusion]
    type = PhysicsFVMixtureAveragedDiffusion
    variable = w_O2s
    rho = rho_neutral
    diffusivity = D_mix_O2s
    mean_molar_mass = Mn_neutral
    include_molar_mass_gradient = true
    block = plasma
  []

  [O_time]
    type = PhysicsFVConservativeMassFractionTimeDerivative
    variable = w_O
    rho = rho_neutral
    block = plasma
  []
  [O_advection]
    type = PhysicsFVMassFractionAdvection
    variable = w_O
    rho = rho_neutral
    block = plasma
  []
  [O_diffusion]
    type = PhysicsFVMixtureAveragedDiffusion
    variable = w_O
    rho = rho_neutral
    diffusivity = D_mix_O
    mean_molar_mass = Mn_neutral
    include_molar_mass_gradient = true
    block = plasma
  []

  [Os_time]
    type = PhysicsFVConservativeMassFractionTimeDerivative
    variable = w_Os
    rho = rho_neutral
    block = plasma
  []
  [Os_advection]
    type = PhysicsFVMassFractionAdvection
    variable = w_Os
    rho = rho_neutral
    block = plasma
  []
  [Os_diffusion]
    type = PhysicsFVMixtureAveragedDiffusion
    variable = w_Os
    rho = rho_neutral
    diffusivity = D_mix_Os
    mean_molar_mass = Mn_neutral
    include_molar_mass_gradient = true
    block = plasma
  []
  [ei415_neutral_mass_source]
    type = FVCoupledForce
    variable = pressure
    v = S_neutral_mass_EI415
    coef = 1.0
    block = plasma
  []
  [ei401_atomic_oxygen_source]
    type = PhysicsFVSpeciesReactionSource
    variable = w_O
    source = S_O_mass_EI401
    block = plasma
  []
  [ei401_neutral_mass_sink]
    type = FVCoupledForce
    variable = pressure
    v = S_neutral_mass_EI401
    coef = 1.0
    block = plasma
  []
  [legacy8_h05_ei417_atomic_o]
    type = PhysicsFVSpeciesReactionSource
    variable = w_O
    source = S_O_mass_EI417
    block = plasma
  []
  [legacy8_h05_ei417_fluid_mass]
    type = FVCoupledForce
    variable = pressure
    v = S_neutral_mass_EI417
    coef = 1.0
    block = plasma
  []
  [legacy8_407_o2s]
    type = PhysicsFVSpeciesReactionSource
    variable = w_O2s
    source = S_O2s_mass_EI407
    block = plasma
  []
  [ei2069_o2a_loss]
    type = PhysicsFVSpeciesReactionSource
    variable = w_O2s
    source = S_O2a_mass_EI2069
    block = plasma
  []
  [ei2069_o_birth]
    type = PhysicsFVSpeciesReactionSource
    variable = w_O
    source = S_O_mass_EI2069
    block = plasma
  []
  [h25_atomic_oxygen]
    type = PhysicsFVSpeciesReactionSource
    variable = w_O
    source = S_O_mass_H25
    block = plasma
  []
  [h25_neutral_pressure]
    type = FVCoupledForce
    variable = pressure
    v = S_neutral_mass_H25
    coef = 1.0
    block = plasma
  []
[]

[BCs]
  [grounded_potential]
    type = DirichletBC
    variable = potential
    value = 0.0
    boundary = 'inlet outlet plasma_electrode plasma_metal plasma_right cover_outer_right wafer_electrode focus_ring_ground vacuum_outer_ground cover_coil_ground vacuum_coil_ground'
  []
  [cover_surface_charge_poisson]
    type = PhysicsADSurfaceChargePoissonBC
    variable = potential
    boundary = plasma_cover
    surface_charge = sigma_s
  []
  [wafer_surface_charge_poisson]
    type = PhysicsADSurfaceChargePoissonBC
    variable = potential
    boundary = plasma_wafer
    surface_charge = sigma_wafer
  []
  [focus_ring_surface_charge_poisson]
    type = PhysicsADSurfaceChargePoissonBC
    variable = potential
    boundary = plasma_focus_ring
    surface_charge = sigma_focus_ring
  []
[]

[FVBCs]
  [neutral_inlet_mass]
    type = WCNSFVMassFluxBC
    variable = pressure
    boundary = inlet
    mdot_pp = neutral_inlet_mdot
    area_pp = neutral_inlet_area
    rho = rho_neutral
    vel_x = u
    vel_y = v
    direction = '-1 0 0'
  []
  [neutral_inlet_u]
    type = WCNSFVMomentumFluxBC
    variable = u
    boundary = inlet
    mdot_pp = neutral_inlet_mdot
    area_pp = neutral_inlet_area
    rho = rho_neutral
    vel_x = u
    vel_y = v
    momentum_component = x
    direction = '-1 0 0'
  []
  [neutral_inlet_v]
    type = WCNSFVMomentumFluxBC
    variable = v
    boundary = inlet
    mdot_pp = neutral_inlet_mdot
    area_pp = neutral_inlet_area
    rho = rho_neutral
    vel_x = u
    vel_y = v
    momentum_component = y
    direction = '-1 0 0'
  []

  [neutral_inlet_O2s]
    type = WCNSFVScalarFluxBC
    variable = w_O2s
    boundary = inlet
    passive_scalar = w_O2s
    scalar_flux_pp = neutral_inlet_mdot_O2s
    area_pp = neutral_inlet_area
    rho = rho_neutral
    vel_x = u
    vel_y = v
    direction = '-1 0 0'
  []
  [neutral_inlet_O]
    type = WCNSFVScalarFluxBC
    variable = w_O
    boundary = inlet
    passive_scalar = w_O
    scalar_flux_pp = neutral_inlet_mdot_O
    area_pp = neutral_inlet_area
    rho = rho_neutral
    vel_x = u
    vel_y = v
    direction = '-1 0 0'
  []
  [neutral_inlet_Os]
    type = WCNSFVScalarFluxBC
    variable = w_Os
    boundary = inlet
    passive_scalar = w_Os
    scalar_flux_pp = neutral_inlet_mdot_Os
    area_pp = neutral_inlet_area
    rho = rho_neutral
    vel_x = u
    vel_y = v
    direction = '-1 0 0'
  []

  [neutral_wall_u]
    type = INSFVNoSlipWallBC
    variable = u
    boundary = 'plasma_electrode plasma_metal plasma_right plasma_cover plasma_wafer plasma_focus_ring'
    function = 0
  []
  [neutral_wall_v]
    type = INSFVNoSlipWallBC
    variable = v
    boundary = 'plasma_electrode plasma_metal plasma_right plasma_cover plasma_wafer plasma_focus_ring'
    function = 0
  []
  [neutral_outlet_p]
    type = INSFVOutletPressureBC
    variable = pressure
    boundary = outlet
    function = ${Physics/Plasmas/pressure}
  []
[]

[Postprocessors]
  [ne_min]
    type = ADElementExtremeFunctorValue
    functor = n_e_physical
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ne_max]
    type = ADElementExtremeFunctorValue
    functor = n_e_physical
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ni_min]
    type = ADElementExtremeFunctorValue
    functor = n_i_physical
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ni_max]
    type = ADElementExtremeFunctorValue
    functor = n_i_physical
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [mean_energy_min]
    type = ADElementExtremeFunctorValue
    functor = e_energy_eV
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [mean_energy_max]
    type = ADElementExtremeFunctorValue
    functor = e_energy_eV
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [potential_min]
    type = ADElementExtremeFunctorValue
    functor = potential
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [potential_max]
    type = ADElementExtremeFunctorValue
    functor = potential
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [charge_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = charge_density_C_m3
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [nm_min]
    type = ADElementExtremeFunctorValue
    functor = n_m_physical
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [nm_max]
    type = ADElementExtremeFunctorValue
    functor = n_m_physical
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [charge_number_min]
    type = ADElementExtremeFunctorValue
    functor = charge_number_density
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [charge_number_max]
    type = ADElementExtremeFunctorValue
    functor = charge_number_density
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [nop_min]
    type = ADElementExtremeFunctorValue
    functor = n_op_physical
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [nop_max]
    type = ADElementExtremeFunctorValue
    functor = n_op_physical
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_inlet_area]
    type = AreaPostprocessor
    boundary = inlet
    execute_on = INITIAL
  []
  [neutral_inlet_mdot]
    type = Receiver
    default = 4.758967769568476e-06
  []
  [neutral_inlet_mdot_O2]
    type = Receiver
    default = 4.7588725892612807e-06
  []
  [neutral_inlet_mdot_O2s]
    type = Receiver
    default = 4.759015359722073e-11
  []
  [neutral_inlet_mdot_O]
    type = Receiver
    default = 2.3795076798610365e-11
  []
  [neutral_inlet_mdot_Os]
    type = Receiver
    default = 2.3795076798610365e-11
  []

  [neutral_outlet_mass]
    type = BoundaryVolumetricFlowRate
    boundary = outlet
    vel_x = u
    vel_y = v
    advected_quantity = rho_neutral
    rhie_chow_user_object = rc
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_outlet_mdot_O2]
    type = BoundaryVolumetricFlowRate
    boundary = outlet
    vel_x = u
    vel_y = v
    advected_quantity = rho_w_O2
    rhie_chow_user_object = rc
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_outlet_mdot_O2s]
    type = BoundaryVolumetricFlowRate
    boundary = outlet
    vel_x = u
    vel_y = v
    advected_quantity = rho_w_O2s
    rhie_chow_user_object = rc
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_outlet_mdot_O]
    type = BoundaryVolumetricFlowRate
    boundary = outlet
    vel_x = u
    vel_y = v
    advected_quantity = rho_w_O
    rhie_chow_user_object = rc
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_outlet_mdot_Os]
    type = BoundaryVolumetricFlowRate
    boundary = outlet
    vel_x = u
    vel_y = v
    advected_quantity = rho_w_Os
    rhie_chow_user_object = rc
    execute_on = 'INITIAL TIMESTEP_END'
  []

  [neutral_sum_w_min]
    type = ADElementExtremeFunctorValue
    functor = neutral_sum_w_functor
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_sum_w_max]
    type = ADElementExtremeFunctorValue
    functor = neutral_sum_w_functor
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []

  [w_O2_min]
    type = ADElementExtremeFunctorValue
    functor = w_O2_constraint
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [w_O2_max]
    type = ADElementExtremeFunctorValue
    functor = w_O2_constraint
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [w_O2s_min]
    type = ADElementExtremeFunctorValue
    functor = w_O2s
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [w_O2s_max]
    type = ADElementExtremeFunctorValue
    functor = w_O2s
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [w_O_min]
    type = ADElementExtremeFunctorValue
    functor = w_O
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [w_O_max]
    type = ADElementExtremeFunctorValue
    functor = w_O
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [w_Os_min]
    type = ADElementExtremeFunctorValue
    functor = w_Os
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [w_Os_max]
    type = ADElementExtremeFunctorValue
    functor = w_Os
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []

  [neutral_Mn_min]
    type = ADElementExtremeFunctorValue
    functor = Mn_neutral
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_Mn_max]
    type = ADElementExtremeFunctorValue
    functor = Mn_neutral
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_rho_min]
    type = ADElementExtremeFunctorValue
    functor = rho_neutral
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_rho_max]
    type = ADElementExtremeFunctorValue
    functor = rho_neutral
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_p_min]
    type = ADElementExtremeFunctorValue
    functor = pressure
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_p_max]
    type = ADElementExtremeFunctorValue
    functor = pressure
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_u_min]
    type = ADElementExtremeFunctorValue
    functor = u
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_u_max]
    type = ADElementExtremeFunctorValue
    functor = u
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_v_min]
    type = ADElementExtremeFunctorValue
    functor = v
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_v_max]
    type = ADElementExtremeFunctorValue
    functor = v
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []

  [cover_net_surface_current]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_cover
    functor = cover_net_surface_current_density
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [cover_electron_primary_flux]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_cover
    functor = e_wall_number_flux
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [cover_O2p_flux]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_cover
    functor = O2p_wall_number_flux
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [cover_Om_flux]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_cover
    functor = Om_wall_number_flux
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [cover_Op_flux]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_cover
    functor = Op_wall_number_flux
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [cover_surface_charge_total]
    type = ElementIntegralVariablePostprocessor
    variable = sigma_s
    block = cover_surface
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [cover_sigma_average]
    type = ElementAverageValue
    variable = sigma_s
    block = cover_surface
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [cover_sigma_min]
    type = ElementExtremeValue
    variable = sigma_s
    value_type = min
    block = cover_surface
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [cover_sigma_max]
    type = ElementExtremeValue
    variable = sigma_s
    value_type = max
    block = cover_surface
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [cover_interface_potential]
    type = SideAverageValue
    variable = potential
    boundary = plasma_cover
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [wafer_net_surface_current]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_wafer
    functor = wafer_net_surface_current_density
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [wafer_electron_primary_flux]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_wafer
    functor = e_wall_number_flux
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [wafer_O2p_flux]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_wafer
    functor = O2p_wall_number_flux
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [wafer_Om_flux]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_wafer
    functor = Om_wall_number_flux
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [wafer_Op_flux]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_wafer
    functor = Op_wall_number_flux
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [wafer_surface_charge_total]
    type = ElementIntegralVariablePostprocessor
    variable = sigma_wafer
    block = wafer_surface
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [wafer_sigma_average]
    type = ElementAverageValue
    variable = sigma_wafer
    block = wafer_surface
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [wafer_sigma_min]
    type = ElementExtremeValue
    variable = sigma_wafer
    value_type = min
    block = wafer_surface
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [wafer_sigma_max]
    type = ElementExtremeValue
    variable = sigma_wafer
    value_type = max
    block = wafer_surface
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [wafer_interface_potential]
    type = SideAverageValue
    variable = potential
    boundary = plasma_wafer
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [wafer_ground_potential]
    type = SideAverageValue
    variable = potential
    boundary = wafer_electrode
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [focus_ring_net_surface_current]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_focus_ring
    functor = focus_ring_net_surface_current_density
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [focus_ring_electron_primary_flux]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_focus_ring
    functor = e_wall_number_flux
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [focus_ring_O2p_flux]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_focus_ring
    functor = O2p_wall_number_flux
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [focus_ring_Om_flux]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_focus_ring
    functor = Om_wall_number_flux
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [focus_ring_Op_flux]
    type = ADSideIntegralFunctorPostprocessor
    boundary = plasma_focus_ring
    functor = Op_wall_number_flux
    functor_argument = face
    execute_on = 'INITIAL TIMESTEP_END'
    restrict_to_functors_domain = true
  []
  [focus_ring_surface_charge_total]
    type = ElementIntegralVariablePostprocessor
    variable = sigma_focus_ring
    block = focus_ring_surface
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [focus_ring_sigma_average]
    type = ElementAverageValue
    variable = sigma_focus_ring
    block = focus_ring_surface
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [focus_ring_sigma_min]
    type = ElementExtremeValue
    variable = sigma_focus_ring
    value_type = min
    block = focus_ring_surface
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [focus_ring_sigma_max]
    type = ElementExtremeValue
    variable = sigma_focus_ring
    value_type = max
    block = focus_ring_surface
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [focus_ring_interface_potential]
    type = SideAverageValue
    variable = potential
    boundary = plasma_focus_ring
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [focus_ring_ground_potential]
    type = SideAverageValue
    variable = potential
    boundary = focus_ring_ground
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [vacuum_outer_ground_potential]
    type = SideAverageValue
    variable = potential
    boundary = vacuum_outer_ground
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [cover_coil_ground_potential]
    type = SideAverageValue
    variable = potential
    boundary = cover_coil_ground
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [vacuum_coil_ground_potential]
    type = SideAverageValue
    variable = potential
    boundary = vacuum_coil_ground
    execute_on = 'INITIAL TIMESTEP_END'
  []

  [neutral_mass_total]
    type = ADElementIntegralFunctorPostprocessor
    functor = rho_neutral
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_mass_O2]
    type = ADElementIntegralFunctorPostprocessor
    functor = rho_w_O2
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_mass_O2s]
    type = ADElementIntegralFunctorPostprocessor
    functor = rho_w_O2s
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_mass_O]
    type = ADElementIntegralFunctorPostprocessor
    functor = rho_w_O
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [neutral_mass_Os]
    type = ADElementIntegralFunctorPostprocessor
    functor = rho_w_Os
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []

  [stageb4_O2p_wall_mass_rate]
    type = ADSideIntegralFunctorPostprocessor
    boundary = 'plasma_electrode plasma_metal plasma_right plasma_cover plasma_wafer plasma_focus_ring'
    functor = O2p_wall_mass_flux
    restrict_to_functors_domain = true
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [stageb4_Om_wall_mass_rate]
    type = ADSideIntegralFunctorPostprocessor
    boundary = 'plasma_electrode plasma_metal plasma_right plasma_cover plasma_wafer plasma_focus_ring'
    functor = Om_wall_mass_flux
    restrict_to_functors_domain = true
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [stageb4_Op_wall_mass_rate]
    type = ADSideIntegralFunctorPostprocessor
    boundary = 'plasma_electrode plasma_metal plasma_right plasma_cover plasma_wafer plasma_focus_ring'
    functor = Op_wall_mass_flux
    restrict_to_functors_domain = true
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [rf_drive_scale_t6]
    type = Receiver
    default = 4.7406324819558936
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [P_abs_maxwell_t6]
    type = Receiver
    default = 400
    execute_on = 'INITIAL TIMESTEP_BEGIN TIMESTEP_END'
  []
  [P_rf_raw_W_t6]
    type = ElementIntegralMaterialProperty
    mat_prop = q_rf_raw_t6
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [P_rf_scaled_W_t6]
    type = ElementIntegralMaterialProperty
    mat_prop = q_rf_scaled_t6
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [S_rf_eV_mol_s_t6]
    type = ElementIntegralMaterialProperty
    mat_prop = q_rf_eV_mol_t6
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [mean_energy_rf_state_min_t6]
    type = ElementExtremeValue
    variable = mean_energy_rf_state_t6
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [mean_energy_rf_state_max_t6]
    type = ElementExtremeValue
    variable = mean_energy_rf_state_t6
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [elastic_R_min]
    type = ADElementExtremeFunctorValue
    functor = R_EI02
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [elastic_R_max]
    type = ADElementExtremeFunctorValue
    functor = R_EI02
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [elastic_R_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = R_EI02
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [elastic_delta_e_min]
    type = ADElementExtremeFunctorValue
    functor = delta_epsilon_EI02_eV
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [elastic_delta_e_max]
    type = ADElementExtremeFunctorValue
    functor = delta_epsilon_EI02_eV
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [elastic_energy_source_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = elastic_energy_source_EI02
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei17_rate_min]
    type = ADElementExtremeFunctorValue
    functor = R_EI17
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei17_rate_max]
    type = ADElementExtremeFunctorValue
    functor = R_EI17
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei17_rate_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = R_EI17
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei17_delta_energy_min]
    type = ADElementExtremeFunctorValue
    functor = delta_epsilon_EI17_eV
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei17_delta_energy_max]
    type = ADElementExtremeFunctorValue
    functor = delta_epsilon_EI17_eV
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei17_energy_source_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_electron_energy_EI17
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei415_R_ion_O2_min]
    type = ADElementExtremeFunctorValue
    functor = R_EI415
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei415_R_ion_O2_max]
    type = ADElementExtremeFunctorValue
    functor = R_EI415
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei415_R_ion_O2_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = R_EI415
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei415_energy_source_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_electron_energy_molar_EI415
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei415_heavy_mass_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_heavy_mass_closure_EI415
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei415_charge_molar_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_charge_molar_closure_EI415
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei401_R_min]
    type = ADElementExtremeFunctorValue
    functor = R_EI401
    value_type = min
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei401_R_max]
    type = ADElementExtremeFunctorValue
    functor = R_EI401
    value_type = max
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei401_R_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = R_EI401
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei401_electron_source_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_electron_molar_EI401
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei401_om_source_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_Om_molar_EI401
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei401_heavy_mass_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_heavy_mass_closure_EI401
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei401_charge_molar_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_charge_molar_closure_EI401
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [legacy8_h05_ei417_rate_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = R_EI417
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [legacy8_h05_ei417_electron_source_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_e_molar_EI417
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [legacy8_h05_ei417_energy_sink_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_energy_EI417
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [legacy8_h05_ei417_heavy_mass_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_heavy_mass_closure_EI417
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [legacy8_h05_ei417_neutral_mass_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_neutral_mass_closure_EI417
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [legacy8_h05_ei417_charge_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_charge_closure_EI417
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [legacy8_407_rate_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = R_EI407
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [legacy8_407_mass_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_mass_closure_EI407
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei2069_progress_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = R_EI2069
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [ei2069_heavy_mass_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_heavy_mass_closure_EI2069
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [h25_progress_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = R_H25
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [h25_charge_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_charge_closure_H25
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [h25_heavy_mass_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_heavy_mass_closure_H25
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [h25_neutral_mass_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_neutral_mass_closure_H25
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [h25_oxygen_atoms_closure_integral]
    type = ADElementIntegralFunctorPostprocessor
    functor = S_oxygen_nuclei_closure_H25
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]

[Executioner]
  type = Transient
  scheme = implicit-euler
  solve_type = NEWTON
  end_time = 1e-4
  [TimeStepper]
    type = TimeSequenceStepper
    time_sequence = '0 1.0000000000000001e-09 2.0000000000000001e-09 3.0000000000000004e-09 4.0000000000000002e-09 5.0000000000000001e-09 6.0000000000000008e-09 7.0000000000000006e-09 8.0000000000000005e-09 9.0000000000000012e-09 1e-08 1.1000000000000001e-08 1.2000000000000002e-08 1.3000000000000001e-08 1.4000000000000001e-08 1.5000000000000002e-08 1.6000000000000001e-08 1.7e-08 1.8000000000000002e-08 1.9000000000000001e-08 2e-08 2.1000000000000003e-08 2.2000000000000002e-08 2.3000000000000001e-08 2.4000000000000003e-08 2.5000000000000002e-08 2.6000000000000001e-08 2.7e-08 2.8000000000000003e-08 2.9000000000000002e-08 3.0000000000000004e-08 3.1e-08 3.2000000000000002e-08 3.3000000000000004e-08 3.4e-08 3.5000000000000002e-08 3.6000000000000005e-08 3.7e-08 3.8000000000000003e-08 3.9000000000000005e-08 4.0000000000000001e-08 4.1000000000000003e-08 4.2000000000000006e-08 4.3000000000000001e-08 4.4000000000000004e-08 4.5000000000000006e-08 4.6000000000000002e-08 4.7000000000000004e-08 4.8000000000000006e-08 4.9000000000000002e-08 5.0000000000000004e-08 5.1e-08 5.2000000000000002e-08 5.3000000000000005e-08 5.4e-08 5.5000000000000003e-08 5.6000000000000005e-08 5.7000000000000001e-08 5.8000000000000003e-08 5.9000000000000006e-08 6.0000000000000008e-08 6.1000000000000004e-08 6.1999999999999999e-08 6.3000000000000008e-08 6.4000000000000004e-08 6.5e-08 6.6000000000000009e-08 6.7000000000000004e-08 6.8e-08 6.9000000000000009e-08 7.0000000000000005e-08 7.1e-08 7.2000000000000009e-08 7.3000000000000005e-08 7.4000000000000001e-08 7.500000000000001e-08 7.6000000000000006e-08 7.7000000000000001e-08 7.800000000000001e-08 7.9000000000000006e-08 8.0000000000000002e-08 8.1000000000000011e-08 8.2000000000000006e-08 8.3000000000000002e-08 8.4000000000000011e-08 8.5000000000000007e-08 8.6000000000000002e-08 8.7000000000000011e-08 8.8000000000000007e-08 8.9000000000000003e-08 9.0000000000000012e-08 9.1000000000000008e-08 9.2000000000000003e-08 9.3000000000000012e-08 9.4000000000000008e-08 9.5000000000000004e-08 9.6000000000000013e-08 9.7000000000000008e-08 9.8000000000000004e-08 9.9e-08 1.0000000000000001e-07 1.1000000000000001e-07 1.2000000000000002e-07 1.3e-07 1.4000000000000001e-07 1.5000000000000002e-07 1.6e-07 1.7000000000000001e-07 1.8000000000000002e-07 1.9000000000000001e-07 2.0000000000000002e-07 2.1e-07 2.2000000000000001e-07 2.3000000000000002e-07 2.4000000000000003e-07 2.5000000000000004e-07 2.6e-07 2.7000000000000001e-07 2.8000000000000002e-07 2.9000000000000003e-07 3.0000000000000004e-07 3.1e-07 3.2000000000000001e-07 3.3000000000000002e-07 3.4000000000000003e-07 3.5000000000000004e-07 3.6000000000000005e-07 3.7e-07 3.8000000000000001e-07 3.9000000000000002e-07 4.0000000000000003e-07 4.1000000000000004e-07 4.2e-07 4.3000000000000001e-07 4.4000000000000002e-07 4.5000000000000003e-07 4.6000000000000004e-07 4.7000000000000005e-07 4.8000000000000006e-07 4.9000000000000007e-07 5.0000000000000008e-07 5.0999999999999999e-07 5.2e-07 5.3000000000000001e-07 5.4000000000000002e-07 5.5000000000000003e-07 5.6000000000000004e-07 5.7000000000000005e-07 5.8000000000000006e-07 5.9000000000000007e-07 6.0000000000000008e-07 6.1000000000000009e-07 6.1999999999999999e-07 6.3e-07 6.4000000000000001e-07 6.5000000000000002e-07 6.6000000000000003e-07 6.7000000000000004e-07 6.8000000000000005e-07 6.9000000000000006e-07 7.0000000000000007e-07 7.1000000000000008e-07 7.2000000000000009e-07 7.3e-07 7.4000000000000001e-07 7.5000000000000002e-07 7.6000000000000003e-07 7.7000000000000004e-07 7.8000000000000005e-07 7.9000000000000006e-07 8.0000000000000007e-07 8.1000000000000008e-07 8.2000000000000009e-07 8.300000000000001e-07 8.4e-07 8.5000000000000001e-07 8.6000000000000002e-07 8.7000000000000003e-07 8.8000000000000004e-07 8.9000000000000006e-07 9.0000000000000007e-07 9.1000000000000008e-07 9.2000000000000009e-07 9.300000000000001e-07 9.4000000000000011e-07 9.5000000000000001e-07 9.6000000000000013e-07 9.7000000000000003e-07 9.8000000000000015e-07 9.9000000000000005e-07 1.0000000000000002e-06 1.0100000000000001e-06 1.02e-06 1.0300000000000001e-06 1.04e-06 1.0500000000000001e-06 1.06e-06 1.0700000000000001e-06 1.08e-06 1.0900000000000002e-06 1.1000000000000001e-06 1.1100000000000002e-06 1.1200000000000001e-06 1.13e-06 1.1400000000000001e-06 1.15e-06 1.1600000000000001e-06 1.17e-06 1.1800000000000001e-06 1.19e-06 1.2000000000000002e-06 1.2100000000000001e-06 1.2200000000000002e-06 1.2300000000000001e-06 1.24e-06 1.2500000000000001e-06 1.26e-06 1.2700000000000001e-06 1.28e-06 1.2900000000000001e-06 1.3e-06 1.3100000000000002e-06 1.3200000000000001e-06 1.3300000000000002e-06 1.3400000000000001e-06 1.35e-06 1.3600000000000001e-06 1.37e-06 1.3800000000000001e-06 1.39e-06 1.4000000000000001e-06 1.4100000000000001e-06 1.4200000000000002e-06 1.4300000000000001e-06 1.4400000000000002e-06 1.4500000000000001e-06 1.46e-06 1.4700000000000001e-06 1.48e-06 1.4900000000000001e-06 1.5e-06 1.5100000000000002e-06 1.5200000000000001e-06 1.5300000000000002e-06 1.5400000000000001e-06 1.5500000000000002e-06 1.5600000000000001e-06 1.57e-06 1.5800000000000001e-06 1.59e-06 1.6000000000000001e-06 1.61e-06 1.6200000000000002e-06 1.6300000000000001e-06 1.6400000000000002e-06 1.6500000000000001e-06 1.6600000000000002e-06 1.6700000000000001e-06 1.68e-06 1.6900000000000001e-06 1.7e-06 1.7100000000000001e-06 1.72e-06 1.7300000000000002e-06 1.7400000000000001e-06 1.7500000000000002e-06 1.7600000000000001e-06 1.7700000000000002e-06 1.7800000000000001e-06 1.79e-06 1.8000000000000001e-06 1.81e-06 1.8200000000000002e-06 1.8300000000000001e-06 1.8400000000000002e-06 1.8500000000000001e-06 1.8600000000000002e-06 1.8700000000000001e-06 1.8800000000000002e-06 1.8900000000000001e-06 1.9e-06 1.9099999999999999e-06 1.9200000000000003e-06 1.9300000000000002e-06 1.9400000000000001e-06 1.95e-06 1.9600000000000003e-06 1.9700000000000002e-06 1.9800000000000001e-06 1.99e-06 2.0000000000000003e-06 2.1000000000000002e-06 2.2000000000000001e-06 2.3e-06 2.4000000000000003e-06 2.5000000000000002e-06 2.6000000000000001e-06 2.7e-06 2.8000000000000003e-06 2.9000000000000002e-06 3.0000000000000001e-06 3.1000000000000004e-06 3.2000000000000003e-06 3.3000000000000002e-06 3.4000000000000001e-06 3.5000000000000004e-06 3.6000000000000003e-06 3.7000000000000002e-06 3.8e-06 3.8999999999999999e-06 4.0000000000000007e-06 4.1000000000000006e-06 4.2000000000000004e-06 4.3000000000000003e-06 4.4000000000000002e-06 4.5000000000000001e-06 4.6e-06 4.6999999999999999e-06 4.8000000000000006e-06 4.9000000000000005e-06 5.0000000000000004e-06 5.1000000000000003e-06 5.2000000000000002e-06 5.3000000000000001e-06 5.4e-06 5.5000000000000007e-06 5.6000000000000006e-06 5.7000000000000005e-06 5.8000000000000004e-06 5.9000000000000003e-06 6.0000000000000002e-06 6.1e-06 6.2000000000000008e-06 6.3000000000000007e-06 6.4000000000000006e-06 6.5000000000000004e-06 6.6000000000000003e-06 6.7000000000000002e-06 6.8000000000000001e-06 6.9000000000000009e-06 7.0000000000000007e-06 7.1000000000000006e-06 7.2000000000000005e-06 7.3000000000000004e-06 7.4000000000000003e-06 7.5000000000000002e-06 7.6000000000000001e-06 7.7000000000000008e-06 7.7999999999999999e-06 7.9000000000000006e-06 8.0000000000000013e-06 8.1000000000000004e-06 8.2000000000000011e-06 8.3000000000000002e-06 8.4000000000000009e-06 8.4999999999999999e-06 8.6000000000000007e-06 8.6999999999999997e-06 8.8000000000000004e-06 8.9000000000000012e-06 9.0000000000000002e-06 9.100000000000001e-06 9.2e-06 9.3000000000000007e-06 9.3999999999999998e-06 9.5000000000000005e-06 9.6000000000000013e-06 9.7000000000000003e-06 9.800000000000001e-06 9.9000000000000001e-06 1.0000000000000001e-05 1.1000000000000001e-05 1.2e-05 1.3000000000000001e-05 1.4000000000000001e-05 1.5e-05 1.6000000000000003e-05 1.7e-05 1.8e-05 1.9000000000000001e-05 2.0000000000000002e-05 2.1000000000000002e-05 2.2000000000000003e-05 2.3e-05 2.4000000000000001e-05 2.5000000000000001e-05 2.6000000000000002e-05 2.7000000000000002e-05 2.8000000000000003e-05 2.9e-05 3.0000000000000001e-05 3.1000000000000001e-05 3.2000000000000005e-05 3.3000000000000003e-05 3.4e-05 3.5000000000000004e-05 3.6000000000000001e-05 3.7000000000000005e-05 3.8000000000000002e-05 3.8999999999999999e-05 4.0000000000000003e-05 4.1e-05 4.2000000000000004e-05 4.3000000000000002e-05 4.4000000000000006e-05 4.5000000000000003e-05 4.6e-05 4.7000000000000004e-05 4.8000000000000001e-05 4.9000000000000005e-05 5.0000000000000002e-05 5.1000000000000006e-05 5.2000000000000004e-05 5.3000000000000001e-05 5.4000000000000005e-05 5.5000000000000002e-05 5.6000000000000006e-05 5.7000000000000003e-05 5.8e-05 5.9000000000000004e-05 6.0000000000000002e-05 6.1000000000000005e-05 6.2000000000000003e-05 6.3e-05 6.4000000000000011e-05 6.5000000000000008e-05 6.6000000000000005e-05 6.7000000000000002e-05 6.7999999999999999e-05 6.900000000000001e-05 7.0000000000000007e-05 7.1000000000000005e-05 7.2000000000000002e-05 7.2999999999999999e-05 7.400000000000001e-05 7.5000000000000007e-05 7.6000000000000004e-05 7.7000000000000001e-05 7.7999999999999999e-05 7.9000000000000009e-05 8.0000000000000007e-05 8.1000000000000004e-05 8.2000000000000001e-05 8.3000000000000012e-05 8.4000000000000009e-05 8.5000000000000006e-05 8.6000000000000003e-05 8.7000000000000001e-05 8.8000000000000011e-05 8.9000000000000008e-05 9.0000000000000006e-05 9.1000000000000003e-05 9.2e-05 9.3000000000000011e-05 9.4000000000000008e-05 9.5000000000000005e-05 9.6000000000000002e-05 9.7e-05 9.800000000000001e-05 9.9000000000000008e-05 0.0001'
  []
  line_search = bt
  nl_rel_tol = 1e-8
  nl_abs_tol = 1e-10
  nl_max_its = 100
  l_tol = 1e-10
  l_max_its = 20
  automatic_scaling = true
  off_diagonals_in_auto_scaling = true
  compute_scaling_once = false
  petsc_options = '-snes_converged_reason -ksp_converged_reason'
  petsc_options_iname = '-ksp_type -pc_type -pc_factor_shift_type'
  petsc_options_value = 'preonly lu NONZERO'
[]

[Preconditioning]
  [smp]
    type = SMP
    full = true
  []
[]

[Outputs]
  checkpoint = true
  csv = true
  exodus = true
  file_base = physics
  execute_on = 'INITIAL TIMESTEP_END'
[]
rf_scale_t6 = 1.0
source_enable_t6 = 1.0
faraday_t6 = 96485.33212331001
[AuxVariables]
  # Output-only fields: never consumed by the plasma equations.
  [E_real_full]
    family = LAGRANGE
    order = FIRST
    block = 'plasma cover wafer focus_ring vacuum coil1 coil2 coil3 electrode metal top right bottom port'
  []
  [E_imag_full]
    family = LAGRANGE
    order = FIRST
    block = 'plasma cover wafer focus_ring vacuum coil1 coil2 coil3 electrode metal top right bottom port'
  []
  [rf_absorbed_power_density]
    family = MONOMIAL
    order = CONSTANT
    block = plasma
  []
  [E_real_rf_t6]
    family = LAGRANGE
    order = FIRST
    block = plasma
  []
  [E_imag_rf_t6]
    family = LAGRANGE
    order = FIRST
    block = plasma
  []
  [log_ne_rf_state_t6]
    family = LAGRANGE
    order = FIRST
    block = plasma
  []
  [log_energy_rf_state_t6]
    family = LAGRANGE
    order = FIRST
    block = plasma
  []
  [electron_density_rf_state_t6]
    family = LAGRANGE
    order = FIRST
    block = plasma
  []
  [pressure_rf_state_t6]
    family = MONOMIAL
    order = CONSTANT
    block = plasma
  []
  [mean_energy_rf_state_t6]
    family = LAGRANGE
    order = FIRST
    block = plasma
  []
[]
[AuxKernels]
  [rf_absorbed_power_density_output]
    type = MaterialRealAux
    variable = rf_absorbed_power_density
    property = q_rf_raw_t6
    block = plasma
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [freeze_log_ne_t6]
    type = ParsedAux
    variable = log_ne_rf_state_t6
    coupled_variables = 'log_e'
    expression = 'log_e'
    execute_on = 'INITIAL TIMESTEP_BEGIN'
    block = plasma
  []
  [freeze_log_energy_t6]
    type = ParsedAux
    variable = log_energy_rf_state_t6
    coupled_variables = 'log_e_energy'
    expression = 'log_e_energy'
    execute_on = 'INITIAL TIMESTEP_BEGIN'
    block = plasma
  []
  [electron_density_rf_state_t6_aux]
    type = ParsedAux
    variable = electron_density_rf_state_t6
    coupled_variables = 'log_ne_rf_state_t6'
    expression = 'exp(log_ne_rf_state_t6)*6.02214076e23'
    execute_on = 'INITIAL TIMESTEP_BEGIN'
    block = plasma
  []
  [freeze_pressure_t6]
    type = ParsedAux
    variable = pressure_rf_state_t6
    coupled_variables = 'pressure'
    expression = 'pressure'
    execute_on = 'INITIAL TIMESTEP_BEGIN'
    block = plasma
  []
  [mean_energy_rf_state_t6_aux]
    type = ParsedAux
    variable = mean_energy_rf_state_t6
    coupled_variables = 'log_ne_rf_state_t6 log_energy_rf_state_t6'
    expression = 'exp(log_energy_rf_state_t6-log_ne_rf_state_t6)'
    execute_on = 'INITIAL TIMESTEP_BEGIN'
    block = plasma
  []
[]
[MultiApps]
  [maxwell_t6]
    type = FullSolveMultiApp
    input_files = 'maxwell.i'
    cli_args = 'Outputs/exodus=false;Outputs/csv=false'
    execute_on = TIMESTEP_BEGIN
    no_restore = true
  []
[]
[Transfers]
  [E_real_full_from_maxwell]
    type = MultiAppGeneralFieldShapeEvaluationTransfer
    from_multi_app = maxwell_t6
    source_variable = E_real
    variable = E_real_full
    from_blocks = 'plasma cover wafer focus_ring vacuum coil1 coil2 coil3 electrode metal top right bottom port'
    to_blocks = 'plasma cover wafer focus_ring vacuum coil1 coil2 coil3 electrode metal top right bottom port'
    error_on_miss = true
    execute_on = SAME_AS_MULTIAPP
  []
  [E_imag_full_from_maxwell]
    type = MultiAppGeneralFieldShapeEvaluationTransfer
    from_multi_app = maxwell_t6
    source_variable = E_imag
    variable = E_imag_full
    from_blocks = 'plasma cover wafer focus_ring vacuum coil1 coil2 coil3 electrode metal top right bottom port'
    to_blocks = 'plasma cover wafer focus_ring vacuum coil1 coil2 coil3 electrode metal top right bottom port'
    error_on_miss = true
    execute_on = SAME_AS_MULTIAPP
  []
  [drive_to_maxwell_t6]
    type = MultiAppPostprocessorTransfer
    to_multi_app = maxwell_t6
    from_postprocessor = rf_drive_scale_t6
    to_postprocessor = rf_drive_scale_child
    execute_on = SAME_AS_MULTIAPP
  []
  [ne_to_maxwell_t6]
    type = MultiAppGeneralFieldShapeEvaluationTransfer
    to_multi_app = maxwell_t6
    source_variable = electron_density_rf_state_t6
    variable = electron_density_state_t6
    from_blocks = plasma
    to_blocks = plasma
    execute_on = SAME_AS_MULTIAPP
  []
  [mean_en_to_maxwell_t6]
    type = MultiAppGeneralFieldShapeEvaluationTransfer
    to_multi_app = maxwell_t6
    source_variable = mean_energy_rf_state_t6
    variable = mean_energy_state_t6
    from_blocks = plasma
    to_blocks = plasma
    execute_on = SAME_AS_MULTIAPP
  []
  [pressure_to_maxwell_t6]
    type = MultiAppGeneralFieldShapeEvaluationTransfer
    to_multi_app = maxwell_t6
    source_variable = pressure_rf_state_t6
    variable = pressure_state_t6
    from_blocks = plasma
    to_blocks = plasma
    execute_on = SAME_AS_MULTIAPP
  []
  [E_real_from_maxwell_t6]
    type = MultiAppGeneralFieldShapeEvaluationTransfer
    from_multi_app = maxwell_t6
    source_variable = E_real
    variable = E_real_rf_t6
    from_blocks = plasma
    to_blocks = plasma
    execute_on = SAME_AS_MULTIAPP
  []
  [E_imag_from_maxwell_t6]
    type = MultiAppGeneralFieldShapeEvaluationTransfer
    from_multi_app = maxwell_t6
    source_variable = E_imag
    variable = E_imag_rf_t6
    from_blocks = plasma
    to_blocks = plasma
    execute_on = SAME_AS_MULTIAPP
  []
  [P_abs_from_maxwell_t6]
    type = MultiAppPostprocessorTransfer
    from_multi_app = maxwell_t6
    from_postprocessor = P_abs
    to_postprocessor = P_abs_maxwell_t6
    reduction_type = average
    execute_on = SAME_AS_MULTIAPP
  []
[]
[Controls]
  [rf_drive_pid_t6]
    type = PIDTransientControl
    postprocessor = P_rf_raw_W_t6
    target = 400
    parameter_pp = rf_drive_scale_t6
    K_integral = 0
    K_proportional = -0.00050000000000000001
    K_derivative = 0
    minimum_output_value = 0.10000000000000001
    maximum_output_value = 3
    execute_on = TIMESTEP_END
  []
[]
[Physics]
  [Plasmas]
    files = 'chemistry.json'
    pressure = 1.333223684
    temperature = 300
    state_model = ideal_gas
    # Shared FEM-potential gradient evaluation for every C2 FV ion wall.
    wall_gradient = adjacent_element
    [Transport]
      [Chemistry]
        block = plasma
      []
      [DriftDiffusion]
        [Continuity]
          block = plasma
          fem_species = e
          fvm_species = 'O2p Om Op'
          fem_potential = potential
          # Optional [V/m]: omit or set 0 for exact hard max(x,0).
          # Historical S6 sets 0.001 explicitly to retain its prior gate.
          migration_smoothing_width = 0.001
        []
        [Energy]
          block = plasma
          fem_species = e
          fem_potential = potential
          transport_coefficient = fluid
        []
      []
    []
  []
[]