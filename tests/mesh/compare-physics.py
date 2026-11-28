"""Quantify changes on unchanged Parent mesh; never claim scientific equivalence."""
import csv, importlib.util, json, math, sys
from pathlib import Path
spec=importlib.util.spec_from_file_location("exodus_reader","/scripts/rdc-p7-compare.py")
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
root=Path(sys.argv[1]); a=root/"baseline"; b=root/"conformal"
def rows(p):
    with p.open() as f: return list(csv.DictReader(f))
x,y=rows(a/"fields/parent.csv"),rows(b/"fields/parent.csv")
assert len(x)==len(y) and x[-1].keys()==y[-1].keys()
assert [r["time"] for r in x]==[r["time"] for r in y]
scalar={}
for k in x[-1]:
    u,v=float(x[-1][k]),float(y[-1][k])
    assert math.isfinite(u) and math.isfinite(v), k
    scalar[k]={"baseline":u,"conformal":v,"absolute_delta":v-u,"relative_delta":(v-u)/abs(u) if u else None}
e,f=m.Exodus(a/"fields/parent.e"),m.Exodus(b/"fields/parent.e")
try:
    va,vb=e.variables(),f.variables()
    fields={}
    assert set(va)==set(vb)
    for k in va:
        i,t,d=va[k]; j,s,h=vb[k]
        assert (t,d)==(s,h),k
        if k.startswith(("coord","connect","node_num_map","elem_num_map","time_whole","name_nod_var","name_elem_var","eb_prop","ns_prop","ss_prop","node_ns","elem_ss","side_ss")):
            assert list(e.values(i,t,d))==list(f.values(j,s,h)),k
    def names(k):
        i,t,d=va[k]; raw=e.values(i,t,d); n,w=[v for _,v in d]
        return [raw[z*w:(z+1)*w].split(b"\0",1)[0].decode().strip() for z in range(n)]
    for kind,namekey in (("nod","name_nod_var"),("elem","name_elem_var")):
        for n,label in enumerate(names(namekey),1):
            prefix=f"vals_{kind}_var{n}"
            u=[];v=[]
            for k in va:
                if k!=prefix and not k.startswith(prefix+"eb"): continue
                i,t,d=va[k];j,s,h=vb[k]
                aa=e.values(i,t,d);bb=f.values(j,s,h)
                count=d[-1][1]
                for l,r in zip(aa[-count:],bb[-count:]):
                    assert math.isfinite(l) and math.isfinite(r),label
                    if abs(l)>=1e30 or abs(r)>=1e30:
                        assert l==r,label
                        continue
                    u.append(l);v.append(r)
            if not u: continue
            dif=[r-l for l,r in zip(u,v)]; norm=math.sqrt(sum(l*l for l in u))
            fields[label]={"count":len(u),"max_abs_delta":max(map(abs,dif)),"relative_l2":math.sqrt(sum(z*z for z in dif))/norm if norm else None}
    assert {"E_real_rf_t6","E_imag_rf_t6","log_e","log_O2p","log_Op","log_Om"}<=fields.keys()
finally: e.close();f.close()
report={"status":"BOUNDED_MESH_COMPARISON_COMPLETE","science":"SCIENCE_HOLD","acceptance":"Numerical differences measured; no equivalence threshold approved.","parent_topology_exact":True,"endpoint_s":float(x[-1]["time"]),"scalars":scalar,"fields":fields}
(root/"mesh-physics-comparison.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
print(json.dumps({"status":report["status"],"rf":{k:v for k,v in scalar.items() if "rf_" in k or "P_abs" in k},"fields":{k:fields[k] for k in ("E_real_rf_t6","E_imag_rf_t6","log_e","log_O2p","log_Op","log_Om")}},indent=2))
