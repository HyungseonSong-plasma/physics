#include "MaxwellPhysics.h"

#include <algorithm>
#include <cmath>
#include <set>

namespace Plasma
{

InputParameters
MaxwellPhysics::validParams()
{
  InputParameters params = PlasmaInterface::validParams();
  params.addClassDescription(
      "Generates RF field operators, grounded boundaries and optional driven coil sources.");
  params.addRequiredParam<VariableName>(
      "field_real", "Existing solver variable for the real electromagnetic field.");
  params.addRequiredParam<VariableName>(
      "field_imag", "Existing solver variable for the imaginary electromagnetic field.");
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
  if (isParamValid("reaction_material"))
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
  if (!isParamValid("reaction_material"))
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
          getParam<MaterialPropertyName>("reaction_material");
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
          {getParam<MaterialPropertyName>("coupling_material")};
      assignBlocks(params, _blocks);
      getProblem().addKernel(type, name() + "_" + variable + "_coupling", params);
    }
  }
  if (isParamValid("imaginary_source"))
  {
    const std::string type = "BodyForce";
    auto params = getFactory().getValidParams(type);
    params.set<NonlinearVariableName>("variable") = imag;
    params.set<Real>("value") = getParam<Real>("imaginary_source");
    if (isParamValid("coil_blocks"))
    {
      params.set<PostprocessorName>("postprocessor") = getParam<PostprocessorName>("coil_drive_scale");
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
  if (!isParamValid("reaction_material"))
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
registerMooseAction("PhysicsApp", MaxwellPhysics, "add_kernel");
registerMooseAction("PhysicsApp", MaxwellPhysics, "add_bc");
