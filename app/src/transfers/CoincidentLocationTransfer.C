#include "CoincidentLocationTransfer.h"
#include <cmath>

registerMooseObject("PhysicsApp", CoincidentLocationTransfer);

InputParameters
CoincidentLocationTransfer::validParams()
{
  auto params = MultiAppGeneralFieldNearestLocationTransfer::validParams();
  params.addClassDescription("Copies a single coincident source node or centroid; never extrapolates.");
  params.addRangeCheckedParam<Real>("coincidence_tolerance", 1e-12,
                                    "coincidence_tolerance >= 0",
                                    "Maximum coordinate distance in the transfer reference frame");
  return params;
}

CoincidentLocationTransfer::CoincidentLocationTransfer(const InputParameters & params)
  : MultiAppGeneralFieldNearestLocationTransfer(params),
    _coincidence_tolerance(getParam<Real>("coincidence_tolerance"))
{
  if (getParam<unsigned int>("num_nearest_points") != 1)
    paramError("num_nearest_points", "Coincident transfer requires exactly one source location");
  if (!getParam<bool>("error_on_miss"))
    paramError("error_on_miss", "Coincident transfer must reject missing locations");
  if (getParam<MooseEnum>("post_transfer_extrapolation") != "none")
    paramError("post_transfer_extrapolation", "Coincident transfer must not extrapolate");
}

void
CoincidentLocationTransfer::evaluateInterpValues(
    const unsigned int var_index,
    const std::vector<std::pair<Point, unsigned int>> & incoming_points,
    std::vector<std::pair<Real, Real>> & outgoing_vals)
{
  MultiAppGeneralFieldNearestLocationTransfer::evaluateInterpValues(
      var_index, incoming_points, outgoing_vals);
  for (auto & value : outgoing_vals)
    if (!std::isfinite(value.second) || value.second > _coincidence_tolerance)
      value = {GeneralFieldTransfer::OutOfMeshValue, GeneralFieldTransfer::OutOfMeshValue};
}
