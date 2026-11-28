"""Verify and publish the bounded native Parent and Maxwell Exodus payloads."""
import importlib.util
import json
import math
from pathlib import Path
import re
import shutil
import sys

spec = importlib.util.spec_from_file_location("reader", Path(__file__).with_name("exodus-reader.py"))
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)

def inspect(path, required, endpoint):
    ex = reader.Exodus(path)
    try:
        vs = ex.variables()
        times = list(ex.values(*vs["time_whole"]))
        assert len(times) >= 2 and all(math.isfinite(t) for t in times), (path, times)
        assert math.isclose(times[0], 0.0, abs_tol=1e-16), (path, times)
        assert math.isclose(times[-1], endpoint, rel_tol=1e-10, abs_tol=1e-16), (path, times)
        assert all(a <= b for a,b in zip(times,times[1:])), (path,times)
        fields = {}
        for kind in ("nod", "elem"):
            key = f"name_{kind}_var"
            if key not in vs:
                continue
            raw = ex.values(*vs[key])
            n,w = [v for _,v in vs[key][2]]
            for i in range(n):
                name = raw[i*w:(i+1)*w].split(b"\0",1)[0].decode().strip()
                if name not in required:
                    continue
                prefix = f"vals_{kind}_var{i+1}"
                count = 0
                for k in vs:
                    if k != prefix and not (kind == "elem" and re.fullmatch(prefix+r"eb\d+",k)):
                        continue
                    dims = vs[k][2]
                    assert len(dims)==2 and dims[0][1]==len(times), k
                    width = dims[-1][1]
                    if not width:
                        continue
                    data = list(ex.values(*vs[k]))
                    for frame in (data[:width],data[-width:]):
                        assert all(math.isfinite(x) for x in frame), k
                        assert any(abs(x)<1e30 for x in frame), k
                    count += width
                if count:
                    fields[name] = count
        assert set(fields)==set(required), (path,fields)
        return {"times":times,"fields":fields,"sha256":reader.sha(path)}
    finally:
        ex.close()

def main():
    source, dest = map(Path, sys.argv[1:])
    parent = source/"parent.e"
    children = sorted(source.glob("parent*maxwell_t6*.e"))
    assert len(children)==1, f"Expected one Maxwell Exodus; found {children}"
    child = children[0]
    assert child != parent
    report = {
        "parent": inspect(parent, {"log_e","log_O2p","log_Op","log_Om","E_real_rf_t6","E_imag_rf_t6"}, 1e-9),
        "maxwell": inspect(child, {"E_real","E_imag"}, 1.0),
        "maxwell_time_semantics": "Steady executioner output index, not physical seconds",
        "maxwell_source_filename": child.name,
        "scope": "Bounded one-step output validation, not scientific equivalence"
    }
    shutil.copyfile(parent,dest/"parent.e")
    shutil.copyfile(child,dest/"maxwell.e")
    shutil.copyfile(source/"parent.csv",dest/"parent.csv")
    (dest/"manifest.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    print(json.dumps(report,sort_keys=True))

if __name__ == "__main__":
    main()
