#pragma once

#include "MooseMesh.h"
#include "libmesh/elem.h"
#include "libmesh/remote_elem.h"

namespace PhysicsBoundaryFaceInfo
{
// The pinned MOOSE caches one FaceInfo per face, on its owning element.
// Resolve it from either side of a conformal interface without rebuilding
// the cache or changing the face orientation. A missing face remains an error
// for the caller; this does not manufacture a boundary FaceInfo.
inline const FaceInfo *
find(const MooseMesh & mesh, const Elem * elem, unsigned int side)
{
  if (const auto * fi = mesh.faceInfo(elem, side))
    return fi;

  const auto * neighbor = elem->neighbor_ptr(side);
  if (!neighbor || neighbor == libMesh::remote_elem)
    return nullptr;

  const auto neighbor_side = neighbor->which_neighbor_am_i(elem);
  if (neighbor_side >= neighbor->n_sides())
    return nullptr;

  return mesh.faceInfo(neighbor, neighbor_side);
}
}
