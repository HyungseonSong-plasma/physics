#pragma once

#include "PlasmaInterface.h"

namespace Plasma
{

/**
 * Generates opt-in RF operators, grounded boundaries and driven coil sources.
 */
class MaxwellPhysics : public PlasmaInterface
{
public:
  static InputParameters validParams();
  explicit MaxwellPhysics(const InputParameters & parameters);

private:
  void checkIntegrity() const override;
  void addFEKernels() override;
  void addFEBCs() override;
};

}
