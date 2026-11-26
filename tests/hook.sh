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

if [[ $engine == terraform ]]; then
  git checkout-index -f -- "$file"
  for extension in tfmock.hcl tfquery.hcl; do
    staged="example.$extension"
    printf 'fixture="synthetic"\n' > "$staged"
    git add -- "$staged"
    if "$engine" fmt -check -recursive > "$scratch/native.log"; then
      printf 'Native fmt did not check %s.\n' "$staged" >&2
      exit 1
    fi
    grep -Fx -- "$staged" "$scratch/native.log"
    if TERRAFORM_CI_CHECK="$repo/scripts/check.sh" TERRAFORM_CI_ENGINE="$engine" "$hook" > "$scratch/hook.log" 2>&1; then
      printf 'Staged bad formatting passed for %s.\n' "$staged" >&2
      exit 1
    fi
    grep -Fx -- "$staged" "$scratch/hook.log"
    git rm -q -f -- "$staged"
  done
fi

printf 'output "broken" {\n' > broken.tf
status=0
NO_COLOR=0 TERRAFORM_CI_ENGINE="$engine" \
  "$repo/scripts/check.sh" format broken.tf > "$scratch/format.log" 2>&1 || status=$?
test "$status" -ne 0
grep -F 'Formatting failed.' "$scratch/format.log"
if grep -q $'\e' "$scratch/format.log"; then
  printf '%s\n' 'Redirected diagnostics contain ANSI escape sequences.' >&2
  exit 1
fi
