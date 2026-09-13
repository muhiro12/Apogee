#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/../.." && pwd)"
release_script="$repository_root/.github/scripts/release.sh"
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT
mkdir "$temporary_directory/bin" "$temporary_directory/repository"
export MOCK_RELEASE_LOG="$temporary_directory/releases.txt"
export MOCK_RELEASE_EXISTS=false
cat > "$temporary_directory/bin/gh" <<'SH'
#!/bin/bash
set -euo pipefail
[[ "$1" == release ]] || exit 2
case "$2" in
    view) [[ "$MOCK_RELEASE_EXISTS" == true ]] ;;
    create) printf '%s\n' "$@" >> "$MOCK_RELEASE_LOG" ;;
    *) exit 2 ;;
esac
SH
chmod +x "$temporary_directory/bin/gh"
export PATH="$temporary_directory/bin:$PATH"
cd "$temporary_directory/repository"
git init --quiet
git config user.name 'Release Test'
git config user.email 'release-test@example.invalid'
git -c commit.gpgsign=false commit --quiet --allow-empty -m 'Initial fixture'
GITHUB_SHA=$(git rev-parse HEAD)
export GITHUB_SHA
export GITHUB_REF=refs/heads/main
export REQUESTED_VERSION=
initial_commit=$GITHUB_SHA

run_release() {
    : > "$MOCK_RELEASE_LOG"
    bash "$release_script" > "$temporary_directory/output.txt" 2>&1
}
expect_creation() {
    printf '%s\n' release create "$@" > "$temporary_directory/expected.txt"
    diff -u "$temporary_directory/expected.txt" "$MOCK_RELEASE_LOG"
}
expect_failure() {
    if run_release; then
        echo 'Invalid release unexpectedly succeeded.' >&2
        exit 1
    fi
    test ! -s "$MOCK_RELEASE_LOG"
}

# An unversioned main must not choose an initial stability promise.
run_release
test ! -s "$MOCK_RELEASE_LOG"
REQUESTED_VERSION=none
run_release
test ! -s "$MOCK_RELEASE_LOG"
REQUESTED_VERSION=0.1
run_release
expect_creation 0.1 --target "$GITHUB_SHA" --generate-notes
REQUESTED_VERSION=0.1.0
run_release
expect_creation 0.1 --target "$GITHUB_SHA" --generate-notes

# Recover a missing release, then make retries idempotent.
git tag 0.1
REQUESTED_VERSION=
run_release
expect_creation 0.1 --verify-tag --generate-notes
MOCK_RELEASE_EXISTS=true
run_release
test ! -s "$MOCK_RELEASE_LOG"
MOCK_RELEASE_EXISTS=false

git -c commit.gpgsign=false commit --quiet --allow-empty -m 'Next fixture'
GITHUB_SHA=$(git rev-parse HEAD)
next_commit=$GITHUB_SHA
run_release
expect_creation 0.2 --target "$GITHUB_SHA" --generate-notes
REQUESTED_VERSION=1.0
run_release
expect_creation 1.0 --target "$GITHUB_SHA" --generate-notes
REQUESTED_VERSION=1.0.0
run_release
expect_creation 1.0 --target "$GITHUB_SHA" --generate-notes
REQUESTED_VERSION=0.1.1
run_release
expect_creation 0.1.1 --target "$GITHUB_SHA" --generate-notes

# A breaking change selects its major before automatic publication on main.
git -c commit.gpgsign=false commit --quiet --allow-empty \
    -m 'Change the public fixture' -m 'Release-Version: 2.0'
GITHUB_SHA=$(git rev-parse HEAD)
REQUESTED_VERSION=
run_release
expect_creation 2.0 --target "$GITHUB_SHA" --generate-notes
REQUESTED_VERSION=2.1.1
run_release
expect_creation 2.1.1 --target "$GITHUB_SHA" --generate-notes
git -c commit.gpgsign=false commit --quiet --allow-empty -m 'Continue fixture'
GITHUB_SHA=$(git rev-parse HEAD)

for REQUESTED_VERSION in 01.2.3 1.02 1.0.01 v1.0.0 1 1.0.0-beta.1 1.0.0.0 0.0.9 0.1 0.1.0; do
    expect_failure
done
REQUESTED_VERSION=
GITHUB_REF=refs/heads/develop
expect_failure
GITHUB_REF=refs/heads/main
GITHUB_SHA=$initial_commit
expect_failure
GITHUB_SHA=$(git rev-parse HEAD)

# Numeric ordering includes nonzero patches and multi-digit minor versions.
git tag 0.1.2 "$next_commit"
git tag 0.1.10 "$next_commit"
REQUESTED_VERSION=0.1.9
expect_failure
REQUESTED_VERSION=0.1.11
run_release
expect_creation 0.1.11 --target "$GITHUB_SHA" --generate-notes
REQUESTED_VERSION=
run_release
expect_creation 0.2 --target "$GITHUB_SHA" --generate-notes
git tag 0.2 "$next_commit"
git tag 0.10 "$next_commit"
run_release
expect_creation 0.11 --target "$GITHUB_SHA" --generate-notes
REQUESTED_VERSION=0.9
expect_failure

# Legacy tags retain their source identity during a naming migration.
git tag 1.0.0 "$next_commit"
REQUESTED_VERSION=1.0
expect_failure
git tag 1.0
expect_failure
git -c commit.gpgsign=false commit --quiet --allow-empty -m 'Continue after conflicting aliases'
GITHUB_SHA=$(git rev-parse HEAD)
REQUESTED_VERSION=
expect_failure
git tag -d 1.0 >/dev/null
git checkout --quiet --detach "$next_commit"
GITHUB_SHA=$next_commit
REQUESTED_VERSION=
run_release
expect_creation 1.0 --target "$GITHUB_SHA" --generate-notes
git tag 1.0
git tag v99.0
git tag 99.00
run_release
expect_creation 1.0 --verify-tag --generate-notes
MOCK_RELEASE_EXISTS=true
REQUESTED_VERSION=1.0.0
run_release
test ! -s "$MOCK_RELEASE_LOG"
MOCK_RELEASE_EXISTS=false
REQUESTED_VERSION=

# Maintenance still requires the verified main commit but performs no publishing.
git -c commit.gpgsign=false commit --quiet --allow-empty \
    -m 'Maintain the fixture workflow' -m 'Release-Version: none'
GITHUB_SHA=$(git rev-parse HEAD)
run_release
test ! -s "$MOCK_RELEASE_LOG"
GITHUB_REF=refs/heads/develop
expect_failure
GITHUB_REF=refs/heads/main
GITHUB_SHA=$initial_commit
expect_failure
GITHUB_SHA=$(git rev-parse HEAD)
REQUESTED_VERSION=1.1
run_release
expect_creation 1.1 --target "$GITHUB_SHA" --generate-notes
REQUESTED_VERSION=

# An older queued run must not publish after a newer release.
git checkout --quiet --detach "$initial_commit"
GITHUB_SHA=$initial_commit
expect_failure

echo 'Release automation checks passed without GitHub requests.'
