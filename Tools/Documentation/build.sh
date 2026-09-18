#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."
scratch_path="${APOGEE_SCRATCH_PATH:-.build}"
# Use the directory the dump step reports. The build system also leaves intermediate
# copies elsewhere in the scratch path, and those are not the reviewed output.
dump_output=$(swift package --scratch-path "$scratch_path" dump-symbol-graph --minimum-access-level public)
printf '%s\n' "$dump_output"
symbol_graph_path=$(printf '%s\n' "$dump_output" | sed -n 's/^Files written to //p' | tail -n 1)
if [ -z "$symbol_graph_path" ]; then
  echo "The symbol graph dump did not report an output directory" >&2
  exit 1
fi
python3 Tools/Documentation/classify-api.py "$symbol_graph_path" .build/documentation
xcrun docc convert Sources/ApogeeCore/ApogeeCore.docc \
  --additional-symbol-graph-dir .build/documentation/symbols \
  --output-dir .build/documentation/ApogeeCore.doccarchive \
  --warnings-as-errors
