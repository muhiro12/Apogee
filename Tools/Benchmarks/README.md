# Build benchmarks

Run this macOS maintainer tool with a supported release Xcode selected through
`DEVELOPER_DIR`. Python 3 and standard Xcode/SwiftPM tools are sufficient.
Use new private output directories; logs and source snapshots may contain local
paths or uncommitted files and must not be published wholesale.

```sh
benchmark_root="$(mktemp -d)"
python3 Tools/Benchmarks/builds.py --ref 0.4.0 \
  --output "$benchmark_root/baseline" --jobs 4
python3 Tools/Benchmarks/builds.py \
  --output "$benchmark_root/candidate" --jobs 4
```

The baseline uses `git archive`; the candidate copies tracked and nonignored
untracked files from the working tree. Each report includes a source digest,
revision, toolchain, selected SDK, OS, hardware, command, cache policy, exit code,
and wall-clock duration. Child processes explicitly use the SDK belonging to the
selected Xcode, preventing a Command Line Tools SDK from being mixed with it.

Each snapshot starts with fresh package and consumer `.build` directories.
Dependency resolution is a separate phase. Package dependency targets are warmed
before measuring the generated client, core, and CLI sequentially. These are
target-invocation elapsed times, including SwiftPM overhead, not compiler CPU
profiles or fully independent clean builds. The separate consumer starts clean
and then repeats its unchanged build to measure a no-op incremental invocation.
The executable checks fictional local metadata without API credentials.

Run comparisons sequentially without another build. Global source caches, OS
caches, temperature, and unrelated host activity are not controlled. Repeat
measurements and report ranges rather than treating one result as universal.
Keep debug/Release, package/consumer, no-op/source-change increments, and real
plugin startup separate when interpreting results. This script measures Release
library-consumer builds, not all of those other scenarios.

See [the recorded baseline and optimization](../../docs/build-performance.md).
