#!/bin/bash
set -euo pipefail

fail() { echo "$*" >&2; exit 1; }
[[ "${GITHUB_REF:-}" == 'refs/heads/main' ]] || fail 'Releases require main.'
[[ "$(git rev-parse HEAD)" == "${GITHUB_SHA:?Missing release commit}" ]] || fail 'Checkout does not match the verified commit.'

version_pattern='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
versions() { grep -E "^${version_pattern}$" || true; }
latest=$(git tag --list --sort=version:refname | versions | tail -n 1)
requested=${REQUESTED_VERSION:-}
if [[ -z "$requested" ]]; then
    requested=$(git log -1 --format='%(trailers:key=Release-Version,valueonly)')
fi

if [[ -n "$latest" ]]; then
    git merge-base --is-ancestor "$latest" HEAD || fail 'Latest release is not an ancestor of this commit.'
fi

if [[ -n "$requested" ]]; then
    [[ "$requested" =~ ^${version_pattern}$ ]] || fail 'Use a canonical major.minor.patch version without a prefix.'
    next=$requested
else
    existing=$(git tag --points-at HEAD --sort=version:refname | versions | tail -n 1)
    if [[ -n "$existing" ]]; then
        next=$existing
    elif [[ -z "$latest" ]]; then
        echo 'No release tag exists. Run Release on main with an explicit initial version.'
        exit 0
    else
        IFS='.' read -r major minor patch <<< "$latest"
        next="${major}.$((minor + 1)).0"
    fi
fi

if git rev-parse --verify --quiet "refs/tags/$next" >/dev/null; then
    [[ "$(git rev-list -n 1 "$next")" == "$GITHUB_SHA" ]] || fail 'Requested tag already belongs to a different commit.'
    if gh release view "$next" >/dev/null 2>&1; then
        echo "Release $next already exists for this commit."
        exit 0
    fi
    gh release create "$next" --verify-tag --generate-notes
else
    if [[ -n "$latest" ]]; then
        greatest=$(printf '%s\n' "$latest" "$next" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
        [[ "$greatest" == "$next" && "$next" != "$latest" ]] || fail 'Requested version must be newer than the latest release.'
    fi
    gh release create "$next" --target "$GITHUB_SHA" --generate-notes
fi
