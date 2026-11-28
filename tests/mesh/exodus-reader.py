"""Compare same-build, same-case multilayer and merged-input numerical results."""

import csv
import ctypes as C
import hashlib
import json
import math
import os
from pathlib import Path
import sys

RTOL = 1e-12
ATOL = 1e-12


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def equal_number(a, b, label, exact=False):
    require(math.isfinite(a) and math.isfinite(b), "Nonfinite: " + label)
    require(a == b if exact else math.isclose(a, b, rel_tol=RTOL, abs_tol=ATOL),
            f"Numerical mismatch {label}: {a} != {b}")


def compare_csv(a, b):
    with a.open(newline="") as fa, b.open(newline="") as fb:
        ra, rb = csv.DictReader(fa), csv.DictReader(fb)
        require(ra.fieldnames == rb.fieldnames, "CSV header mismatch")
        la, lb = list(ra), list(rb)
    require(len(la) == len(lb) >= 2, "CSV time row mismatch")
    for i, (x, y) in enumerate(zip(la, lb)):
        for name in x:
            equal_number(float(x[name]), float(y[name]), f"CSV {i}:{name}")
    return {"rows": len(la), "columns": len(ra.fieldnames)}


class Exodus:
    def __init__(self, path):
        self.nc = C.CDLL("/opt/libmesh/lib/libnetcdf.so.13")
        self.id = C.c_int()
        self.call("nc_open", os.fsencode(path), 0, C.byref(self.id))

    def call(self, name, *args):
        require(getattr(self.nc, name)(*args) == 0, "netCDF error " + name)

    def close(self):
        self.call("nc_close", self.id)

    def variables(self):
        n = C.c_int()
        self.call("nc_inq_nvars", self.id, C.byref(n))
        result = {}
        for v in range(n.value):
            name = C.create_string_buffer(257)
            kind, rank = C.c_int(), C.c_int()
            self.call("nc_inq_varname", self.id, v, name)
            self.call("nc_inq_vartype", self.id, v, C.byref(kind))
            self.call("nc_inq_varndims", self.id, v, C.byref(rank))
            dimids = (C.c_int * rank.value)()
            self.call("nc_inq_vardimid", self.id, v, dimids)
            dims = []
            for dim in dimids:
                length = C.c_size_t()
                label = C.create_string_buffer(257)
                self.call("nc_inq_dim", self.id, dim, label, C.byref(length))
                dims.append((label.value.decode(), length.value))
            result[name.value.decode()] = (v, kind.value, tuple(dims))
        return result

    def values(self, v, kind, dims):
        count = math.prod(n for _, n in dims)
        require(count <= 10_000_000, "Excessive Exodus variable size")
        if kind == 2:
            raw = C.create_string_buffer(count)
            self.call("nc_get_var_text", self.id, v, raw)
            return raw.raw
        require(kind in {1, 3, 4, 5, 6, 7, 8, 9, 10, 11}, "Unsupported netCDF type")
        data = (C.c_double * count)()
        self.call("nc_get_var_double", self.id, v, data)
        return data


