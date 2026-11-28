#include "NVTransport.h"
#include "Chemistry.h"
#include "ActionWarehouse.h"
#include "FEProblemBase.h"

#include <cmath>
#include <iomanip>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>

namespace Plasma
{
InputParameters
NVTransport::validParams()
{
  auto params = PlasmaInterface::validParams();
  params.addClassDescription(
      "NavierStokes collision/mixture transport from [Plasmas]/files; "
      "named .i species masses can own the alias-only collision-data path.");
  params.addParam<std::vector<std::string>>(
      "species_molar_mass", "Named neutral masses (species:kg/mol); exact coverage of the "
                            "active mixture, no JSON or database mass owner.");
  params.addParam<FileName>("neutral_collision_file",
      "Alias-only neutral collision table; reuse the solved-mixture root catalogue.");
  params.addParam<bool>("solve_neutral_transport", false,
      "Own the qualified RZ x/y neutral conservation and WCNS boundary operators.");
  params.addParam<std::vector<BoundaryName>>("neutral_wall_boundaries", "No-slip walls.");
  params.addParam<std::vector<BoundaryName>>("neutral_outlet_boundaries", "Fixed-pressure outlets.");
  params.addParam<Point>("neutral_inlet_direction", "Explicit incoming direction.");
  params.addParam<FunctionName>("neutral_outlet_pressure", "Prescribed outlet pressure function [Pa].");
  params.addParam<MooseFunctorName>("neutral_viscosity", "Existing dynamic-viscosity functor.");
  params.addParam<UserObjectName>("neutral_rhie_chow", "Existing Rhie-Chow interpolator.");
  return params;
}

NVTransport::NVTransport(const InputParameters & parameters)
  : PlasmaInterface(parameters)
{
  if (!getParam<bool>("solve_neutral_transport"))
    return;
  if (!isParamValid("neutral_collision_file"))
    paramError("solve_neutral_transport", "Requires the solved neutral transport catalogue.");
  for (const auto * key : {"neutral_wall_boundaries", "neutral_outlet_boundaries",
                          "neutral_inlet_direction", "neutral_outlet_pressure",
                          "neutral_viscosity", "neutral_rhie_chow"})
    if (!isParamValid(key))
      paramError(key, "Explicit neutral flow configuration is required.");
  if (getParam<std::vector<BoundaryName>>("neutral_wall_boundaries").empty() ||
      getParam<std::vector<BoundaryName>>("neutral_outlet_boundaries").empty())
    paramError("neutral_wall_boundaries", "Wall and outlet sidesets must be nonempty.");
  const auto & direction = getParam<Point>("neutral_inlet_direction");
  if (!std::isfinite(direction.norm()) || std::abs(direction.norm() - 1.0) > 1e-12 ||
      direction(2) != 0.0)
    paramError("neutral_inlet_direction", "Expected a finite unit direction in the RZ x/y plane.");
}

void
NVTransport::addFunctorMaterials()
{
  // The solved-pressure neutral catalogue already owns masses and live
  // fraction names. Do not introduce a second JSON species/mass owner.
  if (isParamValid("neutral_collision_file"))
  {
    const auto roots = _awh.getActions<PlasmasAction>();
    if (roots.size() != 1 || !roots.front()->isParamValid("neutral_species") ||
        !rootGasStateEnabled() || !getProblem().hasVariable("pressure"))
      paramError("neutral_collision_file", "Requires the solved neutral root catalogue.");
    if (isParamValid("species_molar_mass") || chemistryData().nvTransport())
      paramError("neutral_collision_file", "Duplicate neutral transport catalogue.");
    const auto & root = *roots.front();
    const auto & ids = root.getParam<std::vector<std::string>>("neutral_species");
    const auto & masses = root.getParam<std::vector<Real>>("neutral_molar_masses");
    const auto & names = root.getParam<std::vector<std::string>>("neutral_fraction_names");
    const auto & blocks = root.getParam<std::vector<SubdomainName>>("neutral_blocks");
    if (ids.size() < 2 || masses.size() != ids.size() || names.size() != ids.size() ||
        std::set<SubdomainName>(_blocks.begin(), _blocks.end()) !=
        std::set<SubdomainName>(blocks.begin(), blocks.end()))
      paramError("neutral_collision_file", "Neutral transport must match root catalogue and blocks.");
    auto p = getFactory().getValidParams("NVTransportMaterial");
    p.set<FileName>("transport_data_file") = getParam<FileName>("neutral_collision_file");
    p.set<MooseFunctorName>("temperature") = "temperature";
    p.set<MooseFunctorName>("pressure") = "pressure";
    p.set<std::vector<std::string>>("species") = ids;
    p.set<std::vector<Real>>("molar_masses") = masses;
    p.set<std::vector<MooseFunctorName>>("mass_fractions") =
        std::vector<MooseFunctorName>(names.begin(), names.end());
    assignBlocks(p, _blocks);
    getProblem().addFunctorMaterial("NVTransportMaterial", name() + "_mixture_transport_coefficients", p);
    for (std::size_t k = 0; k < ids.size(); ++k)
    {
      auto concentration = getFactory().getValidParams("ADParsedFunctorMaterial");
      concentration.set<std::string>("property_name") = "c_" + ids[k] + "_molar";
      concentration.set<std::vector<std::string>>("functor_names") = {"rho_neutral", names[k]};
      concentration.set<std::vector<std::string>>("functor_symbols") = {"rho", "Y"};
      std::ostringstream expression;
      expression << std::setprecision(17) << "rho*Y/" << masses[k];
      concentration.set<std::string>("expression") = expression.str();
      assignBlocks(concentration, _blocks);
      getProblem().addFunctorMaterial("ADParsedFunctorMaterial",
          name() + "_" + ids[k] + "_molar_concentration", concentration);
    }
    return;
  }

  const auto * config = chemistryData().nvTransport();
  if (!config)
    mooseError("Activated [Transport]/[NavierStokes] requires "
               "transport_coefficients.navier_stokes in [Plasmas]/files");
  const std::string type = "NVTransportMaterial";
  auto params = getFactory().getValidParams(type);
  params.set<FileName>("transport_data_file") = config->transport_data_file;
  params.set<MooseFunctorName>("temperature") = rootGasStateEnabled() ? "temperature" : config->temperature;
  params.set<MooseFunctorName>("pressure") = rootGasStateEnabled() ? "pressure" : config->pressure;
  params.set<std::vector<std::string>>("species") = config->species;
  std::vector<MooseFunctorName> fractions;
  const bool input_mass_owner = isParamValid("species_molar_mass");
  if (input_mass_owner)
  {
    // This first .i ownership cut uses the existing solved-pressure EOS.
    // Fixed-pressure root JSON composition remains a separate legacy lane.
    if (!rootGasStateEnabled() || !getProblem().hasVariable("pressure"))
      paramError("species_molar_mass", "Named neutral masses require the solved-pressure mixture.");
    const std::set<std::string> selected(config->species.begin(), config->species.end());
    if (selected.size() != config->species.size())
      paramError("species_molar_mass", "Repeated active neutral species.");
    std::map<std::string, Real> masses;
    for (const auto & entry : getParam<std::vector<std::string>>("species_molar_mass"))
    {
      const auto colon = entry.find(':');
      if (colon == std::string::npos || colon == 0 || colon + 1 == entry.size() ||
          entry.find(':', colon + 1) != std::string::npos)
        paramError("species_molar_mass", "Expected species:positive_mass, found ", entry);
      const auto id = entry.substr(0, colon);
      const auto value = entry.substr(colon + 1);
      if (!selected.count(id) || masses.count(id))
        paramError("species_molar_mass", "Unknown or repeated neutral mass: ", id);
      std::size_t consumed = 0;
      Real mass = 0.0;
      try
      {
        mass = std::stod(value, &consumed);
      }
      catch (const std::exception &)
      {
        paramError("species_molar_mass", "Invalid neutral molar mass: ", entry);
      }
      if (consumed != value.size() || !std::isfinite(mass) || mass <= 0.0)
        paramError("species_molar_mass", "Neutral molar mass must be finite and positive: ", id);
      const auto & record = chemistryData().species(id);
      if (record.charge_number != 0 || record.molar_mass > 0.0 ||
          record.molar_mass_kg_mol > 0.0 || record.ion_wall)
        paramError("species_molar_mass", "Neutral .i mass conflicts with charge or JSON mass owner: ", id);
      masses.emplace(id, mass);
    }
    if (masses.size() != selected.size())
      paramError("species_molar_mass", "Named neutral masses must cover every active species.");
    for (const auto & reaction : chemistryData().reactions())
      if (reaction.rate.model == "lookup" && !selected.count(reaction.rate.lookup_target))
        paramError("species_molar_mass", "EI lookup target is not an active neutral: ",
                   reaction.rate.lookup_target);

    std::vector<Real> ordered_masses;
    for (std::size_t i = 0; i < config->species.size(); ++i)
    {
      const auto & id = config->species[i];
      const Real mass = masses.at(id);
      ordered_masses.push_back(mass);
      // During the staged migration the existing EOS owns rho_neutral and
      // the existing validated mixture bindings own live mass fractions.
      // Each species has exactly one concentration, shared by every EI rate.
      auto concentration = getFactory().getValidParams("ADParsedFunctorMaterial");
      concentration.set<std::string>("property_name") = "c_" + id + "_molar";
      concentration.set<std::vector<std::string>>("functor_names") =
          {"rho_neutral", config->mass_fractions[i]};
      concentration.set<std::vector<std::string>>("functor_symbols") = {"rho", "Y"};
      std::ostringstream expression;
      expression << std::setprecision(17) << "rho*Y/" << mass;
      concentration.set<std::string>("expression") = expression.str();
      assignBlocks(concentration, _blocks);
      getProblem().addFunctorMaterial("ADParsedFunctorMaterial",
                                      name() + "_" + id + "_molar_concentration",
                                      concentration);
    }
    params.set<std::vector<Real>>("molar_masses") = ordered_masses;
    fractions.assign(config->mass_fractions.begin(), config->mass_fractions.end());
  }
  else if (rootGasStateEnabled())
    for (const auto & id : config->species)
      fractions.emplace_back("Y_" + id); // live JSON species-state aliases
  else
    fractions.assign(config->mass_fractions.begin(), config->mass_fractions.end());
  params.set<std::vector<MooseFunctorName>>("mass_fractions") = fractions;
  if (!config->electron_temperature.empty())
  {
    params.set<MooseFunctorName>("electron_temperature") = config->electron_temperature;
    params.set<MooseFunctorName>("electron_number_density") = config->electron_number_density;
  }
  assignBlocks(params, _blocks);
  getProblem().addFunctorMaterial(type, name() + "_mixture_transport_coefficients", params);
}

void
NVTransport::addFVKernels()
{
  if (!getParam<bool>("solve_neutral_transport"))
    return;
  const auto roots = _awh.getActions<PlasmasAction>();
  if (roots.size() != 1 || !roots.front()->isParamValid("neutral_species"))
    paramError("solve_neutral_transport", "Requires one solved neutral root.");
  const auto & root = *roots.front();
  const auto & ids = root.getParam<std::vector<std::string>>("neutral_species");
  const auto & names = root.getParam<std::vector<std::string>>("neutral_fraction_names");
  const auto & dependent = root.getParam<std::string>("neutral_dependent_species");
  if (ids.size() != names.size())
    paramError("solve_neutral_transport", "Root species and fraction names must match.");
  for (const auto * v : {"pressure", "u", "v"})
    if (!solverVariableExists(v) || !isVariableFV(v))
      paramError("solve_neutral_transport", "Requires existing FV state ", v);
  const auto & rc = getParam<UserObjectName>("neutral_rhie_chow");
  const auto & mu = getParam<MooseFunctorName>("neutral_viscosity");
  const auto base = [this](const std::string & type, const std::string & variable)
  {
    auto p = getFactory().getValidParams(type);
    p.set<NonlinearVariableName>("variable") = variable;
    assignBlocks(p, _blocks);
    return p;
  };
  const auto advection = [&rc](InputParameters & p)
  {
    p.set<UserObjectName>("rhie_chow_user_object") = rc;
    p.set<MooseEnum>("advected_interp_method") = "upwind";
    p.set<MooseEnum>("velocity_interp_method") = "rc";
    p.set<MooseFunctorName>("rho") = "rho_neutral";
  };
  {
    const std::string type = "WCNSFVMassTimeDerivative";
    auto p = base(type, "pressure");
    p.set<MooseFunctorName>("drho_dt") = "drho_neutral_dt";
    getProblem().addFVKernel(type, "neutral_mass_time", p);
  }
  {
    const std::string type = "INSFVMassAdvection";
    auto p = base(type, "pressure");
    advection(p);
    getProblem().addFVKernel(type, "neutral_mass_advection", p);
  }
  for (const std::string variable : {"u", "v"})
  {
    const auto component = variable == "u" ? "x" : "y";
    {
      const std::string type = "INSFVMomentumAdvection";
      auto p = base(type, variable);
      advection(p);
      p.set<MooseEnum>("momentum_component") = component;
      getProblem().addFVKernel(type, variable + "_advection", p);
    }
    {
      const std::string type = "INSFVMomentumDiffusion";
      auto p = base(type, variable);
      p.set<UserObjectName>("rhie_chow_user_object") = rc;
      p.set<MooseFunctorName>("mu") = mu;
      p.set<MooseEnum>("momentum_component") = component;
      getProblem().addFVKernel(type, variable + "_diffusion", p);
    }
    {
      const std::string type = "INSFVMomentumPressure";
      auto p = base(type, variable);
      p.set<UserObjectName>("rhie_chow_user_object") = rc;
      p.set<MooseFunctorName>("pressure") = "pressure";
      p.set<MooseEnum>("momentum_component") = component;
      getProblem().addFVKernel(type, variable + "_pressure", p);
    }
  }
  {
    // Historical S6 RZ geometry has radial x and axial y. The native
    // RZ kernel rejects inconsistent coordinates. No momentum time term.
    const std::string type = "INSFVMomentumViscousSourceRZ";
    auto p = base(type, "u");
    p.set<UserObjectName>("rhie_chow_user_object") = rc;
    p.set<MooseFunctorName>("mu") = mu;
    p.set<MooseEnum>("momentum_component") = "x";
    getProblem().addFVKernel(type, "u_rz_viscous_source", p);
  }
  for (std::size_t k = 0; k < ids.size(); ++k)
  {
    if (ids[k] == dependent)
      continue;
    if (!solverVariableExists(names[k]) || !isVariableFV(names[k]))
      paramError("solve_neutral_transport", "Requires existing FV fraction ", names[k]);
    {
      const std::string type = "PhysicsFVConservativeMassFractionTimeDerivative";
      auto p = base(type, names[k]);
      p.set<MooseFunctorName>("rho") = "rho_neutral";
      getProblem().addFVKernel(type, ids[k] + "_time", p);
    }
    {
      const std::string type = "PhysicsFVMassFractionAdvection";
      auto p = base(type, names[k]);
      advection(p);
      getProblem().addFVKernel(type, ids[k] + "_advection", p);
    }
    {
      const std::string type = "PhysicsFVMixtureAveragedDiffusion";
      auto p = base(type, names[k]);
      p.set<MooseFunctorName>("rho") = "rho_neutral";
      p.set<MooseFunctorName>("diffusivity") = "D_mix_" + ids[k];
      p.set<MooseFunctorName>("mean_molar_mass") = "Mn_neutral";
      p.set<bool>("include_molar_mass_gradient") = true;
      getProblem().addFVKernel(type, ids[k] + "_diffusion", p);
    }
  }
}

void
NVTransport::addFVBCs()
{
  if (!getParam<bool>("solve_neutral_transport"))
    return;
  const auto roots = _awh.getActions<PlasmasAction>();
  if (roots.size() != 1 || !roots.front()->isParamValid("neutral_species"))
    paramError("solve_neutral_transport", "Requires one solved neutral root.");
  const auto & root = *roots.front();
  const auto & ids = root.getParam<std::vector<std::string>>("neutral_species");
  const auto & names = root.getParam<std::vector<std::string>>("neutral_fraction_names");
  const auto & dependent = root.getParam<std::string>("neutral_dependent_species");
  const auto & inlet = root.getParam<std::vector<BoundaryName>>("inlet_boundaries");
  const auto & walls = getParam<std::vector<BoundaryName>>("neutral_wall_boundaries");
  const auto & outlet = getParam<std::vector<BoundaryName>>("neutral_outlet_boundaries");
  if (ids.size() != names.size() || inlet.size() != 1)
    paramError("solve_neutral_transport", "Requires matching species and one qualified feed sideset.");
  std::set<BoundaryName> seen;
  for (const auto * group : {&inlet, &walls, &outlet})
    for (const auto & side : *group)
      if (!seen.insert(side).second)
        paramError("neutral_wall_boundaries", "Neutral inlet, walls and outlet must not overlap: ", side);
  const auto & direction = getParam<Point>("neutral_inlet_direction");
  const auto base = [this](const std::string & type, const std::string & variable,
                         const std::vector<BoundaryName> & sides)
  {
    auto p = getFactory().getValidParams(type);
    p.set<NonlinearVariableName>("variable") = variable;
    p.set<std::vector<BoundaryName>>("boundary") = sides;
    return p;
  };
  const auto flux = [&direction](InputParameters & p)
  {
    p.set<PostprocessorName>("area_pp") = "neutral_inlet_area";
    p.set<MooseFunctorName>("rho") = "rho_neutral";
    p.set<MooseFunctorName>("vel_x") = "u";
    p.set<MooseFunctorName>("vel_y") = "v";
    p.set<Point>("direction") = direction;
  };
  {
    const std::string type = "WCNSFVMassFluxBC";
    auto p = base(type, "pressure", inlet);
    flux(p);
    p.set<PostprocessorName>("mdot_pp") = "neutral_inlet_mdot";
    getProblem().addFVBC(type, "neutral_inlet_mass", p);
  }
  for (const std::string variable : {"u", "v"})
  {
    const std::string type = "WCNSFVMomentumFluxBC";
    auto p = base(type, variable, inlet);
    flux(p);
    p.set<PostprocessorName>("mdot_pp") = "neutral_inlet_mdot";
    p.set<UserObjectName>("rhie_chow_user_object") = getParam<UserObjectName>("neutral_rhie_chow");
    p.set<MooseEnum>("momentum_component") = variable == "u" ? "x" : "y";
    getProblem().addFVBC(type, "neutral_inlet_" + variable, p);
  }
  for (std::size_t k = 0; k < ids.size(); ++k)
  {
    if (ids[k] == dependent)
      continue;
    const std::string type = "WCNSFVScalarFluxBC";
    auto p = base(type, names[k], inlet);
    flux(p);
    p.set<MooseFunctorName>("passive_scalar") = names[k];
    p.set<PostprocessorName>("scalar_flux_pp") = "neutral_inlet_mdot_" + ids[k];
    getProblem().addFVBC(type, "neutral_inlet_" + ids[k], p);
  }
  for (const std::string variable : {"u", "v"})
  {
    const std::string type = "INSFVNoSlipWallBC";
    auto p = base(type, variable, walls);
    p.set<FunctionName>("function") = "0";
    getProblem().addFVBC(type, "neutral_wall_" + variable, p);
  }
  {
    const std::string type = "INSFVOutletPressureBC";
    auto p = base(type, "pressure", outlet);
    p.set<FunctionName>("function") = getParam<FunctionName>("neutral_outlet_pressure");
    getProblem().addFVBC(type, "neutral_outlet_p", p);
  }
}
} // namespace Plasma

using Plasma::NVTransport;
registerPhysicsBaseTasks("PhysicsApp", NVTransport);
registerMooseAction("PhysicsApp", NVTransport, "add_functor_material");
registerMooseAction("PhysicsApp", NVTransport, "add_fv_kernel");
registerMooseAction("PhysicsApp", NVTransport, "add_fv_bc");
