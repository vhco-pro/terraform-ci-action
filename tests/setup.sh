#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

pin=$("$repo/scripts/setup.sh" pin terraform 1.17.2)
[[ $pin == $'1.17.2\t'* ]]
printf 'invalid archive\n' > "$scratch/invalid.zip"
if "$repo/scripts/setup.sh" install terraform 1.17.2 "$scratch/bin" "$scratch/invalid.zip" >"$scratch/log" 2>&1; then
  printf 'A wrong archive checksum passed.\n' >&2
  exit 1
fi
grep -F 'checksum' "$scratch/log"
test ! -e "$scratch/bin/terraform"
"$repo/scripts/setup.sh" install terraform 1.17.2 "$scratch/bin"
test "$("$scratch/bin/terraform" version -json | jq -r .terraform_version)" = 1.17.2
