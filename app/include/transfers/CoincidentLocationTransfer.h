#pragma once

#include "MultiAppGeneralFieldNearestLocationTransfer.h"

// Copy a coincident source DOF only. Reject non-coincident candidates locally
// so the base transfer can search other ranks, and error if none is found.
class CoincidentLocationTransfer : public MultiAppGeneralFieldNearestLocationTransfer
{
public:
  static InputParameters validParams();
  explicit CoincidentLocationTransfer(const InputParameters & params);

protected:
  void evaluateInterpValues(
      unsigned int var_index,
      const std::vector<std::pair<Point, unsigned int>> & incoming_points,
      std::vector<std::pair<Real, Real>> & outgoing_vals) override;

private:
  const Real _coincidence_tolerance;
};
