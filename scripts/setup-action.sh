#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
case "${TERRAFORM_CI_ENGINE:-}" in
  terraform|tofu) ;;
  *) printf '%s\n' 'engine must be terraform or tofu.' >&2; exit 1 ;;
esac
version=${TERRAFORM_CI_ENGINE_VERSION:?engine-version is required.}
"$script_dir/setup.sh" pin "$TERRAFORM_CI_ENGINE" "$version" >/dev/null
tools=$(mktemp -d "${RUNNER_TEMP:?Missing RUNNER_TEMP}/terraform-ci.XXXXXXXX")
if [[ $TERRAFORM_CI_ENGINE == terraform ]]; then
  "$script_dir/setup.sh" install terraform "$version" "$tools"
fi
trivy_version=$("$script_dir/setup.sh" pin trivy | cut -f1)
"$script_dir/setup.sh" install trivy "$trivy_version" "$tools"
printf '%s\n' "$tools" >> "$GITHUB_PATH"
IFS=$'\t' read -r lint_version lint_checksum <<< "$("$script_dir/setup.sh" pin tflint)"
{
  printf 'engine=%s\nengine-version=%s\n' "$TERRAFORM_CI_ENGINE" "$version"
  printf 'tflint-version=%s\ntflint-checksum=%s\n' "$lint_version" "$lint_checksum"
  if [[ $TERRAFORM_CI_ENGINE == tofu ]]; then
    printf 'tofu-checksums<<CHECKSUMS\n'
    "$script_dir/setup.sh" checksums tofu "$version"
    printf 'CHECKSUMS\n'
  fi
} >> "$GITHUB_OUTPUT"
