#include "BoundaryFVVariables.h"

registerMooseObject("PhysicsApp", BoundaryINSFVVelocityVariable);
registerMooseObject("PhysicsApp", BoundaryINSFVPressureVariable);
registerMooseObject("PhysicsApp", BoundaryINSFVScalarFieldVariable);

VectorValue<ADReal>
BoundaryINSFVVelocityVariable::uncorrectedAdGradSln(const FaceInfo & fi,
                                                     const Moose::StateArg & state,
                                                     bool correct_skewness) const
{
  // The standard fully-developed branch reads fi.elem() unconditionally.
  // Use the active neighbor when it is the only side with velocity DOFs.
  if (fi.neighborPtr() && !this->hasBlocks(fi.elem().subdomain_id()) &&
      this->hasBlocks(fi.neighbor().subdomain_id()) &&
      this->getTwoTermBoundaryExpansion() && this->isFullyDevelopedFlowFace(fi))
  {
    const auto cell_gradient = INSFVVelocityVariable::adGradSln(
        fi.neighborPtr(), state, correct_skewness);
    const auto & normal = fi.normal();
    return cell_gradient - (cell_gradient * normal) * normal;
  }
  return INSFVVelocityVariable::uncorrectedAdGradSln(fi, state, correct_skewness);
}
