"""Normalize only file references in the exact qualified S6-417 inputs."""
import hashlib,json,pathlib,shutil,sys,zipfile,re
P=pathlib.Path
stage,layout,artifact,merged_child,out,receipt_path=map(P,sys.argv[1:])
sha=lambda b:hashlib.sha256(b).hexdigest()
def read_checked(p,digest):
    b=p.read_bytes()
    assert sha(b)==digest,(p,sha(b),digest)
    return b
def replace_exact(raw,old,new,count=1):
    assert raw.count(old)==count,(old,raw.count(old),count)
    return raw.replace(old,new)
with zipfile.ZipFile(artifact) as z:
    r=json.loads(z.read("single-input/equivalence.json"))
    assert r["status"]=="SINGLE_INPUT_NUMERICAL_EQUIVALENCE_PASS"
    inv=json.loads(z.read("single-input/input-inventory.json"))
    parent=z.read("single-input/input.i")
assert sha(parent)==r["input_sha256"]=="7f221b51e81c39812bafa635e2f3e0fe6eeee8c0a9f8586bfd1b2ec2333fffce"
current=json.loads(receipt_path.read_text())
chem=stage/"experiments/Issue395_powered_chemistry_ladder"
assert current["ordered"]==inv["original_layers"]
for rel in current["ordered"]:
    assert sha((stage/rel).read_bytes())==inv["files"][rel]["sha256"]
assert current["json_sha256"]==inv["files"]["experiments/Issue395_powered_chemistry_ladder/chemistry/public_d_s6_417_physics.json"]["sha256"]
src=chem/"chemistry/public_d_s6_417_physics.json"
j=read_checked(src,current["json_sha256"])
oldj=b'../../../physics_app/database/electron_moments.txt'
j2=replace_exact(j,oldj,b'electron_moments.txt')
expected=json.loads(j);expected["species"]["e"]["transport_coef"]["file"]="electron_moments.txt"
assert json.loads(j2)==expected
parent=replace_exact(parent,b'baseline_plasma_plus_unstructured_cover_plus_wafer.msh',b'mesh.msh')
parent=replace_exact(parent,b'rf_elastic_multiapp_maxwell_400w_100us_dt1000ns_child.i',b'maxwell.i')
parent=replace_exact(parent,b'chemistry/public_d_s6_417_physics.json',b'chemistry.json')
parent=replace_exact(parent,b'../../physics_app/database/',b'',6)
child=merged_child.read_bytes()
child=replace_exact(child,b'../Issue18_qvt_plasma_mapping/qvt.msh',b'maxwell.msh')
assert b'!include' not in child
for n,raw in {"input.i":parent,"maxwell.i":child,"chemistry.json":j2}.items():
    assert b'private_rates' not in raw and b'physics_app/database/' not in raw
    assert b'../' not in b'\n'.join(l for l in raw.splitlines() if not l.lstrip().startswith(b'#')),n
out.mkdir()
shutil.copytree(layout/"assets",out/"assets")
assets=out/"assets"
check={"mesh.msh":"experiments/Issue395_powered_chemistry_ladder/baseline_plasma_plus_unstructured_cover_plus_wafer.msh","maxwell.msh":"experiments/Issue18_qvt_plasma_mapping/qvt.msh"}
for name in ("o2_elastic.txt","o_elastic.txt"):check[name]=f"experiments/Issue395_powered_chemistry_ladder/{name}"
for name in current["database_sha256"]|current["rates_sha256"]:check[name]=f"physics_app/database/{name}"
for dest,rel in check.items():
    assert (assets/dest).read_bytes()==read_checked(stage/rel,inv["files"][rel]["sha256"]),dest
for name,raw in {"input.i":parent,"maxwell.i":child,"chemistry.json":j2}.items():
    (assets/name).write_bytes(raw)
print("FLAT_INPUT_PATH_ONLY_AND_DATA_IDENTITY_PASS")
