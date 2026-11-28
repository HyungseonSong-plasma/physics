"""Physics P7 trace-selected structural candidate; not runtime acceptance."""

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys

# Explicit file-level selection inside the pinned full-runtime image.
PREFIXES = (
    "/bin", "/lib", "/lib64", "/usr", "/opt/physics", "/opt/libmesh",
    "/opt/openmpi", "/opt/petsc", "/opt/vtk", "/opt/wasp",
    "/opt/physics_vendor", "/opt/rh/gcc-toolset-13/root/usr",
)
CONFIGS = {"/etc/localtime", "/etc/nsswitch.conf", "/etc/passwd"}
APP = "/opt/physics/physics-opt"


def sha(path):
    with path.open("rb") as stream:
        h = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
        return h.hexdigest()


def inside(path, root):
    return path == root or path.startswith(root + "/")


def allowed(path):
    return path in CONFIGS or any(inside(path, prefix) for prefix in PREFIXES)


def canonical(path):
    return path.startswith("/") and not path.startswith("//") and (
        str(PurePosixPath(path)) == path and ".." not in PurePosixPath(path).parts
    )


def write_json(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")


def stage(ev, root):
    trace_path = ev / "rdc-p7-trace.json"
    trace = json.loads(trace_path.read_text())
    if trace["status"] != "TRACE_OBSERVATION_PASS" or trace["parse_errors"]:
        raise ValueError("Trace must pass before candidate staging")
    selected = {}
    deferred = []
    generated = []
    unsupported = []

    def add(target, access, evidence):
        if not canonical(target) or not allowed(target):
            raise ValueError("Unapproved target: " + target)
        src = Path(target)
        actual = str(src.resolve(strict=True))
        if not allowed(actual):
            raise ValueError("Unapproved resolved source: " + actual)
        st = src.stat()
        mode = stat.S_IMODE(st.st_mode)
        if mode & 0o7000:
            raise ValueError("Special mode: " + target)
        dest = root / target.lstrip("/")
        if stat.S_ISDIR(st.st_mode):
            if mode & 0o555 != 0o555:
                raise ValueError("Inaccessible directory: " + target)
            dest.mkdir(parents=True, exist_ok=True)
            kind = "directory"
            digest = None
            size = 0
        elif stat.S_ISREG(st.st_mode):
            if mode & 0o444 != 0o444:
                raise ValueError("Unreadable source: " + target)
            kind = "executable" if access == "exec" else (
                "header" if "/include/" in target else
                "config" if target in CONFIGS else "data"
            )
            if kind == "executable" and mode & 0o111 != 0o111:
                raise ValueError("Nonportable executable mode: " + target)
            dest.parent.mkdir(parents=True, exist_ok=True)
            # Preserve path aliases as explicit regular files, not directory
            # copies. Record actual source and hashes; no chmod or strip.
            if not dest.exists():
                shutil.copy2(src, dest, follow_symlinks=True)
            digest = sha(src)
            if sha(dest) != digest or stat.S_IMODE(dest.stat().st_mode) != mode:
                raise ValueError("Staged alias differs: " + target)
            size = st.st_size
        else:
            raise ValueError("Nonregular source: " + target)
        prev = selected.get(target)
        if prev is not None:
            if prev["sha256"] != digest:
                raise ValueError("Duplicate source drift")
            prev["evidence"].append(evidence)
            if kind == "executable":
                prev["kind"] = kind
            return
        selected[target] = {"target": target, "actual": actual, "kind": kind,
                            "mode": mode, "bytes": size, "sha256": digest,
                            "evidence": [evidence]}

    for rec in trace["candidates"]:
        path = rec["path"]
        if path == "/etc/ld.so.cache":
            deferred.append({"path": path, "reason": "generated loader cache; not copied"})
            continue
        try:
            add(path, rec["access"], {"trace": rec})
        except (OSError, ValueError) as exc:
            unsupported.append({"path": path, "reason": str(exc)})

    # The observed linker paths containing '..' require actual resolution
    # equality, not blind lexical normalization. Virtual and case paths are
    # external to the runtime; relative generated JIT names remain evidence.
    for rec in trace["unknown_paths"]:
        path = rec["path"]
        if re.fullmatch(r"(?:\./tmp_jit_[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)?|\.jitcache/[0-9a-f]+\.so)", path):
            generated.append(rec)
            continue
        normal = os.path.normpath(path)
        if path.startswith("/") and any(inside(normal, x) for x in ("/case", "/proc", "/sys", "/dev", "/run", "/tmp", "/evidence")):
            deferred.append({"path": path, "reason": "workspace or virtual path; not collected"})
            continue
        try:
            if not canonical(normal) or not allowed(normal):
                raise ValueError("unresolved relative or unapproved path")
            if Path(path).resolve(strict=True) != Path(normal).resolve(strict=True):
                raise ValueError("lexical and actual resolution differ")
            add(normal, rec["access"], {"trace": rec, "normalized": normal})
        except (OSError, ValueError) as exc:
            unsupported.append({"path": path, "reason": str(exc)})

    # Explicitly retain the entire already-reviewed 23-file Physics database,
    # without relying on this one case to exercise every table. No private data.
    database = Path("/opt/physics/database")
    entries = sorted(database.iterdir())
    if len(entries) != 23 or any(not p.is_file() or p.is_symlink() for p in entries):
        raise ValueError("Expected exact 23 regular public database files")
    for item in entries:
        add(str(item), "read", {"explicit": "reviewed public database"})
    if sha(root / APP.lstrip("/")) != (ev / "executable.sha256").read_text().split()[0]:
        raise ValueError("Physics binary identity mismatch")
    profile = {"schema": "physics.rdc-p7.structural-profile.v1",
               "trace_sha256": sha(trace_path), "selected": list(selected.values()),
               "deferred": deferred, "generated_name_observations": generated,
               "unsupported": unsupported, "status": "STRUCTURAL_CANDIDATE_ONLY",
               "limitations": ["observations not proof of necessity",
                               "relative JIT paths not proven by cwd tracking",
                               "loader cache and search-order validation pending",
                               "static ELF closure and isolated numerical replay pending"]}
    write_json(ev / "rdc-p7-profile.json", profile)
    print("RDC_P7_PROFILE", len(selected), sum(r["bytes"] for r in selected.values()),
          "deferred", len(deferred), "generated", len(generated),
          "unsupported", len(unsupported), flush=True)
    if unsupported:
        print("RDC_P7_PROFILE_BLOCKERS", json.dumps(unsupported[:30]), flush=True)
        raise ValueError("Unclassified observed input; see profile")


def collect_candidate(ev, source, runtime):
    from rdc.collector import collect
    from rdc.discovery.elf import read_elf, ElfError
    from rdc.graph import DependencyGraph
    from rdc.models import BuildIdentity, CollectionPolicy, Dependency, DependencyKind, Edge, Evidence, Resolution
    from rdc.planner import plan_collection
    from rdc.validator import verify_rootfs

    profile_path = ev / "rdc-p7-profile.json"
    profile = json.loads(profile_path.read_text())
    if profile["unsupported"]:
        raise ValueError("Profile has unresolved inputs")
    graph = DependencyGraph(str(source))
    policy = CollectionPolicy((str(source),))
    root_node = str(source / APP.lstrip("/"))
    elf_observations = []
    for entry in profile["selected"]:
        target = entry["target"]
        path = source / target.lstrip("/")
        kind = DependencyKind(entry["kind"])
        if kind != DependencyKind.DIRECTORY:
            if sha(path) != entry["sha256"]:
                raise ValueError("Staging changed: " + target)
            with path.open("rb") as stream:
                header = stream.read(18)
            if header[:4] == b"\x7fELF" and int.from_bytes(header[16:18], "little") in (2, 3):
                try:
                    meta = read_elf(str(path))
                    elf_observations.append({"target": target, "interpreter": meta.interpreter,
                        "needed": list(meta.needed), "rpath": meta.rpath, "runpath": meta.runpath})
                    if kind != DependencyKind.EXECUTABLE:
                        kind = DependencyKind.INTERPRETER if target.endswith("/ld-linux-x86-64.so.2") else DependencyKind.SHARED_LIBRARY
                except ElfError as exc:
                    elf_observations.append({"target": target, "error": str(exc)})
        graph.add_node(Dependency(str(path), target, kind))
    write_json(ev / "rdc-p7-elf-inventory.json", elf_observations)
    for entry in profile["selected"]:
        path = str(source / entry["target"].lstrip("/"))
        if path != root_node:
            graph.add_edge(Edge(root_node, Evidence("physics-profile", "explicit-observed-input", entry["target"]),
                                Resolution.RESOLVED, path))
    build = BuildIdentity("physics-s6-417-trace-candidate", sha(profile_path), "linux-x86_64",
                          (("rdc", "a460a7415e7b891db0da60bf1f7be11513a6b6b0"),),
                          ("actual S6-417 observation", "structural only; no isolated replay"))
    plan = plan_collection(graph, (root_node,), policy, build)
    manifest = collect(plan, runtime)
    digest = hashlib.sha256(manifest).hexdigest()
    (ev / "rdc-p7-collection.json").write_bytes(manifest)
    verified = verify_rootfs(runtime, manifest, digest)
    write_json(ev / "rdc-p7-structural-receipt.json",
               {"status": "STRUCTURAL_CANDIDATE_PASS", "manifest_sha256": digest,
                "bytes": verified.collected_bytes, "selected": len(profile["selected"]),
                "elf_objects": len(elf_observations), "science": "SCIENCE_HOLD",
                "runtime_equivalence": "NOT_RUN"})
    print("RDC_P7_STRUCTURAL_CANDIDATE_PASS", len(profile["selected"]),
          verified.collected_bytes, digest, flush=True)


if __name__ == "__main__":
    command, *args = sys.argv[1:]
    paths = [Path(x).resolve() for x in args]
    if command == "stage":
        stage(*paths)
    elif command == "collect":
        collect_candidate(*paths)
    else:
        raise ValueError("Unsupported command")
