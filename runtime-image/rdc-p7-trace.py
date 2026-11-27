"""P7 evidence adapter: use the reviewed RDC parser, not a broad file copy."""

import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

from rdc.discovery.trace import Access, Scope, TraceError, parse_trace


def main():
    directory, output = map(Path, sys.argv[1:])
    streams = sorted(directory.glob("events.*"))
    if not streams or len(streams) > 4096:
        raise ValueError("Missing or excessive trace streams")
    total = sum(path.stat().st_size for path in streams)
    if total > 256 * 1024 * 1024:
        raise ValueError("Trace exceeds P7 parse budget")
    counts = Counter()
    candidates = Counter()
    unknown = Counter()
    external = Counter()
    generated = Counter()
    failed = Counter()
    digests = []
    errors = []
    for stream in streams:
        with stream.open("rb") as source:
            digests.append(hashlib.file_digest(source, "sha256").hexdigest())
        with stream.open(encoding="utf-8") as source:
            for index, line in enumerate(source, 1):
                try:
                    events = parse_trace((line,), "/case", (
                        "/proc", "/sys", "/dev", "/run", "/evidence", "/tmp", "/var/tmp",
                    ))
                except TraceError as error:
                    # Preserve syntax evidence without raw argv/environment payloads.
                    if len(errors) < 20:
                        shape = re.sub(r'"(?:\\.|[^"\\])*"', '"<redacted>"', line)
                        errors.append({"stream": stream.name, "line": index,
                                       "error": str(error), "shape": shape[:180].strip()})
                    counts["parse_errors"] += 1
                    continue
                for event in events:
                    counts["events"] += 1
                    counts[f"{event.scope.value}:{event.access.value}:{event.success}"] += 1
                    if not event.success:
                        failed[(event.path, event.errno or "")] += 1
                    elif event.scope is Scope.UNKNOWN:
                        unknown[(event.path, event.access.value)] += 1
                    elif event.scope is Scope.EXTERNAL:
                        external[(event.path, event.access.value)] += 1
                    elif event.access is Access.WRITE or event.scope is Scope.WORKSPACE:
                        generated[(event.path, event.access.value)] += 1
                    elif event.access in (Access.READ, Access.EXEC):
                        candidates[(event.path, event.access.value)] += 1
    def rows(counter, key):
        return [{"path": path, key: detail, "count": n}
                for (path, detail), n in sorted(counter.items())]
    result = {
        "schema": "physics.rdc-p7.trace.v1",
        "status": "TRACE_PARSE_FAILED" if errors else "TRACE_OBSERVATION_PASS",
        "science": "SCIENCE_HOLD",
        "rdc_sha": "a460a7415e7b891db0da60bf1f7be11513a6b6b0",
        "stream_count": len(streams),
        "trace_bytes": total,
        "stream_sha256": sorted(digests),
        "counts": dict(counts),
        "candidates": rows(candidates, "access"),
        "unknown_paths": rows(unknown, "access"),
        "external_paths": rows(external, "access"),
        "workspace_or_write": rows(generated, "access"),
        "failed_probes": rows(failed, "errno"),
        "parse_errors": errors,
    }
    output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    print("RDC_P7_TRACE", result["status"], counts["events"], len(candidates),
          len(unknown), counts["parse_errors"], flush=True)
    if errors:
        raise TraceError("Real Physics trace contains unsupported records; see evidence")
    if not any(access == "exec" and path == "/opt/physics/physics-opt"
               for path, access in candidates):
        raise TraceError("Physics executable was not observed")
    if not any(access == "exec" and "cc1plus" in path for path, access in candidates):
        raise TraceError("Cold C++ compiler execution was not observed")


if __name__ == "__main__":
    main()
