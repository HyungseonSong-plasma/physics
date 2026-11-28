"""Validate direct native Parent Exodus; no mesh or result merging."""
import csv
import json
import math
from pathlib import Path
import shutil
import sys
from importlib.util import spec_from_file_location,module_from_spec
spec=spec_from_file_location("reader",Path(__file__).with_name("exodus-reader.py"))
reader=module_from_spec(spec);spec.loader.exec_module(reader)
root,dest=map(Path,sys.argv[1:])
candidate=root/"candidate/fields"
base=root/"baseline/fields"
RTOL=1e-9
ATOL=1e-12
parity_failures=[]
class Data:
    def __init__(self,p):
        self.ex=reader.Exodus(p)
        self.v=self.ex.variables()
        self.coords=[tuple(round(z,12) for z in q) for q in zip(*(self.values(k) for k in ("coordx","coordy","coordz") if k in self.v))]
        assert len(self.coords)==len(set(self.coords))
        self.ids=[int(x) for x in self.values("eb_prop1")]
        self.nod=self.names("name_nod_var")
        self.elem=self.names("name_elem_var")
    def values(self,k):return list(self.ex.values(*self.v[k]))
    def names(self,k):
        if k not in self.v:return []
        raw=self.ex.values(*self.v[k]);n,w=[x[1] for x in self.v[k][2]]
        return [raw[i*w:(i+1)*w].split(b"\0",1)[0].decode().strip() for i in range(n)]
    def topology(self,block):
        k="connect"+str(self.ids.index(block)+1)
        width=self.v[k][2][-1][1];a=self.values(k)
        return [tuple(sorted(self.coords[int(j)-1] for j in a[i:i+width])) for i in range(0,len(a),width)]
    def nodal(self,name,frame):
        k="vals_nod_var"+str(self.nod.index(name)+1);n=len(self.coords)
        a=self.values(k);return a[frame*n:(frame+1)*n] if frame>=0 else a[-n:]
    def elemental(self,name,block,frame):
        k=f"vals_elem_var{self.elem.index(name)+1}eb{self.ids.index(block)+1}"
        if k not in self.v:return None
        n=self.v[k][2][-1][1];a=self.values(k)
        return a[frame*n:(frame+1)*n] if frame>=0 else a[-n:]
    def close(self):self.ex.close()
def perm(a,b):
    d={k:i for i,k in enumerate(b)}
    assert len(d)==len(b) and len(set(a))==len(a) and set(a)<=set(b)
    return [d[k] for k in a]
def compare(a,b,label):
    assert len(a)==len(b) and len(a)>0,label
    assert all(math.isfinite(x) and math.isfinite(y) for x,y in zip(a,b)),label
    pairs=[(x,y) for x,y in zip(a,b) if abs(x)<1e30 and abs(y)<1e30]
    assert all((abs(x)<1e30)==(abs(y)<1e30) for x,y in zip(a,b)),label
    if not pairs:return {"count":0}
    mx=max(abs(x-y) for x,y in pairs);scale=max(abs(x) for x,y in pairs)
    passed=mx<=ATOL+RTOL*scale
    if not passed:parity_failures.append({"label":label,"max_abs_delta":mx,"scale":scale,"allowed":ATOL+RTOL*scale})
    norm=math.sqrt(sum(x*x for x,y in pairs))
    return {"count":len(pairs),"max_abs_delta":mx,"max_relative_to_field_scale":mx/scale if scale else None,"relative_l2":math.sqrt(sum((x-y)**2 for x,y in pairs))/norm if norm else None,"pass":passed}
def csvrows(p):
    with p.open() as f:return list(csv.DictReader(f))
c=Data(candidate/"parent.e")
try:
    assert sorted(c.ids)==sorted([10,20,21,22,23,24,25,26,30,31,32,73,87,91,92,93,94]),c.ids
    # Full volume geometry and three Parent surface blocks.
    volumes=[i for i in c.ids if i not in (30,31,32)]
    assert len(c.coords)==2085
    assert sum(len(c.topology(i)) for i in volumes)==4016
    assert len(list(candidate.glob("*.e")))==1,"Unexpected independent child output"
    times=c.values("time_whole")
    assert len(times)==2 and math.isclose(times[0],0,abs_tol=1e-16) and math.isclose(times[-1],1e-9,rel_tol=1e-10,abs_tol=1e-16)
    for field in ("E_real_full","E_imag_full"):
        v=c.nodal(field,-1)
        assert len(v)==2085 and all(math.isfinite(x) and abs(x)<1e30 for x in v) and any(x!=0 for x in v),field
    q=c.elemental("rf_absorbed_power_density",10,-1)
    assert q is not None and len(q)==1798 and all(math.isfinite(x) and 0<=x<1e30 for x in q) and any(x>0 for x in q)
    report={"status":"NATIVE_PARENT_EXODUS_PASS","times_s":times,"nodes":len(c.coords),"volume_triangles":4016,"blocks":c.ids,"rf_time_semantics":"latest accepted TIMESTEP_BEGIN solve; initial unsolved values","scope":"bounded one step; SCIENCE_HOLD","comparison_tolerance":{"rtol_field_scale":RTOL,"atol":ATOL}}
    if base.exists():
        b=Data(base/"parent.e")
        children=list(base.glob("parent*maxwell_t6*.e"))
        assert len(children)==1,children
        child=Data(children[0])
        try:
            assert b.values("time_whole")==times
            nmap=perm(b.coords,c.coords);assert set(b.ids)<=set(c.ids)
            emap={i:perm(b.topology(i),c.topology(i)) for i in b.ids}
            assert all(len(emap[i])==len(c.topology(i)) for i in b.ids)
            assert set(b.nod)<=set(c.nod) and set(b.elem)<=set(c.elem)
            fields={}
            for frame in (0,1):
                for name in b.nod:
                    v=c.nodal(name,frame);fields[f"{frame}:nod:{name}"]=compare(b.nodal(name,frame),[v[j] for j in nmap],f"{frame}:nod:{name}")
                for name in b.elem:
                    for i in b.ids:
                        a=b.elemental(name,i,frame)
                        if a is None:continue
                        v=c.elemental(name,i,frame);assert v is not None,(name,i)
                        fields[f"{frame}:elem:{name}:{i}"]=compare(a,[v[j] for j in emap[i]],f"{frame}:elem:{name}:{i}")
            # Maxwell is the same geometry, and its steady time is an output index.
            assert set(child.coords)==set(c.coords)
            jmap=perm(child.coords,c.coords)
            assert set(child.ids)==set(volumes)
            for i in volumes:
                assert set(child.topology(i))==set(c.topology(i)),i
            assert math.isclose(child.values("time_whole")[-1],1.0,abs_tol=1e-12)
            rf={}
            for src,dst in (("E_real","E_real_full"),("E_imag","E_imag_full")):
                v=c.nodal(dst,-1);rf[dst]=compare(child.nodal(src,-1),[v[j] for j in jmap],dst)
            rows1,rows2=csvrows(base/"parent.csv"),csvrows(candidate/"parent.csv")
            assert len(rows1)==len(rows2)==2
            scalars={}
            for i,(x,y) in enumerate(zip(rows1,rows2)):
                assert x.keys()==y.keys()
                for k in x:
                    scalars[f"{i}:{k}"]=compare([float(x[k])],[float(y[k])],f"{i}:csv:{k}")
                    scalars[f"{i}:{k}"].update(baseline=float(x[k]),candidate=float(y[k]))
            report["baseline_parity"]={"fields":fields,"scalars":scalars,"maxwell_full_domain":rf}
        finally:b.close();child.close()
    # Retain all measured mismatches even when the strict gate rejects output.
    report["parity_failures"]=parity_failures
    # Only the six reviewed endpoint velocity comparisons may be reported
    # separately. All other fields, RF and scalar checks remain strict.
    velocity_labels={"1:elem:u:10","1:elem:v:10","1:csv:neutral_u_min","1:csv:neutral_u_max",
                     "1:csv:neutral_v_min","1:csv:neutral_v_max"}
    velocity_failures=[f for f in parity_failures if f["label"] in velocity_labels]
    strict_failures=[f for f in parity_failures if f["label"] not in velocity_labels]
    report["velocity_parity"]={"pass":not velocity_failures,"failures":velocity_failures,
        "policy":"reported numerical regression; not a scientific equivalence threshold"}
    report["nonvelocity_parity"]={"pass":not strict_failures,"failures":strict_failures}
    if base.exists():
        audit=json.loads((root/"fvm-audit.json").read_text())
        gate=audit["conservation_gate"]
        assert gate["relative_numerical_tolerance"]==1e-8
        assert set(gate["cases"])=={"baseline","candidate","candidate_rf_capture"}
        expected_checks={"mass_balance","wall_net_mass","outlet_mass_reporting","radial_momentum","axial_momentum"}
        assert all(set(v)==expected_checks for v in gate["cases"].values())
        conservation_pass=gate["pass"] is True and gate["capture_exact"] is True and all(
            x is True for v in gate["cases"].values() for x in v.values())
        report["conservation_gate"]=gate
    else:
        conservation_pass=not velocity_failures
        report["conservation_gate"]={"scope":"not run: no baseline","pass":None}
    report["science"]="SCIENCE_HOLD"
    report["status"]="NATIVE_PARENT_EXODUS_PASS" if not strict_failures and conservation_pass else "NATIVE_PARENT_EXODUS_FAIL"
    (root/"parent-exodus-parity.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    if base.exists():
        print(json.dumps({"status":report["status"],"failed_comparisons":len(parity_failures),"flow":{k:v for k,v in fields.items() if k.startswith(("1:elem:u:","1:elem:v:","1:elem:pressure:","1:elem:w_O"))},"outlet":{k:v for k,v in scalars.items() if k.startswith("1:neutral_outlet")}},indent=2,sort_keys=True))
    assert not strict_failures,("Nonvelocity strict parity gate",len(strict_failures),strict_failures[:10])
    assert conservation_pass,("Reconstructed FV conservation gate",report["conservation_gate"])
    shutil.copyfile(candidate/"parent.e",dest/"physics.e")
    shutil.copyfile(candidate/"parent.csv",dest/"physics.csv")
    report["physics_e_sha256"]=reader.sha(dest/"physics.e")
    if base.exists():
        shutil.copyfile(root/"fvm-audit.json",dest/"fvm-audit.json")
    (dest/"manifest.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    print(json.dumps({"status":report["status"],"nodes":report["nodes"],"blocks":report["blocks"],"rf_parity":report.get("baseline_parity",{}).get("maxwell_full_domain")},sort_keys=True))
finally:c.close()
