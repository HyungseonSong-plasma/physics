// Diagnostic-only: compare native and proposed block-boundary face gradients.
#include "SideIntegralPostprocessor.h"
#include "MooseVariableFV.h"
#include "FaceInfo.h"
#include "metaphysicl/raw_type.h"

class BoundaryGradientProbe : public SideIntegralPostprocessor
{
public:
  static InputParameters validParams();
  BoundaryGradientProbe(const InputParameters & p);
protected:
  Real computeQpIntegral() override { mooseError("FaceInfo integration required"); }
  Real computeFaceInfoIntegral(const FaceInfo * fi) override;
  MooseVariableFV<Real> * _fv;
  const MooseEnum _metric;
};

registerMooseObject("PhysicsApp", BoundaryGradientProbe);

InputParameters
BoundaryGradientProbe::validParams()
{
  auto p = SideIntegralPostprocessor::validParams();
  p.addRequiredCoupledVar("variable", "Scalar FV variable on the active block");
  p.addRequiredParam<MooseEnum>("metric",
      MooseEnum("native_error corrected_error cell_error native_flux_error corrected_flux_error active_owner"),
      "Integrated diagnostic quantity");
  return p;
}

BoundaryGradientProbe::BoundaryGradientProbe(const InputParameters & p)
  : SideIntegralPostprocessor(p),
    _fv(dynamic_cast<MooseVariableFV<Real> *>(getFieldVar("variable", 0))),
    _metric(getParam<MooseEnum>("metric"))
{
  if (!_fv)
    paramError("variable", "A nonlinear scalar FV variable is required");
  addMooseVariableDependency(_fv);
  _qp_integration = false;
}

Real
BoundaryGradientProbe::computeFaceInfoIntegral(const FaceInfo * fi)
{
  const bool owner = fi->elemPtr() == _current_elem;
  if (!owner && fi->neighborPtr() != _current_elem)
    mooseError("Probe sideset owner does not touch FaceInfo");
  if (_fv->isInternalFace(*fi) || !_fv->hasBlocks(_current_elem->subdomain_id()))
    mooseError("Expected one active side of a block boundary");
  const auto state = determineState();
  const RealVectorValue exact(2, 3, 0);
  const RealVectorValue native = MetaPhysicL::raw_value(_fv->adGradSln(*fi, state, false));
  const RealVectorValue cell = MetaPhysicL::raw_value(_fv->uncorrectedAdGradSln(*fi, state, false));
  const Point displacement = fi->faceCentroid() -
      (owner ? fi->elemCentroid() : fi->neighborCentroid());
  const Real distance = displacement.norm();
  const RealVectorValue e = displacement / distance;
  const Real jump = MetaPhysicL::raw_value(_fv->getBoundaryFaceValue(*fi, state, false) -
                                          _fv->getElemValue(_current_elem, state));
  const RealVectorValue corrected = cell + (jump / distance - cell * e) * e;
  const RealVectorValue outward = owner ? fi->normal() : -fi->normal();
  if (_metric == "native_error") return (native - exact).norm();
  if (_metric == "corrected_error") return (corrected - exact).norm();
  if (_metric == "cell_error") return (cell - exact).norm();
  if (_metric == "native_flux_error") return std::abs((native - exact) * outward);
  if (_metric == "corrected_flux_error") return std::abs((corrected - exact) * outward);
  if (_metric == "active_owner") return owner ? 1. : 0.;
  mooseError("Unknown diagnostic metric");
}
