"""Report spatial FV differences, integrated mass terms and native residual norms.
A balance reconstruction and nonlinear residual norms are diagnostic evidence;
neither proves independent momentum conservation or mesh convergence.
"""
import csv,json,math,sys
from pathlib import Path
from importlib.util import spec_from_file_location,module_from_spec
from collections import Counter,defaultdict,deque
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
        # Reconstruct conformal volume adjacency from Exodus, independently of
        # the native FaceInfo owner/cache. Ignore lower-dimensional surface blocks.
        owners=defaultdict(list)
        for bi,block in enumerate(val("eb_prop1"),1):
            k=f"connect{bi}"
            if v[k][2][-1][1]!=3:
                continue
            con=val(k)
            for i in range(0,len(con),3):
                tri=tuple(sorted(coords[int(j)-1] for j in con[i:i+3]))
                for j in range(3):
                    edge=tuple(sorted((tri[j],tri[(j+1)%3])))
                    owners[edge].append((int(block),tri))
        return fields,owners
    finally:ex.close()
def metrics(a,b,keys):
    d=[b[k]-a[k] for k in keys];scale=math.sqrt(math.fsum(a[k]**2 for k in keys))
    return {"cells":len(keys),"max_abs":max(map(abs,d)),"relative_l2":math.sqrt(math.fsum(x*x for x in d))/scale if scale else None}
(a,old_owners),(b,new_owners),(capture,capture_owners)=[
    data(root/k/"fields/parent.e") for k in ("baseline","candidate","candidate_rf_capture")]
keys=list(a["u"])
assert set(keys)==set(b["u"])==set(capture["u"])
assert new_owners==capture_owners or all(
    sorted(new_owners[e])==sorted(capture_owners[e])
    for e in set(new_owners)|set(capture_owners))
# Compare topology at each plasma face, including exterior-to-interface
# transitions. Coordinate keys use the same precision as the parity reader.
def active(owners,edge):
    return [tri for block,tri in owners[edge] if block==10]
def kind(owners,edge):
    entries=owners[edge]
    assert 1<=len(entries)<=2,(edge,entries)
    n=len(active(owners,edge))
    assert n in (1,2)
    if n==2:return "plasma_interior"
    other=[block for block,_ in entries if block!=10]
    return "block_"+str(other[0]) if other else "exterior"
plasma_edges={edge for edge,entries in old_owners.items() if any(block==10 for block,_ in entries)}
assert plasma_edges=={edge for edge,entries in new_owners.items() if any(block==10 for block,_ in entries)}
transitions=defaultdict(list)
neighbors=defaultdict(set)
cut_cells=set()
for edge in plasma_edges:
    before,after=kind(old_owners,edge),kind(new_owners,edge)
    old_cells=active(old_owners,edge)
    assert set(old_cells)==set(active(new_owners,edge)),edge
    assert (before=="plasma_interior")== (after=="plasma_interior"),edge
    if len(old_cells)==2:
        x,y=old_cells
        neighbors[x].add(y);neighbors[y].add(x)
    else:
        transitions[(before,after)].append(edge)
        if before!=after:cut_cells.add(old_cells[0])
assert cut_cells,"Expected exterior-to-interface transitions"
distance={t:0 for t in cut_cells};queue=deque(cut_cells)
while queue:
    t=queue.popleft()
    for neighbor in neighbors[t]:
        if neighbor not in distance:
            distance[neighbor]=distance[t]+1;queue.append(neighbor)
assert set(distance)==set(keys),"Disconnected plasma cell graph"
def rz_area(edge):
    (r1,z1),(r2,z2)=edge
    # Surface of revolution of a straight edge about the Y axis.
    assert min(r1,r2)>=-1e-12,edge
    return math.pi*(r1+r2)*math.hypot(r2-r1,z2-z1)
topology={"plasma_faces":len(plasma_edges),
          "plasma_internal_faces":sum(kind(old_owners,e)=="plasma_interior" for e in plasma_edges),
          "transitions":{f"{x}->{y}":{"faces":len(es),"rz_area_m2":math.fsum(map(rz_area,es))}
                         for (x,y),es in sorted(transitions.items())},
          "cut_adjacent_cells":len(cut_cells),
          "scope":"Exodus geometry only, not native FaceInfo ownership or flux orientation"}
rings={"cut_adjacent":[t for t in keys if distance[t]==0],
       "one_to_two_layers":[t for t in keys if 1<=distance[t]<=2],
       "three_or_more_layers":[t for t in keys if distance[t]>=3]}
edges=Counter(tuple(sorted((t[i],t[(i+1)%3]))) for t in keys for i in range(3))
boundary=[t for t in keys if any(edges[tuple(sorted((t[i],t[(i+1)%3])))]==1 for i in range(3))]
interior=[t for t in keys if t not in set(boundary)]
report={"status":"FVM_DIAGNOSTIC_ONLY","spatial":{},"mass_budget":{},"residual_norms":{},"scope":"same mesh; 1 ns endpoint; accepted-state reconstructed domain momentum terms, native last-assembled RHS norms; not independent discretization or mesh convergence"}
report["face_topology"]=topology
report["cut_distance"]={n:{k:metrics(a[n],b[n],ts) for k,ts in rings.items() if ts} for n in ("u","v","pressure")}
report["capture_control"]={n:metrics(b[n],capture[n],keys) for n in b}
report["boundary_transport"]={}
report["momentum_budget"]={}
BUDGET_RTOL=1e-8
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
    # Native Rhie-Chow reporting flux, outward from the flow domain.
    # These are advective transport terms only; they omit pressure/viscous
    # traction and the RZ momentum source, so are NOT a momentum balance.
    fluxes={group:{quantity:x[f"audit_flux_{group}_{quantity}"]
                   for quantity in ("mass","momentum_x","momentum_y")}
            for group in ("outlet","wall")}
    assert all(math.isfinite(q) for f in fluxes.values() for q in f.values())
    report["boundary_transport"][kind]={
        "outward_flux":fluxes,
        "outlet_mass_reporting_delta_kg_s":fluxes["outlet"]["mass"]-outflow,
        "wall_mass_normalized_to_inlet":abs(fluxes["wall"]["mass"])/inflow,
        "scope":"native reporting face flux; inlet BC imposed separately; advective momentum only, no pressure/viscous/RZ closure"}
    # Measured net wall flux is included, not assumed zero.
    balance=math.fsum((accum,-inflow,fluxes["outlet"]["mass"],fluxes["wall"]["mass"],-src))
    report["mass_budget"][kind].update(
        reconstructed_balance_kg_s=balance,normalized_to_inlet=abs(balance)/inflow,
        note="cell-average time/source terms; imposed inlet; native outlet and wall net reporting flux")
    momentum={}
    for var,axis in (("u","x"),("v","y")):
        names=("pressure","viscous","inlet","rz") if var=="u" else ("pressure","viscous","inlet")
        terms={n:x[f"audit_budget_{var}_{n}"] for n in names}
        absolute={n:x[f"audit_budget_{var}_{n}_abs"] for n in names}
        for group in ("outlet","wall"):
            terms[group+"_advection"]=fluxes[group]["momentum_"+axis]
            absolute[group+"_advection"]=abs(terms[group+"_advection"])
        assert all(math.isfinite(q) for q in terms.values())
        assert all(math.isfinite(q) and q>=0 for q in absolute.values())
        assert all(abs(terms[n])<=absolute[n]+1e-13*max(absolute[n],1e-300) for n in terms)
        scale=math.fsum(absolute.values())
        assert scale>0 and absolute["pressure"]>0 and absolute["viscous"]>0,(kind,var,absolute)
        if var=="u":assert absolute["inlet"]>0 and absolute["rz"]>0,(kind,var,absolute)
        else:assert terms["inlet"]==0,(kind,var,terms)
        imbalance=math.fsum(terms.values())
        rel=abs(imbalance)/scale
        rhs_rel=norms[var]["l_1"]/scale
        momentum[var]={"signed_terms_N":terms,"absolute_contribution_scale_N":scale,
                       "abs_terms_N":absolute,"balance_N":imbalance,"normalized_balance":rel,
                       "native_rhs_l1_normalized":rhs_rel,
                       "pass":rel<=BUDGET_RTOL and rhs_rel<=BUDGET_RTOL}
    report["momentum_budget"][kind]=momentum
checks={}
for kind in ("baseline","candidate","candidate_rf_capture"):
    checks[kind]={
        "mass_balance":report["mass_budget"][kind]["normalized_to_inlet"]<=BUDGET_RTOL,
        "wall_net_mass":report["boundary_transport"][kind]["wall_mass_normalized_to_inlet"]<=BUDGET_RTOL,
        "outlet_mass_reporting":abs(report["boundary_transport"][kind]["outlet_mass_reporting_delta_kg_s"])<=BUDGET_RTOL*report["mass_budget"][kind]["inlet_kg_s"],
        "radial_momentum":report["momentum_budget"][kind]["u"]["pass"],
        "axial_momentum":report["momentum_budget"][kind]["v"]["pass"]}
capture_exact=all(v["max_abs"]==0 for v in report["capture_control"].values())
report["conservation_gate"]={"relative_numerical_tolerance":BUDGET_RTOL,
    "cases":checks,"capture_exact":capture_exact,
    "pass":capture_exact and all(all(v.values()) for v in checks.values()),
    "scope":"one-step discrete numerical qualification only; SCIENCE_HOLD; no mesh/time convergence or scientific acceptance"}
(root/"fvm-audit.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
print(json.dumps(report,indent=2,sort_keys=True))
print("FVM_PHYSICAL_DIAGNOSTIC_CAPTURE_COMPLETE")
print("FVM_RECONSTRUCTED_BUDGET_PASS" if report["conservation_gate"]["pass"] else "FVM_RECONSTRUCTED_BUDGET_FAIL")
