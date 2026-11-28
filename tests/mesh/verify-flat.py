#!/usr/bin/env python3
"""Verify accepted parent endpoint, scalar densities and Exodus field payload."""
import csv
import ctypes as C
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024*1024), b""):
            h.update(block)
    return h.hexdigest()

def endpoint(path, target):
    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    require(len(rows) >= 2, "Parent CSV lacks initial and accepted output")
    times = [float(row["time"]) for row in rows]
    require(all(math.isfinite(t) for t in times), "Nonfinite CSV time")
    require(all(a <= b for a, b in zip(times,times[1:])), "Nonmonotonic CSV times")
    require(math.isclose(times[-1],target,rel_tol=1e-10,abs_tol=1e-16), "Wrong CSV endpoint")
    vals = {}
    for name in ("ne","ni","nop","nm"):
        low,high = (float(rows[-1][name+"_"+k]) for k in ("min","max"))
        require(math.isfinite(low) and math.isfinite(high) and 0 < low <= high, "Bad density: "+name)
        vals[name] = {"min":low,"max":high}
    return vals

def exodus(path,target):
    nc = C.CDLL("/opt/libmesh/lib/libnetcdf.so.13")
    def call(name,*args):
        rc = getattr(nc,name)(*args)
        require(rc == 0, f"{name}: netCDF status {rc}")
    fid = C.c_int()
    call("nc_open",os.fsencode(path),0,C.byref(fid))
    try:
        def varid(name,optional=False):
            v = C.c_int()
            rc = nc.nc_inq_varid(fid,name.encode(),C.byref(v))
            if optional and rc != 0:
                return None
            require(rc == 0, "Missing Exodus variable "+name)
            return v
        def shape(v):
            rank = C.c_int()
            call("nc_inq_varndims",fid,v,C.byref(rank))
            dims = (C.c_int * rank.value)()
            call("nc_inq_vardimid",fid,v,dims)
            result = []
            for d in dims:
                n=C.c_size_t()
                call("nc_inq_dimlen",fid,d,C.byref(n))
                result.append(n.value)
            return result
        def names(var):
            v=varid(var,True)
            if v is None:
                return []
            n,w=shape(v)
            raw=C.create_string_buffer(n*w)
            call("nc_get_var_text",fid,v,raw)
            return [raw.raw[i*w:(i+1)*w].split(b"\0",1)[0].decode().strip() for i in range(n)]
        t=varid("time_whole")
        nt,=shape(t)
        require(nt>=2,"Exodus lacks initial and accepted time")
        tv=(C.c_double*nt)()
        call("nc_get_var_double",fid,t,tv)
        require(all(math.isfinite(x) for x in tv) and math.isclose(tv[-1],target,rel_tol=1e-10,abs_tol=1e-16),"Wrong Exodus endpoint")
        nv=C.c_int()
        call("nc_inq_nvars",fid,C.byref(nv))
        variables=[]
        for i in range(nv.value):
            b=C.create_string_buffer(257)
            call("nc_inq_varname",fid,i,b)
            variables.append(b.value.decode())
        fields={}
        for kind,namevar in (("nod","name_nod_var"),("elem","name_elem_var")):
            for i,name in enumerate(names(namevar),1):
                if name not in ("log_e","log_O2p","log_Op","log_Om"):
                    continue
                prefix=f"vals_{kind}_var{i}"
                keys=[k for k in variables if k==prefix or (kind=="elem" and re.fullmatch(prefix+r"eb\d+",k))]
                count=0
                for key in keys:
                    v=varid(key)
                    dims=shape(v)
                    require(len(dims)==2 and dims[0]==nt,"Unexpected field dimensions: "+key)
                    n=dims[1]
                    if not n:
                        continue
                    require(n<10_000_000,"Unexpected field size")
                    start=(C.c_size_t*2)(nt-1,0)
                    size=(C.c_size_t*2)(1,n)
                    data=(C.c_double*n)()
                    call("nc_get_vara_double",fid,v,start,size,data)
                    # Exodus may use the standard fill sentinel on inactive blocks.
                    real=[x for x in data if abs(x)<1e30]
                    require(all(math.isfinite(x) for x in data),"Nonfinite field: "+key)
                    require(all(abs(x)<1e30 or math.isclose(abs(x),9.969209968386869e36,rel_tol=1e-6) for x in data),"Invalid field: "+key)
                    count+=len(real)
                if count:
                    fields[name]=fields.get(name,0)+count
        require(set(fields)=={"log_e","log_O2p","log_Op","log_Om"},"Missing spatial species field(s): "+str(fields))
        return fields
    finally:
        call("nc_close",fid)

def main():
    evidence=Path(sys.argv[1])
    target=1e-9
    log=re.sub(r"\x1b\[[0-9;]*m","",(evidence/"newonly-one-step.log").read_text())
    require(re.search(r"(?m)^ *Solve Converged! *$",log),"No unprefixed parent convergence")
    require("Finished Executing" in log and "JIT compile failed" not in log,"Execution/JIT gate")
    steps=re.findall(r"(?m)^Time Step \d+, time = ([\deE.+-]+)",log)
    require(steps and math.isclose(float(steps[-1]),target,rel_tol=1e-10,abs_tol=1e-16),"Parent log endpoint")
    fields=evidence/"fields"
    result={"status":"BOUNDED_PARENT_OUTPUT_PASS","science":"SCIENCE_HOLD","endpoint_s":target,
        "density_extrema":endpoint(fields/"parent.csv",target),
        "spatial_log_field_counts":exodus(fields/"parent.e",target)}
    (evidence/"newonly-output-manifest.json").write_text(json.dumps(result,indent=2,sort_keys=True)+"\n")
    print(json.dumps(result,sort_keys=True))
if __name__=="__main__": main()
