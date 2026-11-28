"""Patch one-sided FV flow reporting in the disposable pinned MOOSE tree."""
import hashlib,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1])
def git(*args):
    return subprocess.check_output(["git","-C",str(root),*args],text=True).strip()
assert git("rev-parse","HEAD")=="9f388366ccf38b9c34542ec5561198249fde0ac9"
path=root/"modules/navier_stokes/src/postprocessors/VolumetricFlowRate.C"
before=path.read_bytes()
assert git("hash-object",str(path))=="c0f8eb4b2c3b1d103b860350a985d4937752a6d3"
old="  const auto * elem = _adv_quant->hasFaceSide(*fi, true) ? fi->elemPtr() : fi->neighborPtr();"
new="  // A block-restricted flow domain has a physical boundary even when the mesh\n  // has a geometric neighbor. Keep the provider's FaceInfo-oriented flux for\n  // the upwind decision; orient only the reported flux out of the flow domain.\n  const bool flow_on_elem = _rc_uo->hasFaceSide(*fi, true);\n  const bool flow_on_neighbor = _rc_uo->hasFaceSide(*fi, false);\n  if (!flow_on_elem && !flow_on_neighbor)\n    mooseError(\"Volumetric flow rate requested on a face outside the flow domain: \", name());\n\n  const bool one_sided_flow = flow_on_elem != flow_on_neighbor;\n  if (one_sided_flow && !_adv_quant->hasFaceSide(*fi, flow_on_elem))\n    mooseError(\"Advected quantity is not defined on the active flow side: \", name());\n\n  const auto * elem = one_sided_flow\n                          ? (flow_on_elem ? fi->elemPtr() : fi->neighborPtr())\n                          : (_adv_quant->hasFaceSide(*fi, true) ? fi->elemPtr() : fi->neighborPtr());"
old2="  return face_flux * adv_quant_face;"
new2="  return (one_sided_flow && flow_on_neighbor ? -face_flux : face_flux) * adv_quant_face;"
text=before.decode()
assert text.count(old)==1 and text.count(old2)==1
path.write_text(text.replace(old,new).replace(old2,new2))
assert set(git("diff","--name-only").splitlines())=={"modules/navier_stokes/src/postprocessors/VolumetricFlowRate.C","framework/src/variables/MooseVariableFV.C"}
print("FLOW_PATCH_BEFORE_SHA256",hashlib.sha256(before).hexdigest())
print("FLOW_PATCH_AFTER_SHA256",hashlib.sha256(path.read_bytes()).hexdigest())
print(git("diff","--","modules/navier_stokes/src/postprocessors/VolumetricFlowRate.C"))
