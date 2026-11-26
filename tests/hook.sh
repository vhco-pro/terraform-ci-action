#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
engine=${1:-terraform}
file=main.tf
if [[ $engine == tofu ]]; then file=main.tofu; fi
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
cd "$scratch"
git init -q
hook="$repo/examples/native-hook/.githooks/pre-commit"
test -x "$hook" || { printf 'Hook entry point absent: %s\n' "$hook" >&2; exit 1; }
printf 'output "value" {\nvalue="fixture"\n}\n' > "$file"
git add -- "$file"
printf 'output "value" {\n  value = "fixture"\n}\n' > "$file"
index=$(git write-tree)
worktree=$(sha256sum "$file")
if TERRAFORM_CI_CHECK="$repo/scripts/check.sh" TERRAFORM_CI_ENGINE="$engine" "$hook"; then
  printf 'Staged bad formatting passed.\n' >&2
  exit 1
fi
test "$index" = "$(git write-tree)"
test "$worktree" = "$(sha256sum "$file")"
git add -- "$file"
printf 'output "value" {\nvalue="fixture"\n}\n' > "$file"
index=$(git write-tree)
worktree=$(sha256sum "$file")
TERRAFORM_CI_CHECK="$repo/scripts/check.sh" TERRAFORM_CI_ENGINE="$engine" "$hook"
test "$index" = "$(git write-tree)"
test "$worktree" = "$(sha256sum "$file")"
