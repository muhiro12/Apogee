#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."
scratch_path="${APOGEE_SCRATCH_PATH:-.build}"
swift package --scratch-path "$scratch_path" dump-symbol-graph --minimum-access-level public
python3 Tools/Documentation/classify-api.py "$scratch_path" .build/documentation
xcrun docc convert Sources/ApogeeCore/ApogeeCore.docc \
  --additional-symbol-graph-dir .build/documentation/symbols \
  --output-dir .build/documentation/ApogeeCore.doccarchive \
  --warnings-as-errors
