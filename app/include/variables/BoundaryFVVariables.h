#pragma once

#include "INSFVVelocityVariable.h"
#include "INSFVPressureVariable.h"
#include "INSFVScalarFieldVariable.h"
#include "FaceInfo.h"
#include "MooseMesh.h"

// Keep the native variable class and its INS-specific behavior. Only a
// geometrically internal, one-sided variable boundary needs a new stencil.
template <class Base>
class BoundaryFVVariable : public Base
{
public:
  explicit BoundaryFVVariable(const InputParameters & params) : Base(params) {}
  static InputParameters validParams() { return Base::validParams(); }

  using Base::adGradSln;
  VectorValue<ADReal> adGradSln(const FaceInfo & fi,
                               const Moose::StateArg & state,
                               bool correct_skewness = false) const override
  {
    if (!fi.neighborPtr() || this->isInternalFace(fi))
      return Base::adGradSln(fi, state, correct_skewness);

    const bool on_elem = this->hasBlocks(fi.elem().subdomain_id());
    const Elem * active = on_elem ? fi.elemPtr() : fi.neighborPtr();
    mooseAssert(this->hasBlocks(active->subdomain_id()), "No active variable side");
    const Point displacement = fi.faceCentroid() -
                               (on_elem ? fi.elemCentroid() : fi.neighborCentroid());
    const Real distance = displacement.norm();
    const Point direction(displacement / distance);
    const ADReal jump = this->getBoundaryFaceValue(fi, state, correct_skewness) -
                        this->getElemValue(active, state);
    auto gradient = (jump / distance) * direction;
    if (this->_mesh.dimension() > 1)
    {
      const auto cell_gradient = this->uncorrectedAdGradSln(fi, state, correct_skewness);
      gradient += cell_gradient - (cell_gradient * direction) * direction;
    }
    return gradient;
  }
};

class BoundaryINSFVVelocityVariable : public BoundaryFVVariable<INSFVVelocityVariable>
{
public:
  using BoundaryFVVariable<INSFVVelocityVariable>::BoundaryFVVariable;
  using BoundaryFVVariable<INSFVVelocityVariable>::uncorrectedAdGradSln;
  VectorValue<ADReal> uncorrectedAdGradSln(const FaceInfo & fi,
                                          const Moose::StateArg & state,
                                          bool correct_skewness = false) const override;
};

class BoundaryINSFVPressureVariable : public BoundaryFVVariable<INSFVPressureVariable>
{
public:
  using BoundaryFVVariable<INSFVPressureVariable>::BoundaryFVVariable;
};

class BoundaryINSFVScalarFieldVariable : public BoundaryFVVariable<INSFVScalarFieldVariable>
{
public:
  using BoundaryFVVariable<INSFVScalarFieldVariable>::BoundaryFVVariable;
};
