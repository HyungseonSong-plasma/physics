"""Native A/B diagnostic: identical active triangle, optional skew passive neighbor."""
import csv,json,math,sys
from pathlib import Path
root=Path(sys.argv[2])
cases=("exterior","internal_active_first","internal_passive_first")
if sys.argv[1]=="prepare":
    for case in cases:
        d=root/case;d.mkdir(parents=True,exist_ok=True)
        nodes=["1 0 0 0","2 1 0 0","3 1 1 0"]
        elements=["1 1 2 101 101 1 2","2 1 2 101 101 3 1","3 1 2 102 102 2 3"]
        active="2 2 10 10 1 2 3"
        passive="2 2 20 20 2 4 3"
        physical=['1 101 "outer"','1 102 "interface"','2 10 "active"']
        if case=="exterior":
            elements.append("4 "+active)
        else:
            nodes.append("4 2 0.2 0")
            physical.append('2 20 "passive"')
            order=(active,passive) if case=="internal_active_first" else (passive,active)
            elements.extend(str(i+4)+" "+e for i,e in enumerate(order))
        def block(name,rows):return "$"+name+"\n"+str(len(rows))+"\n"+"\n".join(rows)+"\n$End"+name+"\n"
        (d/"case.msh").write_text("$MeshFormat\n2.2 0 8\n$EndMeshFormat\n"+block("PhysicalNames",physical)+block("Nodes",nodes)+block("Elements",elements))
else:
    data={}
    for case in cases:
        with (root/case/"probe.csv").open() as f: rows=list(csv.DictReader(f))
        assert len(rows)==2 and [float(r["time"]) for r in rows]==[0,1],(case,rows)
        data[case]={phase:{k:float(v) for k,v in r.items()} for phase,r in zip(("initial","solved"),rows)}
    report={"scope":"native scalar FV, single skew TRI3 interface, affine manufactured state; patched native gradient; initial and solved state","exact_gradient":[2,3,0],"cases":data}
    (root/"gradient-report.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    print(json.dumps(report,indent=2,sort_keys=True))
    for case,phases in data.items():
        for phase,d in phases.items():
            assert all(math.isfinite(v) for v in d.values()),(case,phase)
            for metric in ("cell_error","corrected_error","corrected_flux_error","native_error","native_flux_error"):
                assert d[metric]<1e-10,(case,phase,metric,d)
    for phase in ("initial","solved"):
        assert {round(data[c][phase]["active_owner"]) for c in cases[1:]}=={0,1},"Both FaceInfo ownership orientations not exercised"
    print("PATCHED_MOOSE_NATIVE_BOUNDARY_GRADIENT_PASS")
