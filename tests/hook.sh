#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
cd "$scratch"
git init -q
hook="$repo/examples/native-hook/.githooks/pre-commit"
test -x "$hook" || { printf 'Hook entry point absent: %s\n' "$hook" >&2; exit 1; }
printf 'output "value" {\nvalue="fixture"\n}\n' > main.tf
git add -- main.tf
printf 'output "value" {\n  value = "fixture"\n}\n' > main.tf
index=$(git write-tree)
worktree=$(sha256sum main.tf)
if TERRAFORM_CI_CHECK="$repo/scripts/check.sh" TERRAFORM_CI_ENGINE=terraform "$hook"; then
  printf 'Staged bad formatting passed.\n' >&2
  exit 1
fi
test "$index" = "$(git write-tree)"
test "$worktree" = "$(sha256sum main.tf)"
git add -- main.tf
printf 'output "value" {\nvalue="fixture"\n}\n' > main.tf
index=$(git write-tree)
worktree=$(sha256sum main.tf)
TERRAFORM_CI_CHECK="$repo/scripts/check.sh" TERRAFORM_CI_ENGINE=terraform "$hook"
test "$index" = "$(git write-tree)"
test "$worktree" = "$(sha256sum main.tf)"
