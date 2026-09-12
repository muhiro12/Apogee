#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/../.." && pwd)"
binary="${1:?Pass the path to the built apogee executable}"
binary="$(cd "$(dirname "$binary")" && pwd)/$(basename "$binary")"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

"$binary" --help > "$temporary_directory/help.txt"
"$binary" release-status --help > "$temporary_directory/status-help.txt"
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

if "$binary" release-status --version 1.2.3 --apply > "$temporary_directory/status-apply.txt" 2>&1; then
    echo 'The read-only status command unexpectedly accepted --apply.' >&2
    exit 1
fi
grep -q 'Unknown option' "$temporary_directory/status-apply.txt"

mkdir "$temporary_directory/empty-metadata"
if "$binary" validate-metadata --metadata-path "$temporary_directory/empty-metadata" > "$temporary_directory/empty.txt" 2>&1; then
    echo 'Empty metadata unexpectedly passed validation.' >&2
    exit 1
fi
grep -q 'No metadata files matched' "$temporary_directory/empty.txt"
echo 'CLI smoke checks passed without App Store Connect requests.'
