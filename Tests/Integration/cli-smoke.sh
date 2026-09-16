#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/../.." && pwd)"
binary="${1:?Pass the path to the built apogee executable}"
binary="$(cd "$(dirname "$binary")" && pwd)/$(basename "$binary")"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

"$binary" --help > "$temporary_directory/help.txt"
"$binary" release-status --help > "$temporary_directory/status-help.txt"
"$binary" read-metadata --help > "$temporary_directory/metadata-help.txt"
"$binary" create-version --help > "$temporary_directory/create-help.txt"
grep -q 'manual release' "$temporary_directory/create-help.txt"
"$binary" validate-metadata \
  --apogee-config "$repository_root/Examples/ReleaseTools/apogee.json" \
  --release-notes-only > "$temporary_directory/validation.txt"
grep -q 'en-US' "$temporary_directory/validation.txt"
grep -q '\[ja\]' "$temporary_directory/validation.txt"

if "$binary" update-metadata --version 1.2.3 --apply --dry-run > "$temporary_directory/conflict.txt" 2>&1; then
    echo 'Conflicting execution flags unexpectedly succeeded.' >&2
    exit 1
fi
grep -q 'Use either --dry-run or --apply' "$temporary_directory/conflict.txt"

if "$binary" create-version --version 2.0 --apply --dry-run > "$temporary_directory/create-conflict.txt" 2>&1; then
    echo 'Version creation unexpectedly accepted conflicting execution flags.' >&2
    exit 1
fi
grep -q 'Use either --dry-run or --apply' "$temporary_directory/create-conflict.txt"

if "$binary" create-version --version 2.0 --release-type AFTER_APPROVAL > "$temporary_directory/create-release-type.txt" 2>&1; then
    echo 'Version creation unexpectedly accepted an automatic release option.' >&2
    exit 1
fi
grep -q 'Unknown option' "$temporary_directory/create-release-type.txt"

if "$binary" release-status --version 1.2.3 --apply > "$temporary_directory/status-apply.txt" 2>&1; then
    echo 'The read-only status command unexpectedly accepted --apply.' >&2
    exit 1
fi
grep -q 'Unknown option' "$temporary_directory/status-apply.txt"

for mode in --apply --dry-run; do
    if "$binary" read-metadata --version 1.2.3 "$mode" > "$temporary_directory/metadata-mode.txt" 2>&1; then
        echo 'The read-only metadata command unexpectedly accepted an execution mode.' >&2
        exit 1
    fi
    grep -q 'Unknown option' "$temporary_directory/metadata-mode.txt"
done

mkdir "$temporary_directory/empty-metadata"
if "$binary" validate-metadata --metadata-path "$temporary_directory/empty-metadata" > "$temporary_directory/empty.txt" 2>&1; then
    echo 'Empty metadata unexpectedly passed validation.' >&2
    exit 1
fi
grep -q 'No metadata files matched' "$temporary_directory/empty.txt"

"$binary" validate-metadata \
  --apogee-config "$repository_root/Examples/ReleaseTools/apogee.json" \
  --output json > "$temporary_directory/validation.json" 2> "$temporary_directory/json-stderr.txt"
test ! -s "$temporary_directory/json-stderr.txt"
python3 - "$temporary_directory/validation.json" <<'PY'
import json
import sys
with open(sys.argv[1]) as stream:
    result = json.load(stream)
assert result['schemaVersion'] == 1
assert result['kind'] == 'release-plan'
assert result['command'] == 'validate-metadata'
assert result['mode'] == 'local'
assert result['target'] is None
assert result['requestedTarget'] is None
assert result['plan']['plannedMutationCount'] == 0
assert not result['plan']['hasChanges']
assert result['verification']['status'] == 'performed'
assert {item['locale'] for item in result['verification']['checks']} == {'en-US', 'ja'}
assert all(item['scope'] == 'local-validation' for item in result['verification']['checks'])
PY

assert_json_failure() {
    if "$binary" "$@" > "$temporary_directory/failure.json" 2> "$temporary_directory/failure-stderr.txt"; then
        echo 'A failing JSON invocation unexpectedly succeeded.' >&2
        exit 1
    fi
    test ! -s "$temporary_directory/failure.json"
    test -s "$temporary_directory/failure-stderr.txt"
}
assert_json_failure validate-metadata --metadata-path "$temporary_directory/empty-metadata" --output json
assert_json_failure validate-metadata --output invalid
assert_json_failure create-version --version 2.0 --apply --dry-run --output json
assert_json_failure release-status --version 2.0 --app-id EXAMPLE_APP_ID \
  --apogee-config "$temporary_directory/missing.json" --output json
echo 'CLI smoke checks passed without App Store Connect requests.'
