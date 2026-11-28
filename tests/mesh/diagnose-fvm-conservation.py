"""Report spatial FV differences, integrated mass terms and native residual norms.
A balance reconstruction and nonlinear residual norms are diagnostic evidence;
neither proves independent momentum conservation or mesh convergence.
"""
import csv,json,math,sys
from pathlib import Path
from importlib.util import spec_from_file_location,module_from_spec
from collections import Counter
spec=spec_from_file_location("reader",Path(__file__).with_name("exodus-reader.py"))
reader=module_from_spec(spec);spec.loader.exec_module(reader)
root=Path(sys.argv[1])
def rows(path):
    with path.open() as f:return [{k:float(v) for k,v in r.items()} for r in csv.DictReader(f)]
def data(path):
    ex=reader.Exodus(path)
    try:
        v=ex.variables()
        def val(k):return list(ex.values(*v[k]))
        def names(k):
            raw=ex.values(*v[k]);n,w=[x[1] for x in v[k][2]]
            return [raw[i*w:(i+1)*w].split(b"\0",1)[0].decode().strip() for i in range(n)]
        coords=[tuple(round(z,12) for z in p) for p in zip(val("coordx"),val("coordy"))]
        b=val("eb_prop1").index(10)+1
        conn=val(f"connect{b}");width=v[f"connect{b}"][2][-1][1]
        assert width==3
        keys=[tuple(sorted(coords[int(j)-1] for j in conn[i:i+3])) for i in range(0,len(conn),3)]
        assert len(set(keys))==len(keys)==1798
        ns=names("name_elem_var")
        fields={}
        for name in ("u","v","pressure","w_O2s","w_O","w_Os"):
            values=val(f"vals_elem_var{ns.index(name)+1}eb{b}")[-len(keys):]
            fields[name]=dict(zip(keys,values))
        return fields
    finally:ex.close()
def metrics(a,b,keys):
    d=[b[k]-a[k] for k in keys];scale=math.sqrt(math.fsum(a[k]**2 for k in keys))
    return {"cells":len(keys),"max_abs":max(map(abs,d)),"relative_l2":math.sqrt(math.fsum(x*x for x in d))/scale if scale else None}
a,b=[data(root/k/"fields/parent.e") for k in ("baseline","candidate")]
keys=list(a["u"])
assert set(keys)==set(b["u"])
edges=Counter(tuple(sorted((t[i],t[(i+1)%3]))) for t in keys for i in range(3))
boundary=[t for t in keys if any(edges[tuple(sorted((t[i],t[(i+1)%3])))]==1 for i in range(3))]
interior=[t for t in keys if t not in set(boundary)]
report={"status":"FVM_DIAGNOSTIC_ONLY","spatial":{},"mass_budget":{},"residual_norms":{},"scope":"same mesh; 1 ns endpoint; native RHS norms (last assembled residual), not independent momentum budget or mesh convergence"}
for n in a:
    report["spatial"][n]={"all":metrics(a[n],b[n],keys),"boundary_cells":metrics(a[n],b[n],boundary),"interior_cells":metrics(a[n],b[n],interior)}
for kind in ("baseline","candidate","candidate_rf_capture"):
    r=rows(root/kind/"fields/parent.csv")
    audit=rows(root/kind/"fvm-audit.csv")
    assert audit and math.isclose(audit[-1]["time"],r[-1]["time"],abs_tol=1e-16)
    x=audit[-1];end=r[-1];dt=end["time"]-r[0]["time"]
    src=math.fsum(x["audit_source_"+n] for n in ("EI415","EI401","EI417","H25"))
    inflow=end["neutral_inlet_mdot"];outflow=end["neutral_outlet_mass"]
    accum=x["audit_mass_time"];delta=(end["neutral_mass_total"]-r[0]["neutral_mass_total"])/dt
    balance=accum-inflow+outflow-src
    assert all(math.isfinite(q) for q in (src,inflow,outflow,accum,delta,balance)) and inflow>0
    report["mass_budget"][kind]={"integrated_density_time_term_kg_s":accum,"mass_change_over_dt_kg_s":delta,"inlet_kg_s":inflow,"outlet_kg_s":outflow,"source_kg_s":src,"reconstructed_balance_kg_s":balance,"normalized_to_inlet":abs(balance)/inflow,"note":"cell-average time and source terms; inlet imposed mdot; outlet reporting flux; other boundaries assumed impermeable"}
    norms={n:{p:x[f"audit_{n}_{p}"] for p in ("l_1","l_2","l_inf")} for n in ("pressure","u","v")}
    assert all(math.isfinite(q) and q>=0 for v in norms.values() for q in v.values())
    report["residual_norms"][kind]=norms
(root/"fvm-audit.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
print(json.dumps(report,indent=2,sort_keys=True))
print("FVM_PHYSICAL_DIAGNOSTIC_CAPTURE_COMPLETE")
