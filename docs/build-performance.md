# Generated client build cost

The generated target is the dominant package compilation cost. Removing 15
unused operation entry points reduced committed generated source from 49,685 to
38,133 lines (23%). The adapter still calls all 18 retained operations; screenshot
planning reads local files and never needed the removed upload endpoints.

## Measurement on 2026-09-13

Measurements used Xcode 26.6 (17F113), Swift 6.3.3, its macOS 26.5 SDK, and an
Apple M3 with 8 CPU cores and 24 GiB RAM, running macOS 27.0 (26A5388g).
This is shipping-Xcode evidence on a newer host OS, not an Xcode 27 build.

[The benchmark tool](../Tools/Benchmarks/README.md) ran Release builds with
`--jobs 4 --disable-automatic-resolution`, fresh per-run build directories,
separate dependency resolution, and sequential dependency-target warm-up. Global
source/OS caches and host temperature were not reset. Runs were sequential in the
order baseline 1, package-scope-only, baseline 2, then trimmed candidate.

| Phase (seconds) | 0.4.0 run 1 | Package scope only | 0.4.0 run 2 | Trimmed candidate |
| --- | ---: | ---: | ---: | ---: |
| Generated target, dependencies warm | 112.782 | 97.984 | 88.132 | 73.561 |
| Core target, generated target warm | 7.818 | 9.297 | 7.928 | 7.292 |
| CLI product, preceding targets warm | 3.573 | 3.610 | 3.521 | 3.373 |
| CLI no-op incremental | 0.784 | 0.784 | 0.790 | 0.745 |
| Separate consumer, clean build | 120.842 | 118.613 | 113.326 | 92.642 |
| Separate consumer, no-op incremental | 2.713 | 2.684 | 2.665 | 2.555 |

The baseline is tag `0.4.0`, commit
`c1b60dd84ef5492fcc93210315bfd268fc089462`. The package-scope-only experiment
changed generated access modifiers without changing operations. It falls within
baseline variation, so it does **not** establish a performance improvement.

The trimmed candidate combines package access with the 18-operation graph and the
public API documentation/consumer examples. Generated-file SHA-256 values are:

- Client.swift: `50e78bc149922cca13b07a1569eb6086c936e4c9910651761db77fde98a37843`
- Types.swift: `9096c41adbe68cfc7271a26554791f28337e2af4e2e8c7dc951373375a767814`

The candidate is faster than both baselines in this small sample, including the
separate consumer. These are wall-clock observations, not a universal speedup
guarantee or a comparison with earlier uncontrolled 24-minute reports. No-op
incremental builds do not measure a source-change rebuild. Current CI timings
also include different caches, hardware, build modes, and plugin preparation;
they should be reported separately from this benchmark.

All timed runs used OpenAPI Runtime 1.12.0. The subsequent 1.12.1 maintenance
update is verified separately for correctness; it is not the basis of the
performance comparison above.

## Compatibility and maintenance tradeoffs

The visibility change deliberately removes generated APIs from the consumer
contract during 0.x; see [migration notes](public-api.md#internal-implementation-and-migration-from-04).
For supported operations, normalizing access modifiers leaves only deletions in
the generated diff. Regeneration used the same baseline Apple document and pinned
generator, with no handwritten generated-code edits or new binary dependency.

The operation allowlist now follows the actual adapter. Adding a future feature
requires adding its operation IDs and regenerating at the same time as the
adapter and tests. Existing transitive response schemas remain intact; pruning
individual response fields would need separate evidence to avoid losing state
needed for validation. Precompiled binaries and custom compiler optimization
flags were not introduced because this bounded reduction already improves the
measured source-build path without a new distribution or toolchain burden.

The package tests cover the retained adapter operations and safety behavior; the
trimmer test checks removal of an unused operation and its exclusive schema while
retaining transitive schemas used by a supported operation. Release CLI, library
consumer, and plugin verification remain required before publication.
