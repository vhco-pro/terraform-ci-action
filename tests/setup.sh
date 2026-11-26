#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

version=$(awk '$1 == "terraform" { print $2 }' "$repo/scripts/.tool-versions")
pin=$("$repo/scripts/setup.sh" pin terraform "$version")
[[ $pin == "$version"$'\t'* ]]
printf 'invalid archive\n' > "$scratch/invalid.zip"
if "$repo/scripts/setup.sh" install terraform "$version" "$scratch/bin" "$scratch/invalid.zip" >"$scratch/log" 2>&1; then
  printf 'A wrong archive checksum passed.\n' >&2
  exit 1
fi
grep -F 'checksum' "$scratch/log"
test ! -e "$scratch/bin/terraform"
"$repo/scripts/setup.sh" install terraform "$version" "$scratch/bin"
test "$("$scratch/bin/terraform" version -json | jq -r .terraform_version)" = "$version"
