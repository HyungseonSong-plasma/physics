"""Verify actual VolumetricFlowRate on unit face for inflow and outflow."""
import csv,json,math,sys
from pathlib import Path
root=Path(sys.argv[1])
cases=("exterior","internal_active_first","internal_passive_first")
data={}
for case in cases:
    data[case]={}
    for direction,sign in (("outflow",1),("inflow",-1)):
        with (root/case/direction/"flow.csv").open() as f:
            rows=list(csv.DictReader(f))
        initial=[r for r in rows if float(r["time"])==0]
        assert len(initial)==1,(case,direction,rows)
        d={k:float(v) for k,v in initial[0].items()}
        data[case][direction]=d
report={"scope":"native FV VolumetricFlowRate; prescribed constant velocity; no solve; one-sided flow; unit face; upwind quantity","expected_volume_flow":2,"expected_quantity_flow":6,"cases":data}
(root/"flow-report.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
print(json.dumps(report,indent=2,sort_keys=True))
for case,directions in data.items():
    for direction,d in directions.items():
        sign=1 if direction=="outflow" else -1
        for key,expected in (("volume_flow",2*sign),("quantity_flow",6*sign)):
            assert math.isfinite(d[key]) and abs(d[key]-expected)<1e-10,(case,direction,key,d)
print("APP_BOUNDARY_VOLUMETRIC_FLOW_RATE_PASS")
