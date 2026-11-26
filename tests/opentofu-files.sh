#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
cd "$scratch"
git init -q
version=$("$repo/scripts/setup.sh" pin tofu | cut -f1)
check() {
  TERRAFORM_CI_WORKSPACE="$scratch" TERRAFORM_CI_ENGINE=tofu TERRAFORM_CI_ENGINE_VERSION="$version" \
    TERRAFORM_CI_ROOT_KIND=module "$repo/scripts/check.sh"
}
cat >main.tofu <<'HCL'
terraform {
  required_version = ">= 1.8"
}

output "proof" {
  value = "synthetic"
}
HCL
git add -- main.tofu
check
printf '\nvariable "unused" {\n  type    = string\n  default = "synthetic"\n}\n' >>main.tofu
if check >"$scratch/refusal.log" 2>&1; then
  printf '%s\n' 'TFLint missed the OpenTofu-only unused declaration.' >&2
  exit 1
fi
grep -F terraform_unused_declarations "$scratch/refusal.log"
git checkout-index -f -- main.tofu
printf '\noutput "shadowed" {\n  value = local.not_defined\n}\n' >main.tf
git add -- main.tf
check
git rm -q -f -- main.tf main.tofu
printf '%s\n' '{"terraform":{"required_version":">= 1.8"},"output":{"proof":{"value":"synthetic"}}}' >main.tofu.json
git add -- main.tofu.json
check

git rm -q -f -- main.tofu.json
mkdir assets infra
cat > assets/source.tofu <<'HCL'
terraform {
  required_version = ">= 1.8"
}

output "proof" {
  value = "synthetic"
}
HCL
ln -s ../assets/source.tofu infra/main.tofu
git add -- infra/main.tofu assets/source.tofu
TERRAFORM_CI_WORKING_DIRECTORY=infra check
