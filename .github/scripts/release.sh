#!/bin/bash
set -euo pipefail

fail() { echo "$*" >&2; exit 1; }
[[ "${GITHUB_REF:-}" == 'refs/heads/main' ]] || fail 'Releases require main.'
[[ "$(git rev-parse HEAD)" == "${GITHUB_SHA:?Missing release commit}" ]] || fail 'Checkout does not match the verified commit.'

version_pattern='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?'
version_tags() {
    git tag --list "$@" | { grep -E "^${version_pattern}$" || true; } |
        sort -t. -k1,1n -k2,2n -k3,3n
}
normalize_version() {
    local major minor patch
    IFS='.' read -r major minor patch <<< "$1"
    if [[ "${patch:-0}" == 0 ]]; then
        printf '%s.%s\n' "$major" "$minor"
    else
        printf '%s.%s.%s\n' "$major" "$minor" "$patch"
    fi
}
latest=$(version_tags | tail -n 1)
requested=${REQUESTED_VERSION:-}
if [[ -z "$requested" ]]; then
    requested=$(git log -1 --format='%(trailers:key=Release-Version,valueonly)')
fi
if [[ "$requested" == none ]]; then
    echo 'Release publication skipped for this verified maintenance commit.'
    exit 0
fi

if [[ -n "$latest" ]]; then
    git merge-base --is-ancestor "$latest" HEAD || fail 'Latest release is not an ancestor of this commit.'
    latest_version=$(normalize_version "$latest")
    if [[ "$latest_version" != *.*.* ]] && git rev-parse --verify --quiet "refs/tags/$latest_version" >/dev/null; then
        [[ "$(git rev-list -n 1 "$latest_version")" == "$(git rev-list -n 1 "$latest")" ]] || fail 'Latest version aliases identify different commits.'
    fi
fi

if [[ -n "$requested" ]]; then
    [[ "$requested" =~ ^${version_pattern}$ ]] || fail 'Use major.minor or major.minor.patch without a prefix or leading zeroes.'
    next=$(normalize_version "$requested")
else
    existing=$(version_tags --points-at HEAD | tail -n 1)
    if [[ -n "$existing" ]]; then
        next=$(normalize_version "$existing")
    elif [[ -z "$latest" ]]; then
        echo 'No release tag exists. Run Release on main with an explicit initial version.'
        exit 0
    else
        IFS='.' read -r major minor patch <<< "$latest"
        next="${major}.$((minor + 1))"
    fi
fi

# A legacy zero-patch alias must never identify a different source revision.
if [[ "$next" != *.*.* ]] && git rev-parse --verify --quiet "refs/tags/$next.0" >/dev/null; then
    [[ "$(git rev-list -n 1 "$next.0")" == "$GITHUB_SHA" ]] || fail 'Legacy version tag already belongs to a different commit.'
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
        if [[ "$next" == "$latest_version" ]]; then
            [[ "$(git rev-list -n 1 "$latest")" == "$GITHUB_SHA" ]] || fail 'Requested version already belongs to a different commit.'
        else
            greatest=$(printf '%s\n' "$latest_version" "$next" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
            [[ "$greatest" == "$next" ]] || fail 'Requested version must be newer than the latest release.'
        fi
    fi
    gh release create "$next" --target "$GITHUB_SHA" --generate-notes
fi
