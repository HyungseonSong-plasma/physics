#include "MaxwellPhysics.h"

#include <algorithm>
#include <cmath>
#include <set>
#include <sstream>
#include <iomanip>

namespace Plasma
{

InputParameters
MaxwellPhysics::validParams()
{
  InputParameters params = PlasmaInterface::validParams();
  params.addClassDescription(
      "Generates RF field operators, grounded boundaries and optional driven coil sources.");
  params.addParam<VariableName>(
      "field_real", "E_real", "Legacy override for the real electromagnetic field.");
  params.addParam<VariableName>(
      "field_imag", "E_imag", "Legacy override for the imaginary electromagnetic field.");
  params.addParam<Real>("coil_current_A", "Reference peak coil current in amperes.");
  params.addParam<Real>("coil_cross_section_m2", "Conducting coil cross section in square metres.");
  params.addParam<std::vector<SubdomainName>>("vacuum_blocks", "Nonconducting RF regions with relative permittivity one.");
  params.addParam<std::vector<SubdomainName>>("plasma_blocks", "RF plasma regions using live complex conductivity.");
  params.addParam<std::vector<SubdomainName>>("dielectric_blocks", "RF dielectric regions.");
  params.addParam<std::vector<Real>>("relative_permittivities", "Relative permittivity for each dielectric block.");
  params.addParam<Real>(
      "frequency_Hz", "Positive electromagnetic driving frequency in hertz.");
  // Compatibility with existing fixtures; the canonical input uses frequency_Hz.
  params.addParam<Real>(
      "frequency_hz", "Legacy spelling of frequency_Hz; do not specify both.");

  params.addParam<MaterialPropertyName>(
      "reaction_material", "Existing RF reaction coefficient neg_a.");
  params.addParam<MaterialPropertyName>(
      "coupling_material", "Existing RF cross-coupling coefficient b.");
  params.addParam<Real>(
      "imaginary_source", "Prescribed RF imaginary source in solver equation units.");
  params.addParam<std::vector<SubdomainName>>(
      "coil_blocks", "One imaginary BodyForce per driven coil block.");
  params.addParam<PostprocessorName>(
      "coil_drive_scale", "Live RF drive postprocessor shared by all driven coils.");
  params.addParam<std::vector<BoundaryName>>(
      "ground_boundaries", {}, "Zero-field boundaries for both RF components.");
  return params;
}

MaxwellPhysics::MaxwellPhysics(const InputParameters & parameters)
  : PlasmaInterface(parameters)
{
  const bool canonical_frequency = isParamValid("frequency_Hz");
  const bool legacy_frequency = isParamValid("frequency_hz");
  if (canonical_frequency == legacy_frequency)
    paramError("frequency_Hz", "Specify exactly one of frequency_Hz and legacy frequency_hz.");
  const auto key = canonical_frequency ? "frequency_Hz" : "frequency_hz";
  const auto frequency = getParam<Real>(key);
  if (!std::isfinite(frequency) || frequency <= 0)
    paramError(key, "The frequency must be finite and greater than zero.");
  if (getParam<VariableName>("field_real").empty() ||
      getParam<VariableName>("field_imag").empty() ||
      getParam<VariableName>("field_real") == getParam<VariableName>("field_imag"))
    paramError("field_imag", "Real and imaginary fields must use different solver variables.");
  if (physicalCoils())
  {
    for (const auto * p : {"field_real", "field_imag", "reaction_material", "coupling_material",
                           "imaginary_source", "coil_drive_scale", "frequency_hz", "block"})
      if (isParamSetByUser(p))
        paramError(p, "Physical Maxwell mode owns internal RF fields, coefficients and drive bindings.");
    for (const auto * p : {"coil_current_A", "coil_cross_section_m2", "coil_blocks",
                           "vacuum_blocks", "plasma_blocks", "dielectric_blocks", "relative_permittivities"})
      if (!isParamValid(p))
        paramError(p, "Physical Maxwell mode requires complete coil and region inputs.");
    const Real current = getParam<Real>("coil_current_A");
    const Real area = getParam<Real>("coil_cross_section_m2");
    if (!std::isfinite(current) || current <= 0 || !std::isfinite(area) || area <= 0)
      paramError("coil_cross_section_m2", "Coil current and cross section must be finite and positive.");
    std::set<SubdomainName> regions;
    for (const auto * p : {"vacuum_blocks", "plasma_blocks", "dielectric_blocks"})
      for (const auto & region : getParam<std::vector<SubdomainName>>(p))
        if (!regions.insert(region).second)
          paramError(p, "RF region ownership must be disjoint and unique.");
    const auto & vacuum = getParam<std::vector<SubdomainName>>("vacuum_blocks");
    const auto & coils = getParam<std::vector<SubdomainName>>("coil_blocks");
    if (coils.empty() || std::set<SubdomainName>(coils.begin(), coils.end()).size() != coils.size())
      paramError("coil_blocks", "Driven coil blocks must be nonempty and unique.");
    for (const auto & coil : coils)
      if (std::find(vacuum.begin(), vacuum.end(), coil) == vacuum.end())
        paramError("coil_blocks", "Driven coil must belong to the vacuum-like RF region.");
    const auto & eps = getParam<std::vector<Real>>("relative_permittivities");
    if (eps.size() != getParam<std::vector<SubdomainName>>("dielectric_blocks").size() ||
        getParam<std::vector<SubdomainName>>("plasma_blocks").empty() || vacuum.empty())
      paramError("relative_permittivities", "RF material region coverage is incomplete.");
    for (const auto value : eps)
      if (!std::isfinite(value) || value <= 0)
        paramError("relative_permittivities", "Relative permittivity must be finite and positive.");
    for (const auto * p : {"dont_create_solver_variables", "dont_create_functions", "dont_create_materials",
                           "dont_create_kernels", "dont_create_bcs"})
      if (getParam<bool>(p))
        paramError(p, "Physical Maxwell mode requires complete operator ownership.");
    saveSolverVariableName(getParam<VariableName>("field_real"));
    saveSolverVariableName(getParam<VariableName>("field_imag"));
    addRequiredPhysicsTask("add_variables_physics");
    addRequiredPhysicsTask("add_function");
    addRequiredPhysicsTask("add_materials_physics");
    return;
  }
  if (!isParamSetByUser("field_real") || !isParamSetByUser("field_imag"))
    paramError("field_real", "Legacy Maxwell mode requires explicit field names.");
  const bool reaction = isParamValid("reaction_material");
  const bool coupling = isParamValid("coupling_material");
  if (reaction != coupling)
    paramError("reaction_material", "Supply both Maxwell material coefficients together.");
  if ((!getParam<std::vector<BoundaryName>>("ground_boundaries").empty() ||
       isParamValid("imaginary_source")) && !reaction)
    paramError("reaction_material", "Provide RF coefficients before creating sources or boundaries.");
  const bool coils = isParamValid("coil_blocks");
  const bool scale = isParamValid("coil_drive_scale");
  if (coils != scale || (coils && !isParamValid("imaginary_source")))
    paramError("coil_blocks", "Driven coils require coil_blocks, coil_drive_scale and imaginary_source together.");
  if (isParamValid("imaginary_source") && !std::isfinite(getParam<Real>("imaginary_source")))
    paramError("imaginary_source", "RF source must be finite.");
  if (coils)
  {
    const auto & blocks = getParam<std::vector<SubdomainName>>("coil_blocks");
    if (blocks.empty() || std::set<SubdomainName>(blocks.begin(), blocks.end()).size() != blocks.size())
      paramError("coil_blocks", "Driven coil blocks must be nonempty and unique.");
    if (getParam<PostprocessorName>("coil_drive_scale").empty())
      paramError("coil_drive_scale", "A live RF drive postprocessor is required.");
    if (!_blocks.empty())
      for (const auto & block : blocks)
        if (std::find(_blocks.begin(), _blocks.end(), block) == _blocks.end())
          paramError("coil_blocks", "Driven coil block is outside Maxwell operator blocks: ", block);
  }
}

namespace
{
constexpr Real rf_mu0 = 1.2566370614359173e-6;
constexpr Real rf_eps0 = 8.8541878128e-12;
std::string rfLiteral(Real value)
{
  std::ostringstream stream;
  stream << std::setprecision(17) << value;
  return stream.str();
}
}

bool
MaxwellPhysics::physicalCoils() const
{
  return isParamValid("coil_current_A") || isParamValid("coil_cross_section_m2");
}

bool
MaxwellPhysics::ownsOperators() const
{
  return physicalCoils() || isParamValid("reaction_material");
}

Real
MaxwellPhysics::angularFrequency() const
{
  return 2.0 * 3.141592653589793 * getParam<Real>("frequency_Hz");
}

void
MaxwellPhysics::addSolverVariables()
{
  if (!physicalCoils())
    return;
  for (const auto & field : {getParam<VariableName>("field_real"), getParam<VariableName>("field_imag")})
  {
    if (variableExists(field, /*error_if_aux=*/true))
      paramError("coil_current_A", "Physical Maxwell mode owns the RF solver variables: ", field);
    auto params = getFactory().getValidParams("MooseVariable");
    params.set<MooseEnum>("family") = "LAGRANGE";
    params.set<MooseEnum>("order") = "FIRST";
    params.set<SolverSystemName>("solver_sys") = getSolverSystem(field);
    assignBlocks(params, _blocks);
    getProblem().addVariable("MooseVariable", field, params);
  }
}

void
MaxwellPhysics::addFunctions()
{
  if (!physicalCoils())
    return;
  auto zero = getFactory().getValidParams("ConstantFunction");
  zero.set<Real>("value") = 0;
  getProblem().addFunction("ConstantFunction", "zero_fn", zero);
  const auto omega = angularFrequency();
  const auto k2 = rfLiteral(omega * omega * rf_mu0 * rf_eps0);
  const auto geometry = [&](const std::string & id, Real eps, bool vacuum)
  {
    auto params = getFactory().getValidParams("ParsedFunction");
    params.set<std::string>("expression") = vacuum ? "-(1/(x*x) - k2)" : "-(1/(x*x) - k2*epsr)";
    params.set<std::vector<std::string>>("symbol_names") = vacuum ?
        std::vector<std::string>{"k2"} : std::vector<std::string>{"k2", "epsr"};
    params.set<std::vector<std::string>>("symbol_values") = vacuum ?
        std::vector<std::string>{k2} : std::vector<std::string>{k2, rfLiteral(eps)};
    getProblem().addFunction("ParsedFunction", id, params);
  };
  geometry("neg_a_vac_fn", 1.0, true);
  geometry("neg_a_plasma_geom_t6", 1.0, false);
  const auto & blocks = getParam<std::vector<SubdomainName>>("dielectric_blocks");
  const auto & eps = getParam<std::vector<Real>>("relative_permittivities");
  for (std::size_t n = 0; n < blocks.size(); ++n)
    geometry("maxwell_dielectric_" + blocks[n], eps[n], false);
}

void
MaxwellPhysics::addMaterials()
{
  if (!physicalCoils())
    return;
  const auto function_material = [&](const std::string & id,
      const std::vector<SubdomainName> & blocks, bool plasma, const FunctionName & geom)
  {
    auto params = getFactory().getValidParams("GenericFunctionMaterial");
    params.set<std::vector<std::string>>("prop_names") = plasma ?
        std::vector<std::string>{"neg_a_geom_t6"} : std::vector<std::string>{"neg_a", "b"};
    params.set<std::vector<FunctionName>>("prop_values") = plasma ?
        std::vector<FunctionName>{geom} : std::vector<FunctionName>{geom, "zero_fn"};
    assignBlocks(params, blocks);
    getProblem().addMaterial("GenericFunctionMaterial", id, params);
  };
  const auto & plasma = getParam<std::vector<SubdomainName>>("plasma_blocks");
  function_material("vacuum_like", getParam<std::vector<SubdomainName>>("vacuum_blocks"), false, "neg_a_vac_fn");
  function_material("plasma_geom_t6", plasma, true, "neg_a_plasma_geom_t6");
  for (const auto & block : getParam<std::vector<SubdomainName>>("dielectric_blocks"))
    function_material("maxwell_dielectric_" + block + "_material", {block}, false,
                      "maxwell_dielectric_" + block);
  const auto parsed = [&](const std::string & id, const std::string & property,
      const std::vector<std::string> & deps, const std::string & expression)
  {
    auto params = getFactory().getValidParams("ParsedMaterial");
    params.set<std::string>("property_name") = property;
    params.set<std::vector<std::string>>("material_property_names") = deps;
    params.set<std::vector<std::string>>("constant_names") = {"ommu"};
    params.set<std::vector<std::string>>("constant_expressions") =
        {rfLiteral(angularFrequency() * rf_mu0)};
    params.set<std::string>("expression") = expression;
    assignBlocks(params, plasma);
    getProblem().addMaterial("ParsedMaterial", id, params);
  };
  parsed("plasma_neg_a_t6", "neg_a", {"neg_a_geom_t6", "sigma_imag_t6"},
         "neg_a_geom_t6 + ommu*sigma_imag_t6");
  parsed("plasma_b_t6", "b", {"sigma_real_t6"}, "ommu*sigma_real_t6");
}

void
MaxwellPhysics::checkIntegrity() const
{
  const auto & real_field = getParam<VariableName>("field_real");
  const auto & imaginary_field = getParam<VariableName>("field_imag");
  if (!solverVariableExists(real_field))
    paramError("field_real", "Real electromagnetic field was not found: ", real_field);
  if (!solverVariableExists(imaginary_field))
    paramError("field_imag", "Imaginary electromagnetic field was not found: ", imaginary_field);
  if (isVariableFV(real_field) != isVariableFV(imaginary_field))
    paramError("field_imag", "Real and imaginary fields must use the same numerical method.");
  if (ownsOperators())
    for (const auto & variable : {real_field, imaginary_field})
    {
      requireUniqueFEKernel("Diffusion", variable);
      requireUniqueFEKernel("MatReaction", variable);
      requireUniqueFEKernel("MatCoupledForce", variable);
    }
}

void
MaxwellPhysics::addFEKernels()
{
  if (!ownsOperators())
    return;
  const auto real = getParam<VariableName>("field_real");
  const auto imag = getParam<VariableName>("field_imag");
  for (const auto & variable : {real, imag})
  {
    {
      const std::string type = "Diffusion";
      auto params = getFactory().getValidParams(type);
      params.set<NonlinearVariableName>("variable") = variable;
      assignBlocks(params, _blocks);
      getProblem().addKernel(type, name() + "_" + variable + "_diffusion", params);
    }
    {
      const std::string type = "MatReaction";
      auto params = getFactory().getValidParams(type);
      params.set<NonlinearVariableName>("variable") = variable;
      params.set<MaterialPropertyName>("reaction_rate") =
          physicalCoils() ? MaterialPropertyName("neg_a") : getParam<MaterialPropertyName>("reaction_material");
      assignBlocks(params, _blocks);
      getProblem().addKernel(type, name() + "_" + variable + "_reaction", params);
    }
    {
      const std::string type = "MatCoupledForce";
      auto params = getFactory().getValidParams(type);
      params.set<NonlinearVariableName>("variable") = variable;
      params.set<std::vector<VariableName>>("v") = {variable == real ? imag : real};
      params.set<std::vector<Real>>("coef") = {variable == real ? 1.0 : -1.0};
      params.set<std::vector<MaterialPropertyName>>("material_properties") =
          {physicalCoils() ? MaterialPropertyName("b") : getParam<MaterialPropertyName>("coupling_material")};
      assignBlocks(params, _blocks);
      getProblem().addKernel(type, name() + "_" + variable + "_coupling", params);
    }
  }
  if (physicalCoils() || isParamValid("imaginary_source"))
  {
    const std::string type = "BodyForce";
    auto params = getFactory().getValidParams(type);
    params.set<NonlinearVariableName>("variable") = imag;
    params.set<Real>("value") = physicalCoils() ?
        -angularFrequency() * rf_mu0 * (getParam<Real>("coil_current_A") /
                                        getParam<Real>("coil_cross_section_m2")) :
        getParam<Real>("imaginary_source");
    if (isParamValid("coil_blocks"))
    {
      params.set<PostprocessorName>("postprocessor") = physicalCoils() ?
          PostprocessorName("rf_drive_scale_child") : getParam<PostprocessorName>("coil_drive_scale");
      for (const auto & block : getParam<std::vector<SubdomainName>>("coil_blocks"))
      {
        auto local = params;
        assignBlocks(local, std::vector<SubdomainName>{block});
        getProblem().addKernel(type, block + "_current", local);
      }
    }
    else
    {
      // Retain the legacy prescribed source on the Action's operator blocks.
      assignBlocks(params, _blocks);
      getProblem().addKernel(type, name() + "_imaginary_source", params);
    }
  }
}

void
MaxwellPhysics::addFEBCs()
{
  if (!ownsOperators())
    return;
  const auto real = getParam<VariableName>("field_real");
  const auto imag = getParam<VariableName>("field_imag");
  for (const auto & boundary : getParam<std::vector<BoundaryName>>("ground_boundaries"))
    for (const auto & variable : {real, imag})
    {
      const std::string type = "DirichletBC";
      auto params = getFactory().getValidParams(type);
      params.set<NonlinearVariableName>("variable") = variable;
      params.set<std::vector<BoundaryName>>("boundary") = {boundary};
      params.set<Real>("value") = 0;
      getProblem().addBoundaryCondition(
          type, name() + "_" + variable + "_ground_" + boundary, params);
    }
}

}

using Plasma::MaxwellPhysics;
registerPhysicsBaseTasks("PhysicsApp", MaxwellPhysics);
registerMooseAction("PhysicsApp", MaxwellPhysics, "check_integrity");
registerMooseAction("PhysicsApp", MaxwellPhysics, "add_variables_physics");
registerMooseAction("PhysicsApp", MaxwellPhysics, "add_function");
registerMooseAction("PhysicsApp", MaxwellPhysics, "add_materials_physics");
registerMooseAction("PhysicsApp", MaxwellPhysics, "add_kernel");
registerMooseAction("PhysicsApp", MaxwellPhysics, "add_bc");
