"""Compare actual transferred Maxwell states and RF fields on exact common mesh.
Diagnostic only: does not waive the failed production parity gate.
"""
import csv,json,math,sys
from pathlib import Path
from importlib.util import spec_from_file_location,module_from_spec
spec=spec_from_file_location("reader",Path(__file__).with_name("exodus-reader.py"))
reader=module_from_spec(spec);spec.loader.exec_module(reader)
root=Path(sys.argv[1])
class Data:
    def __init__(self,path):
        self.path=path; self.ex=reader.Exodus(path);self.v=self.ex.variables()
        self.xy=[tuple(round(z,12) for z in q) for q in zip(*(self.val(k) for k in ("coordx","coordy","coordz") if k in self.v))]
        self.ids=[int(x) for x in self.val("eb_prop1")]
        self.nod=self.names("nod");self.elem=self.names("elem")
    def val(self,k):return list(self.ex.values(*self.v[k]))
    def names(self,k):
        key="name_"+k+"_var"
        if key not in self.v:return []
        raw=self.ex.values(*self.v[key]); n,w=[x[1] for x in self.v[key][2]]
        return [raw[i*w:(i+1)*w].split(b"\0",1)[0].decode().strip() for i in range(n)]
    def conn(self,b):
        key="connect"+str(self.ids.index(b)+1);n=self.v[key][2][-1][1];v=self.val(key)
        return [tuple(int(z)-1 for z in v[i:i+n]) for i in range(0,len(v),n)]
    def keys(self,b):return [tuple(sorted(self.xy[j] for j in q)) for q in self.conn(b)]
    def nmap(self,name,frame,nodes=None):
        k="vals_nod_var"+str(self.nod.index(name)+1);n=len(self.xy);v=self.val(k);v=v[frame*n:(frame+1)*n]
        return {self.xy[i]:v[i] for i in (range(n) if nodes is None else nodes)}
    def emap(self,name,b,frame):
        k=f"vals_elem_var{self.elem.index(name)+1}eb{self.ids.index(b)+1}"
        n=self.v[k][2][-1][1];v=self.val(k)[frame*n:(frame+1)*n]
        return dict(zip(self.keys(b),v))
    def plasma_nodes(self):return set(j for q in self.conn(10) for j in q)
    def boundary_nodes(self):
        plasma=self.plasma_nodes()
        other=set(j for b in self.ids if b!=10 and b not in (30,31,32) for q in self.conn(b) for j in q)
        return {self.xy[j] for j in plasma&other}
    def close(self):self.ex.close()
def compare(a,b,interface=()):
    assert a.keys()==b.keys() and a
    assert all(math.isfinite(a[k]) and math.isfinite(b[k]) for k in a)
    ds={k:abs(b[k]-a[k]) for k in a}
    scale=max(abs(x) for x in a.values())
    norm=math.sqrt(sum(x*x for x in a.values()))
    changed=[k for k in a if ds[k]>1e-12+1e-9*abs(a[k])]
    biggest=sorted(a,key=ds.get,reverse=True)[:12]
    return {"count":len(a),"max_abs_delta":max(ds.values()),"relative_l2":math.sqrt(sum(x*x for x in ds.values()))/norm if norm else None,"baseline_min_max":[min(a.values()),max(a.values())],"candidate_min_max":[min(b.values()),max(b.values())],"changed_at_local_1e-9":len(changed),"changed_interface_nodes":sum(k in interface for k in changed),"top_deltas":[{"geometry":k,"baseline":a[k],"candidate":b[k],"delta":b[k]-a[k]} for k in biggest]}
def child(folder):
    x=list(folder.glob("parent*maxwell_t6*.e"));assert len(x)==1,x
    return Data(x[0])
ap=root/"baseline/fields";bp=root/"candidate_rf_capture/fields"
a,b=Data(ap/"parent.e"),Data(bp/"parent.e")
c,d=child(ap),child(bp)
try:
    assert set(c.xy)==set(d.xy) and set(c.ids)==set(d.ids)
    assert all(set(c.keys(i))==set(d.keys(i)) for i in c.ids)
    assert c.val("time_whole")==d.val("time_whole")
    assert a.val("time_whole")==b.val("time_whole")
    interface=c.boundary_nodes()
    assert set(a.keys(10))==set(b.keys(10))==set(c.keys(10))==set(d.keys(10))
    assert {a.xy[j] for j in a.plasma_nodes()}=={b.xy[j] for j in b.plasma_nodes()}=={c.xy[j] for j in c.plasma_nodes()}=={d.xy[j] for j in d.plasma_nodes()}
    report={"status":"DIAGNOSTIC_CAPTURE_COMPLETE_NOT_PARITY_ACCEPTANCE","scope":"1 ns same executable, original production parity remains failed until independently resolved","child_state":{},"parent_frozen_state":{},"child_rf":{},"child_to_parent_rf":{},"parent_to_child_direct":{}}
    for frame in (0,1):
        for name in ("electron_density_state_t6","mean_energy_state_t6"):
            report["child_state"][f"{frame}:{name}"]=compare(c.nmap(name,frame,c.plasma_nodes()),d.nmap(name,frame,d.plasma_nodes()),interface)
        report["child_state"][f"{frame}:pressure_state_t6"]=compare(c.emap("pressure_state_t6",10,frame),d.emap("pressure_state_t6",10,frame))
        for name in ("electron_density_rf_state_t6","mean_energy_rf_state_t6"):
            report["parent_frozen_state"][f"{frame}:{name}"]=compare(a.nmap(name,frame,a.plasma_nodes()),b.nmap(name,frame,b.plasma_nodes()),interface)
        report["parent_frozen_state"][f"{frame}:pressure_rf_state_t6"]=compare(a.emap("pressure_rf_state_t6",10,frame),b.emap("pressure_rf_state_t6",10,frame))
        for src,dst in (("electron_density_rf_state_t6","electron_density_state_t6"),("mean_energy_rf_state_t6","mean_energy_state_t6")):
            report["parent_to_child_direct"][f"{frame}:{dst}"]=compare(b.nmap(src,frame,b.plasma_nodes()),d.nmap(dst,frame,d.plasma_nodes()),interface)
        report["parent_to_child_direct"][f"{frame}:pressure_state_t6"]=compare(b.emap("pressure_rf_state_t6",10,frame),d.emap("pressure_state_t6",10,frame))
    for name in ("E_real","E_imag"):
        report["child_rf"][name]=compare(c.nmap(name,1),d.nmap(name,1),interface)
        report["child_to_parent_rf"][name]=compare(d.nmap(name,1),b.nmap(name+"_full",1),interface)
    with (ap/"parent.csv").open() as f:x=list(csv.DictReader(f))[-1]
    with (bp/"parent.csv").open() as f:y=list(csv.DictReader(f))[-1]
    report["csv"]={k:{"baseline":float(x[k]),"candidate":float(y[k]),"delta":float(y[k])-float(x[k])} for k in x if k.startswith(("P_abs","P_rf","neutral_outlet","neutral_u","neutral_v"))}
    (root/"parent-exodus-diagnostic.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    print(json.dumps({section:{k:{q:v[q] for q in ("max_abs_delta","relative_l2","changed_at_local_1e-9","changed_interface_nodes")} for k,v in report[section].items()} for section in ("child_state","parent_frozen_state","child_rf","child_to_parent_rf")},indent=2))
    # Exact copies must match the actual source and baseline values on every plasma DOF.
    for section in ("child_state","parent_to_child_direct"):
        for name,v in report[section].items():
            assert v["max_abs_delta"]==0,(section,name,v)
    for section in ("child_rf","child_to_parent_rf"):
        for name,v in report[section].items():
            scale=max(abs(x) for x in v["baseline_min_max"])
            assert v["max_abs_delta"]<=1e-12+1e-9*scale,(section,name,v)
    print("RF_COINCIDENT_TRANSFER_AND_FIELD_PARITY_PASS")
finally:
    for obj in (a,b,c,d):obj.close()
