#!/usr/bin/env bash
set -euo pipefail
[[ $COMPOSITE_FAILURE == failure ]]
out=$(mktemp)
trap 'rm -f -- "$out"' EXIT
TERRAFORM_CI_WORKING_DIRECTORY=tests/fixtures/pass GITHUB_OUTPUT="$out" scripts/check.sh
grep -Fx "engine-version=$ACTION_ENGINE_VERSION" "$out"
grep -Fx "tflint-version=$ACTION_TFLINT_VERSION" "$out"
grep -Fx "trivy-version=$ACTION_TRIVY_VERSION" "$out"
if TERRAFORM_CI_WORKING_DIRECTORY=tests/fixtures/fail scripts/check.sh; then
  printf '%s\n' 'The failing fixture passed directly.' >&2
  exit 1
fi
