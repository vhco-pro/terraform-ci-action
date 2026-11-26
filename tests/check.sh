#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
engine=${1:?engine required}
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

version=$("$repo/scripts/setup.sh" pin "$engine" | cut -f1)
check() {
  TERRAFORM_CI_WORKSPACE="$scratch/tree" TERRAFORM_CI_ENGINE="$engine" \
    TERRAFORM_CI_ENGINE_VERSION="$version" "$repo/scripts/check.sh" "$@"
}
refuse() {
  local finding=$1
  shift
  if "$@" >"$scratch/result" 2>&1; then
    printf 'Expected failure for %s\n' "$finding" >&2
    return 1
  fi
  grep -F -- "$finding" "$scratch/result" || { cat "$scratch/result"; return 1; }
}
snapshot() {
  (cd "$scratch/tree" && find . -path './.git' -prune -o -type f -print0 | sort -z | xargs -0 sha256sum)
}
make_fixture() {
  mkdir -p "$scratch/tree"
  git -C "$scratch/tree" init -q
  cat > "$scratch/tree/main.tf" <<'HCL'
terraform {
  required_version = ">= 1.0"

  backend "s3" {
    bucket = "vhco-synthetic-fixture"
    key    = "unreachable"
    region = "us-east-1"
  }
}

resource "terraform_data" "fixture" {
  input = "synthetic"
}

output "fixture" {
  value = terraform_data.fixture.input
}
HCL
  printf '# The fixture uses the built-in Terraform provider.\n' > "$scratch/tree/.terraform.lock.hcl"
  git -C "$scratch/tree" add -- main.tf .terraform.lock.hcl
  git -C "$scratch/tree" -c user.name='Synthetic fixture' -c user.email=fixture@example.invalid commit -q -m baseline
}
make_fixture
before=$(snapshot)
check
test "$(snapshot)" = "$before"
test ! -d "$scratch/tree/.terraform"
test ! -e "$scratch/tree/terraform.tfstate"
mkdir "$scratch/tree/docs"
printf '%s\n' 'Unrelated fixture' > "$scratch/tree/docs/note.txt"
git -C "$scratch/tree" add -- docs/note.txt
git -C "$scratch/tree" -c user.name='Synthetic fixture' -c user.email=fixture@example.invalid commit -q -m 'add unrelated note'
rm -- "$scratch/tree/docs/note.txt"
check
test ! -e "$scratch/tree/docs/note.txt"
refuse 'engine must be' env TERRAFORM_CI_WORKSPACE="$scratch/tree" TERRAFORM_CI_ENGINE=invalid TERRAFORM_CI_ENGINE_VERSION="$version" "$repo/scripts/check.sh"
refuse 'Unsupported' env TERRAFORM_CI_WORKSPACE="$scratch/tree" TERRAFORM_CI_ENGINE="$engine" TERRAFORM_CI_ENGINE_VERSION=0.0.1 "$repo/scripts/check.sh"
refuse 'escapes the checkout' env TERRAFORM_CI_WORKING_DIRECTORY=.. TERRAFORM_CI_WORKSPACE="$scratch/tree" TERRAFORM_CI_ENGINE="$engine" TERRAFORM_CI_ENGINE_VERSION="$version" "$repo/scripts/check.sh"

cp "$scratch/tree/main.tf" "$scratch/main.tf"
printf '\noutput "broken" {\nvalue=local.missing\n}\n' >> "$scratch/tree/main.tf"
before=$(snapshot)
refuse 'Formatting failed' check
test "$(snapshot)" = "$before"
cp "$scratch/main.tf" "$scratch/tree/main.tf"
printf '\noutput "broken" {\n  value = local.missing\n}\n' >> "$scratch/tree/main.tf"
refuse 'Reference to undeclared local' check
cp "$scratch/main.tf" "$scratch/tree/main.tf"
printf '\nmodule "missing" {\n  source = "./absent"\n}\n' >> "$scratch/tree/main.tf"
refuse 'Initialization failed' check
cp "$scratch/main.tf" "$scratch/tree/main.tf"
git -C "$scratch/tree" rm -q --cached .terraform.lock.hcl
refuse 'committed .terraform.lock.hcl' check
git -C "$scratch/tree" -c user.name='Synthetic fixture' -c user.email=fixture@example.invalid commit -q -m 'remove lock from HEAD'
git -C "$scratch/tree" add -- .terraform.lock.hcl
refuse 'committed .terraform.lock.hcl' check
git -C "$scratch/tree" -c user.name='Synthetic fixture' -c user.email=fixture@example.invalid commit -q -m 'commit lock'
mkdir "$scratch/tree/empty"
refuse 'No Terraform configuration' env TERRAFORM_CI_WORKING_DIRECTORY=empty TERRAFORM_CI_WORKSPACE="$scratch/tree" TERRAFORM_CI_ENGINE="$engine" TERRAFORM_CI_ENGINE_VERSION="$version" "$repo/scripts/check.sh"

cat >> "$scratch/tree/main.tf" <<'HCL'

variable "fixture_unused" {
  type    = string
  default = "synthetic"
}
HCL
refuse 'terraform_unused_declarations' check
cp "$scratch/main.tf" "$scratch/tree/main.tf"

mkdir -p "$scratch/tree/policy"
cat >"$scratch/tree/policy/main.tf" <<'HCL'
resource "aws_security_group" "fixture" {
  name        = "synthetic"
  description = "Synthetic fixture"

  ingress {
    description = "Synthetic ingress"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/24"]
  }
}
HCL
git -C "$scratch/tree" add -- policy/main.tf
check
sed -i 's#10.0.0.0/24#0.0.0.0/0#' "$scratch/tree/policy/main.tf"
refuse 'AWS-0107' check
grep -F 'policy/main.tf' "$scratch/result"

cp "$scratch/main.tf" "$scratch/tree/main.tf"
git -C "$scratch/tree" rm -q -f -- policy/main.tf
cat > "$scratch/tree/main.tf" <<'HCL'
terraform {
  required_version = ">= 1.0"

  required_providers {
    random = {
      source  = "registry.terraform.io/hashicorp/random"
      version = "3.7.2"
    }
  }
}
HCL
cat > "$scratch/tree/.terraform.lock.hcl" <<'HCL'
provider "registry.terraform.io/hashicorp/random" {
  version     = "3.6.0"
  constraints = "3.6.0"
}
HCL
refuse 'configured version constraint 3.7.2' check
cp "$scratch/main.tf" "$scratch/tree/main.tf"
printf '# Built-in provider only.\n' > "$scratch/tree/.terraform.lock.hcl"

real_engine=$(command -v "$engine")
mkdir "$scratch/observer"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf '[[ ! -v AWS_ACCESS_KEY_ID && $TF_CLI_CONFIG_FILE != /fixture/caller.rc ]] || { printf "Unexpected caller credentials or config" >&2; exit 1; }\n'
  printf 'exec %q "$@"\n' "$real_engine"
} >"$scratch/observer/$engine"
chmod +x "$scratch/observer/$engine"
AWS_ACCESS_KEY_ID=synthetic-sentinel TF_CLI_CONFIG_FILE=/fixture/caller.rc PATH="$scratch/observer:$PATH" check

mkdir -p "$scratch/tree/empty-typed/dir.tf"
printf 'Synthetic metadata\n' > "$scratch/tree/empty-typed/dir.tf/README.md"
git -C "$scratch/tree" add -- empty-typed/dir.tf/README.md
refuse 'No Terraform configuration' env \
  TERRAFORM_CI_WORKING_DIRECTORY=empty-typed TERRAFORM_CI_ROOT_KIND=module \
  TERRAFORM_CI_WORKSPACE="$scratch/tree" TERRAFORM_CI_ENGINE="$engine" \
  TERRAFORM_CI_ENGINE_VERSION="$version" "$repo/scripts/check.sh"
