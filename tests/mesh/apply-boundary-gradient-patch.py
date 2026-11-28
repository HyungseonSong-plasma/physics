"""Apply exactly one reviewed change to the pinned MOOSE source in a disposable container."""
import hashlib, pathlib, subprocess, sys
root=pathlib.Path(sys.argv[1])
expected="9f388366ccf38b9c34542ec5561198249fde0ac9"
def git(*args):
    return subprocess.check_output(["git","-C",str(root),*args],text=True).strip()
assert git("rev-parse","HEAD")==expected
path=root/"framework/src/variables/MooseVariableFV.C"
before=path.read_bytes()
assert git("hash-object",str(path))=="9b3439e294122c771c43630cf4efc19fdbe34b5a"
old="  const auto delta =\n      this->isInternalFace(fi)\n          ? fi.dCNMag()\n          : (fi.faceCentroid() - (var_defined_on_elem ? fi.elemCentroid() : fi.neighborCentroid()))\n                .norm();\n\n  // This is the component of the gradient which is parallel to the line connecting\n  // the cell centers. Therefore, we can use our second order, central difference\n  // scheme to approximate it.\n  auto face_grad = ((side_two_value - side_one_value) / delta) * fi.eCN();"
new="  // Match the difference stencil to the variable's physical domain. On a\n  // block boundary the inactive neighbor centroid is not a solution point.\n  // Keep the direction oriented from side one to side two, even when the\n  // active variable is on the FaceInfo neighbor.\n  const Point displacement = is_internal_face\n                                 ? Point(fi.dCN())\n                                 : (var_defined_on_elem\n                                        ? Point(fi.faceCentroid() - fi.elemCentroid())\n                                        : Point(fi.neighborCentroid() - fi.faceCentroid()));\n  const auto delta = is_internal_face ? fi.dCNMag() : displacement.norm();\n  const Point direction = is_internal_face ? Point(fi.eCN()) : Point(displacement / delta);\n\n  auto face_grad = ((side_two_value - side_one_value) / delta) * direction;"
old2="    face_grad += interpolated_gradient - (interpolated_gradient * fi.eCN()) * fi.eCN();"
new2="    face_grad += interpolated_gradient - (interpolated_gradient * direction) * direction;"
text=before.decode()
assert text.count(old)==1 and text.count(old2)==1
path.write_text(text.replace(old,new).replace(old2,new2))
assert git("diff","--name-only")=="framework/src/variables/MooseVariableFV.C"
print("MOOSE_PINNED_SOURCE",expected)
print("MOOSE_PATCH_BEFORE_SHA256",hashlib.sha256(before).hexdigest())
print("MOOSE_PATCH_AFTER_SHA256",hashlib.sha256(path.read_bytes()).hexdigest())
print(git("diff","--","framework/src/variables/MooseVariableFV.C"))
