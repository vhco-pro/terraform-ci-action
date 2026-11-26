#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
cd "$scratch"
git init -q -b main
git -c user.name='Synthetic fixture' -c user.email=fixture@example.invalid commit -q --allow-empty -m fixture
tested=$(git rev-parse HEAD)
git tag v1.2.3
git tag v1.2.3-rc.1
git -c user.name='Synthetic fixture' -c user.email=fixture@example.invalid commit -q --allow-empty -m other
git tag v1.2.4
gate() {
  GITHUB_EVENT_NAME="$1" GITHUB_REF="$2" GITHUB_SHA="$tested" \
    RELEASE_DEFAULT_BRANCH=main RELEASE_TEST_RESULT="${3:-success}" "$repo/scripts/release-mode.sh"
}
test "$(gate push refs/heads/main)" = 'mode=version'
test "$(gate pull_request refs/pull/1/merge)" = 'mode=none'
test "$(gate push refs/heads/main failure)" = 'mode=none'
test "$(gate workflow_dispatch refs/tags/v1.2.3)" = $'mode=recover\ntag=v1.2.3'
for invalid_ref in refs/heads/main refs/tags/v1.2.3-rc.1 refs/tags/v1.2.4 refs/tags/v9.9.9; do
  if gate workflow_dispatch "$invalid_ref"; then
    printf 'Unexpected release recovery for %s\n' "$invalid_ref" >&2
    exit 1
  fi
done
