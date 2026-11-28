"""Qualify the canonical 400 W native Parent trajectory, not scientific accuracy."""
import csv
import json
import math
import re
import sys
from pathlib import Path
from importlib.util import spec_from_file_location, module_from_spec

def load(name, file):
    spec=spec_from_file_location(name,Path(__file__).with_name(file))
    module=module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

flat=load("flat","verify-flat.py")
reader=load("reader","exodus-reader.py")
root,input_path=map(Path,sys.argv[1:])
target=1e-4
rtol=1e-8
def require(ok, message):
    if not ok:
        raise RuntimeError(message)
def rows(path):
    with path.open(newline="") as f:
        return [{k:float(v) for k,v in row.items()} for row in csv.DictReader(f)]
def close(a,b):
    return math.isclose(a,b,rel_tol=1e-10,abs_tol=1e-16)
def check_time(ts):
    require(len(ts)>=2 and all(map(math.isfinite,ts)), "Invalid time history")
    require(close(ts[0],0) and close(ts[-1],target), "Incomplete time history")
    require(all(a<b for a,b in zip(ts,ts[1:])), "Nonmonotonic accepted times")
def names(ex,v,k):
    raw=ex.values(*v[k])
    n,w=[x[1] for x in v[k][2]]
    return [raw[i*w:(i+1)*w].split(b"\0",1)[0].decode().strip() for i in range(n)]
report={"status":"PENDING","science":"SCIENCE_HOLD","target_s":target,
        "power_target_W":400,"budget_numerical_rtol":rtol,
        "scope":"single canonical candidate trajectory; not matched long A/B or time/mesh convergence"}
def save():
    (root/"manifest.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
try:
    inp=input_path.read_text()
    require(re.search(r"(?m)^\s*target = 400\s*$",inp) is not None,"400 W target missing")
    sequence=[float(t) for t in re.search(r"time_sequence = '([^']+)'",inp).group(1).split()]
    check_time(sequence)
    log=re.sub(r"\x1b\[[0-9;]*m","",(root/"transient.log").read_text())
    require("Finished Executing" in log and "JIT compile failed" not in log,"Native solve incomplete")
    converged=len(re.findall(r"(?m)^ *Solve Converged! *$",log))
    fields=root/"fields"
    require(list(fields.glob("*.e"))==[fields/"physics.e"],"Expected exactly one native Exodus")
    r=rows(fields/"physics.csv")
    ts=[x["time"] for x in r]
    check_time(ts)
    require(all(any(close(t,q) for q in ts) for t in sequence),"Missing canonical scheduled frame")
    require(converged>=len(ts)-1,"Missing accepted parent convergence markers")
    require(all(math.isfinite(q) for x in r for q in x.values()),"Nonfinite CSV")
    for row in r:
        for n in ("ne","ni","nop","nm"):
            require(0<row[n+"_min"]<=row[n+"_max"],"Invalid density extrema "+n)
    report.update(accepted_steps=len(ts)-1,scheduled_steps=len(sequence)-1,
                  parent_convergence_markers=converged,density_extrema=flat.endpoint(fields/"physics.csv",target),
                  spatial_log_field_counts=flat.exodus(fields/"physics.e",target))
    power_keys=("P_abs_maxwell_t6","P_rf_raw_W_t6","rf_drive_scale_t6")
    report["rf_history"]={k:{"min":min(x[k] for x in r[1:]),"max":max(x[k] for x in r[1:]),"final":r[-1][k]} for k in power_keys}
    require(all(x[k]>=0 for x in r[1:] for k in power_keys),"Negative RF scalar")
    ex=reader.Exodus(fields/"physics.e")
    try:
        v=ex.variables()
        val=lambda k:list(ex.values(*v[k]))
        xt=val("time_whole")
        require(len(xt)==len(ts) and all(close(a,b) for a,b in zip(xt,ts)),"CSV/Exodus time mismatch")
        ids=[int(x) for x in val("eb_prop1")]
        require(set(ids)=={10,20,21,22,23,24,25,26,30,31,32,73,87,91,92,93,94},"Wrong block IDs")
        require(len(val("coordx"))==2085,"Wrong node count")
        count=sum(v[f"connect{i+1}"][2][0][1] for i,b in enumerate(ids) if b not in (30,31,32))
        require(count==4016,"Wrong volume element count")
        nod=names(ex,v,"name_nod_var")
        elem=names(ex,v,"name_elem_var")
        for name in ("E_real_full","E_imag_full"):
            a=val("vals_nod_var"+str(nod.index(name)+1))
            require(len(a)==len(ts)*2085 and all(math.isfinite(x) and abs(x)<1e30 for x in a),"Bad RF history "+name)
            require(any(x!=0 for x in a[-2085:]),"Zero endpoint RF "+name)
        for name in ("rf_absorbed_power_density","u","v","pressure","w_O2s","w_O","w_Os"):
            a=val(f"vals_elem_var{elem.index(name)+1}eb{ids.index(10)+1}")
            require(len(a)==len(ts)*1798 and all(math.isfinite(x) and abs(x)<1e30 for x in a),"Invalid plasma field "+name)
            if name=="pressure":require(min(a)>0,"Nonpositive pressure")
            if name=="rf_absorbed_power_density":require(min(a)>=0 and max(a[-1798:])>0,"Invalid RF heating")
        report["mesh"]={"nodes":2085,"volume_elements":count,"blocks":ids}
    finally:ex.close()
    audit=rows(root/"fvm-audit.csv")
    require(len(audit)==len(r)-1 and all(close(x["time"],y["time"]) for x,y in zip(audit,r[1:])),"Audit history mismatch")
    maxima={}
    failing=[]
    for x,y in zip(audit,r[1:]):
        require(all(math.isfinite(q) for q in x.values()),"Nonfinite audit")
        inflow=y["neutral_inlet_mdot"]
        require(inflow>0,"Invalid inlet")
        src=math.fsum(x["audit_source_"+n] for n in ("EI415","EI401","EI417","H25"))
        mass=abs(math.fsum((x["audit_mass_time"],-inflow,x["audit_flux_outlet_mass"],x["audit_flux_wall_mass"],-src)))/inflow
        checks={"mass_balance":mass,"wall_net_mass":abs(x["audit_flux_wall_mass"])/inflow,
                "outlet_reporting":abs(x["audit_flux_outlet_mass"]-y["neutral_outlet_mass"])/inflow}
        for var,axis in (("u","x"),("v","y")):
            terms=("time","pressure","viscous","inlet","rz") if var=="u" else ("time","pressure","viscous","inlet")
            signed=[x[f"audit_budget_{var}_{n}"] for n in terms]
            absolute=[x[f"audit_budget_{var}_{n}_abs"] for n in terms]
            for group in ("wall","outlet"):
                z=x[f"audit_flux_{group}_momentum_{axis}"]
                signed.append(z);absolute.append(abs(z))
            require(all(q>=0 for q in absolute) and math.fsum(absolute)>0,"Invalid momentum normalization")
            scale=math.fsum(absolute)
            checks[var+"_momentum_balance"]=abs(math.fsum(signed))/scale
            checks[var+"_rhs_l1"]=x[f"audit_{var}_l_1"]/scale
        for key,q in checks.items():
            if key not in maxima or q>maxima[key]["value"]:maxima[key]={"value":q,"time_s":y["time"]}
            if q>rtol:failing.append({"gate":key,"value":q,"time_s":y["time"]})
    report["max_normalized_budget_errors"]=maxima
    report["budget_failure_count"]=len(failing)
    report["first_budget_failures"]=failing[:30]
    report["physics_e_sha256"]=reader.sha(fields/"physics.e")
    report["physics_csv_sha256"]=reader.sha(fields/"physics.csv")
    require(not failing,"Trajectory numerical conservation gate failed")
    report["status"]="TRANSIENT_400W_100US_PASS"
except Exception as exc:
    report.update(status="TRANSIENT_400W_100US_FAIL",error=str(exc))
    raise
finally:
    save()
    print(json.dumps(report,indent=2,sort_keys=True))
