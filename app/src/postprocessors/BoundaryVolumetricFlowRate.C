#include "BoundaryVolumetricFlowRate.h"
#include "RhieChowFaceFluxProvider.h"
#include "FaceInfo.h"
#include "metaphysicl/raw_type.h"

registerMooseObject("PhysicsApp", BoundaryVolumetricFlowRate);

InputParameters
BoundaryVolumetricFlowRate::validParams()
{
  auto params = VolumetricFlowRate::validParams();
  params.addClassDescription("Reports one-sided flow-domain flux with an outward normal.");
  return params;
}

BoundaryVolumetricFlowRate::BoundaryVolumetricFlowRate(const InputParameters & params)
  : VolumetricFlowRate(params)
{
}

Real
BoundaryVolumetricFlowRate::computeFaceInfoIntegral(const FaceInfo * fi)
{
  const bool on_elem = _rc_uo->hasFaceSide(*fi, true);
  const bool on_neighbor = _rc_uo->hasFaceSide(*fi, false);
  if (!on_elem && !on_neighbor)
    mooseError("Volumetric flow rate requested on a face outside the flow domain: ", name());
  if (on_elem && on_neighbor)
    return VolumetricFlowRate::computeFaceInfoIntegral(fi);

  if (!_adv_quant->hasFaceSide(*fi, on_elem))
    mooseError("Advected quantity is not defined on the active flow side: ", name());

  const auto state = determineState();
  const auto raw_flux = MetaPhysicL::raw_value(_rc_uo->getVolumetricFaceFlux(
      _velocity_interp_method, *fi, state, _tid, _subtract_mesh_velocity));
  const auto * active = on_elem ? fi->elemPtr() : fi->neighborPtr();
  const bool skew = _advected_interp_method == Moose::FV::InterpMethod::SkewCorrectedAverage;
  const auto quantity = MetaPhysicL::raw_value((*_adv_quant)(
      Moose::FaceArg({fi, Moose::FV::limiterType(_advected_interp_method),
                      raw_flux > 0, skew, active, nullptr}), state));
  return (on_elem ? raw_flux : -raw_flux) * quantity;
}
