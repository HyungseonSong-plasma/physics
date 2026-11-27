#!/usr/bin/env python3
"""Check exact database packaging and native/runtime lookup equivalence."""
import csv
import hashlib
import json
import math
from pathlib import Path
import sys

def database(root, manifest):
    root = Path(root)
    prefix = "physics_app/database/"
    expected = {e["path"][len(prefix):]: e["blob"] for e in manifest["included"]
                if e["path"].startswith(prefix)}
    assert len(expected) == 23
    actual = {}
    for p in root.rglob("*"):
        assert not p.is_symlink(), p
        if p.is_file():
            data = p.read_bytes()
            actual[p.relative_to(root).as_posix()] = hashlib.sha1(
                b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    assert actual == expected, "database manifest mismatch"
    print("RUNTIME_DATABASE_PATH_BLOB_PASS", len(actual))

def compare(native_path, runtime_path):
    def rows(path):
        with open(path, newline="") as f:
            return list(csv.DictReader(f))
    a, b = rows(native_path), rows(runtime_path)
    assert a and len(a) == len(b)
    for x, y in zip(a, b):
        assert set(x) == set(y) == {"time", "mu", "diffusion", "reaction", "heavy_diffusion"}
        for k in x:
            u, v = float(x[k]), float(y[k])
            assert math.isfinite(u) and math.isfinite(v)
            if k != "time":
                assert u > 0 and v > 0, (k, u, v)
            assert math.isclose(u, v, rel_tol=1e-12, abs_tol=0), (k, u, v)
    print("RUNTIME_NATIVE_DATABASE_LOOKUP_MATCH", len(a), a[-1])

if __name__ == "__main__":
    manifest = json.loads(Path("IMPORT_MANIFEST.json").read_text())
    database(sys.argv[1], manifest)
    database(sys.argv[2], manifest)
    compare(sys.argv[3], sys.argv[4])
