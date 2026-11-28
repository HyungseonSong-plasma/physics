#include "PhysicsFVMomentumBudget.h"
#include "PhysicsBoundaryFaceInfo.h"
#include "FEProblemBase.h"
#include "FaceInfo.h"
#include "MathFVUtils.h"
#include "FVUtils.h"
#include "Limiter.h"
#include "RhieChowFaceFluxProvider.h"
#include "metaphysicl/raw_type.h"
#include <cmath>

registerMooseObject("PhysicsApp", PhysicsFVMomentumBudget);

InputParameters
PhysicsFVMomentumBudget::validParams()
{
  auto params = ElementPostprocessor::validParams();
  params.addClassDescription("Reconstructs accepted-state RZ momentum terms separately from residual assembly; fixed nonporous Laplace-viscosity case with radial inlet.");
  params.addRequiredParam<VariableName>("variable", "FV velocity component");
  params.addRequiredParam<MooseFunctorName>("pressure", "Pressure functor");
  params.addRequiredParam<MooseFunctorName>("rho", "Density functor");
  params.addRequiredParam<MooseFunctorName>("mu", "Dynamic viscosity functor");
  params.addRequiredParam<PostprocessorName>("inlet_mdot", "Imposed inlet mass flow");
  params.addRequiredParam<PostprocessorName>("inlet_area", "Inlet RZ area");
  params.addRequiredParam<MooseEnum>("component", MooseEnum("x=0 y=1"), "Momentum component");
  params.addRequiredParam<MooseEnum>("term", MooseEnum("pressure viscous inlet rz"), "Reconstructed term");
  params.addParam<bool>("absolute", false, "Sum absolute cell/face contributions for normalization");
  return params;
}

PhysicsFVMomentumBudget::PhysicsFVMomentumBudget(const InputParameters & p)
  : ElementPostprocessor(p),
    _velocity(dynamic_cast<MooseVariableFVReal &>(_fe_problem.getVariable(
        _tid, getParam<VariableName>("variable"), Moose::VarKindType::VAR_SOLVER,
        Moose::VarFieldType::VAR_FIELD_STANDARD))),
    _pressure(getFunctor<ADReal>("pressure")),
    _rho(getFunctor<ADReal>("rho")),
    _mu(getFunctor<ADReal>("mu")),
    _mdot(getPostprocessorValue("inlet_mdot")),
    _area(getPostprocessorValue("inlet_area")),
    _component(getParam<MooseEnum>("component")),
    _term(getParam<MooseEnum>("term")),
    _absolute(getParam<bool>("absolute"))
{
  addMooseVariableDependency(&_velocity);
  if (_term == "rz" && _component != 0)
    paramError("component", "RZ source applies only to the radial component.");
}

void PhysicsFVMomentumBudget::initialize() { _sum = 0; }

void
PhysicsFVMomentumBudget::add(Real value)
{
  if (!std::isfinite(value))
    mooseError(name(), ": nonfinite reconstructed momentum term");
  _sum += _absolute ? std::abs(value) : value;
}

void
PhysicsFVMomentumBudget::execute()
{
  const auto state = determineState();
  const Moose::ElemArg cell{_current_elem, false};
  using MetaPhysicL::raw_value;
  if (_term == "pressure")
  {
    add(raw_value(_pressure.gradient(cell, state)(_component)) * _current_elem_volume);
    return;
  }
  if (_term == "rz")
  {
    const Real r = _current_elem->vertex_average()(0);
    if (r <= 0)
      mooseError(name(), ": nonpositive cell radius");
    add(raw_value(_mu(cell, state) * _velocity(cell, state)) * _current_elem_volume / (r*r));
    return;
  }
  // Interior advective and viscous face contributions cancel in a domain sum.
  // Integrate each flow boundary face once, from the active side.
  for (unsigned int side = 0; side < _current_elem->n_sides(); ++side)
  {
    const auto * fi = PhysicsBoundaryFaceInfo::find(_mesh, _current_elem, side);
    if (!fi)
      mooseError(name(), ": missing native FaceInfo");
    const bool owner = fi->elemPtr() == _current_elem;
    if (!owner && fi->neighborPtr() != _current_elem)
      mooseError(name(), ": inconsistent FaceInfo owner");
    const auto * other = owner ? fi->neighborPtr() : fi->elemPtr();
    if (other && _velocity.hasBlocks(other->subdomain_id()))
      continue;
    const Real weight = fi->faceArea() * fi->faceCoord();
    if (weight == 0)
      continue;
    if (!std::isfinite(weight) || weight < 0)
      mooseError(name(), ": invalid face measure");
    const Real sign = owner ? 1.0 : -1.0;
    const Moose::FaceArg face{fi, Moose::FV::limiterType(Moose::FV::InterpMethod::Average),
                              true, false, _current_elem, nullptr};
    const bool inlet = fi->boundaryIDs().count(_mesh.getBoundaryID("inlet"));
    const bool flux_bc = _velocity.getFluxBCs(*fi).first;
    if (inlet != flux_bc)
      mooseError(name(), ": unexpected momentum flux BC coverage");
    if (_term == "inlet" && inlet)
    {
      // WCNSFVMomentumFluxBC with positive mdot and direction (-1,0,0).
      const Real rho = raw_value(_rho(face, state));
      const Real cos_angle = std::abs(fi->normal()(0));
      if (_area <= 0 || _mdot <= 0 || rho <= 0 || cos_angle <= 0)
        mooseError(name(), ": invalid inlet reconstruction");
      const Real mass_flux = _mdot / _area;
      const Real speed = mass_flux / (rho * cos_angle);
      add((_component == 0 ? mass_flux * speed : 0.0) * weight);
    }
    else if (_term == "viscous" && !flux_bc && _velocity.getDirichletBC(*fi).first)
    {
      // Laplace viscosity, no complete expansion; native corrected face gradient.
      const Real mu = raw_value(_mu(face, state));
      if (mu < 0)
        mooseError(name(), ": negative viscosity");
      const Real grad = raw_value(Moose::FV::gradUDotNormal(*fi, _velocity, state, false));
      add(-mu * sign * grad * weight);
    }
  }
}

void PhysicsFVMomentumBudget::threadJoin(const UserObject & other)
{
  _sum += static_cast<const PhysicsFVMomentumBudget &>(other)._sum;
}
void PhysicsFVMomentumBudget::finalize() { gatherSum(_sum); }
PostprocessorValue PhysicsFVMomentumBudget::getValue() const { return _sum; }
