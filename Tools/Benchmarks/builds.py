#!/usr/bin/env python3
"""Measure isolated package targets and clean/incremental consumer builds."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--ref", help="Committed baseline; omit to snapshot the working tree")
    parser.add_argument("--output", type=Path, required=True, help="New private evidence directory")
    parser.add_argument("--jobs", type=int, default=4)
    options = parser.parse_args()
    repository = options.repository.resolve()
    output = options.output.resolve()
    if options.jobs < 1:
        parser.error("--jobs must be positive")
    output.mkdir(parents=True, exist_ok=False)
    source = output / "Apogee"
    source.mkdir()

    def capture(arguments, cwd=repository):
        return subprocess.check_output(arguments, cwd=cwd, text=True).strip()

    revision = capture(["git", "rev-parse", options.ref or "HEAD"])
    environment = os.environ.copy()
    environment["SDKROOT"] = capture(["xcrun", "--sdk", "macosx", "--show-sdk-path"])
    if options.ref:
        archive = subprocess.check_output(["git", "archive", revision], cwd=repository)
        subprocess.run(["tar", "-xf", "-", "-C", str(source)], input=archive, check=True)
    else:
        names = subprocess.check_output(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=repository
        ).decode().split("\0")
        for name in filter(None, names):
            original = repository / name
            if original.is_file():
                destination = source / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(original, destination)

    digest = hashlib.sha256()
    for path in sorted(source.rglob("*")):
        if path.is_file():
            digest.update(str(path.relative_to(source)).encode() + b"\0" + path.read_bytes())
    report = {
        "revision": revision,
        "source": options.ref or "working-tree",
        "snapshot_sha256": digest.hexdigest(),
        "started_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "xcode": capture(["xcodebuild", "-version"]),
        "swift": capture(["swift", "--version"]),
        "sdk": environment["SDKROOT"],
        "os": capture(["sw_vers"]),
        "hardware": {key: capture(["sysctl", "-n", key]) for key in (
            "hw.model", "hw.memsize", "hw.ncpu", "machdep.cpu.brand_string"
        )},
        "jobs": options.jobs,
        "cache_policy": "Fresh snapshot/build directories; global source and OS caches are not cleared. Dependency resolution is timed separately. Target timings follow explicit dependency warm-up.",
        "phases": [],
    }

    def run(name, arguments, cwd=source):
        started = time.perf_counter()
        with (output / (name + ".log")).open("w") as log:
            result = subprocess.run(arguments, cwd=cwd, env=environment, stdout=log, stderr=subprocess.STDOUT)
        phase = {"name": name, "command": arguments, "directory": str(cwd),
                 "seconds": round(time.perf_counter() - started, 3), "exit_code": result.returncode}
        report["phases"].append(phase)
        (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"{name}: {phase['seconds']:.3f}s (exit {result.returncode})", flush=True)
        if result.returncode:
            raise SystemExit(result.returncode)

    build = ["swift", "build", "-c", "release", "--jobs", str(options.jobs), "--disable-automatic-resolution"]
    run("resolve-package", ["swift", "package", "resolve"])
    for target in ("HTTPTypes", "OpenAPIRuntime", "Crypto", "OpenAPIURLSession", "ArgumentParser"):
        run("prepare-" + target, build + ["--target", target])
    run("generated-clean", build + ["--target", "AppStoreConnectGenerated"])
    run("core-clean", build + ["--target", "ApogeeCore"])
    run("cli-clean", build + ["--product", "apogee"])
    run("cli-incremental", build + ["--product", "apogee"])
    consumer = source / "Examples/ReleaseTools"
    run("resolve-consumer", ["swift", "package", "resolve"], consumer)
    run("consumer-clean", build + ["--product", "ReleaseToolsExample"], consumer)
    run("consumer-incremental", build + ["--product", "ReleaseToolsExample"], consumer)
    run("consumer-execution", [str(consumer / ".build/release/ReleaseToolsExample"), "AppStore/Metadata"], consumer)


if __name__ == "__main__":
    main()
