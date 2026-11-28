#pragma once

#include "VolumetricFlowRate.h"

// Report one-sided flow-domain flux with its physical outward normal.
class BoundaryVolumetricFlowRate : public VolumetricFlowRate
{
public:
  static InputParameters validParams();
  explicit BoundaryVolumetricFlowRate(const InputParameters & params);
protected:
  Real computeFaceInfoIntegral(const FaceInfo * fi) override;
};
