"""Quantify changes on unchanged Parent mesh; never claim scientific equivalence."""
import csv, importlib.util, json, math, sys
from pathlib import Path
spec=importlib.util.spec_from_file_location("exodus_reader",str(Path(__file__).with_name("exodus-reader.py")))
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
    def vals(obj,vs,k):
        return list(obj.values(*vs[k]))
    def names(obj,vs,k):
        i,t,d=vs[k]; raw=obj.values(i,t,d); n,w=[v for _,v in d]
        return [raw[z*w:(z+1)*w].split(b"\0",1)[0].decode().strip() for z in range(n)]
    def coordinates(obj,vs):
        keys=[k for k in ("coordx","coordy","coordz") if k in vs]
        assert len(keys)>=2
        return [tuple(round(z,12) for z in q) for q in zip(*(vals(obj,vs,k) for k in keys))]
    ac,bc=coordinates(e,va),coordinates(f,vb)
    def order(a,b):
        assert len(a)==len(b) and len(set(a))==len(a) and set(a)==set(b)
        lookup={k:i for i,k in enumerate(b)}
        return [lookup[k] for k in a]
    node_order=order(ac,bc)
    assert vals(e,va,"time_whole")==vals(f,vb,"time_whole")
    assert names(e,va,"name_nod_var")==names(f,vb,"name_nod_var")
    assert names(e,va,"name_elem_var")==names(f,vb,"name_elem_var")
    a_ids=vals(e,va,"eb_prop1"); b_ids=vals(f,vb,"eb_prop1")
    block_order=order(a_ids,b_ids)
    elem_order={}
    for n,j in enumerate(block_order,1):
        akey=f"connect{n}"; bkey=f"connect{j+1}"
        def keys(obj,vs,k,coords):
            width=vs[k][2][-1][1]; flat=vals(obj,vs,k)
            return [tuple(sorted(coords[int(q)-1] for q in flat[i:i+width])) for i in range(0,len(flat),width)]
        elem_order[n]=order(keys(e,va,akey,ac),keys(f,vb,bkey,bc))
    def compare_pairs(kind,prefix,k):
        i,t,d=va[k]; aa=e.values(i,t,d); count=d[-1][1]
        if kind=="nod": other=k; permutation=node_order
        else:
            block=int(k.split("eb")[-1]); other=prefix+"eb"+str(block_order[block-1]+1); permutation=elem_order[block]
        j,s,h=vb[other]; bb=f.values(j,s,h)
        assert t==s and count==h[-1][1]==len(permutation),k
        return zip(aa[-count:],[bb[-count:][n] for n in permutation])
    for kind,namekey in (("nod","name_nod_var"),("elem","name_elem_var")):
        for n,label in enumerate(names(e,va,namekey),1):
            prefix=f"vals_{kind}_var{n}"
            u=[];v=[]
            for k in va:
                if k!=prefix and not k.startswith(prefix+"eb"): continue
                for l,r in compare_pairs(kind,prefix,k):
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
report={"status":"BOUNDED_MESH_COMPARISON_COMPLETE","science":"SCIENCE_HOLD","acceptance":"Numerical differences measured; no equivalence threshold approved.","parent_topology_by_coordinates_and_block":True,"endpoint_s":float(x[-1]["time"]),"scalars":scalar,"fields":fields}
(root/"mesh-physics-comparison.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
print(json.dumps({"status":report["status"],"rf":{k:v for k,v in scalar.items() if "rf_" in k or "P_abs" in k},"fields":{k:fields[k] for k in ("E_real_rf_t6","E_imag_rf_t6","log_e","log_O2p","log_Op","log_Om")}},indent=2))
