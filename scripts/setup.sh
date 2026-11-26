#!/usr/bin/env bash
set -euo pipefail

fail() { printf '%s\n' "$*" >&2; exit 1; }

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mode=${1:-}
tool=${2:-}
version=${3:-}
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail 'Supported platform: Linux x64.'

case "$tool" in
  tofu) manifest_name=opentofu ;;
  terraform|tflint|trivy) manifest_name=$tool ;;
  *) fail "Unsupported tool: $tool" ;;
esac

supported_version=$(awk -v name="$manifest_name" '$1 == name { print $2 }' "$script_dir/.tool-versions")
[[ $supported_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Missing or invalid tool pin: $tool"
version=${version:-$supported_version}
[[ $version == "$supported_version" ]] || fail "Unsupported $tool version: $version (supported: $supported_version)"

case "$tool" in
  terraform) base_url="https://releases.hashicorp.com/terraform/$version"; asset="terraform_${version}_linux_amd64.zip" ;;
  tofu) base_url="https://github.com/opentofu/opentofu/releases/download/v$version"; asset="tofu_${version}_linux_amd64.zip" ;;
  tflint) base_url="https://github.com/terraform-linters/tflint/releases/download/v$version"; asset=tflint_linux_amd64.zip ;;
  trivy) base_url="https://github.com/aquasecurity/trivy/releases/download/v$version"; asset="trivy_${version}_Linux-64bit.tar.gz" ;;
esac
extension=zip
[[ $asset == *.zip ]] || extension=tar.gz
checksum_for() {
  local checksum
  checksum=$(awk -v file="$tool-$version.$1" '$2 == file { print $1 }' "$script_dir/checksums.sha256")
  [[ $checksum =~ ^[0-9a-f]{64}$ ]] || fail "Missing or invalid checksum for $tool $version ($1)."
  printf '%s\n' "$checksum"
}
checksum=$(checksum_for "$extension")

case "$mode" in
  pin) printf '%s\t%s\n' "$version" "$checksum"; exit 0 ;;
  checksums)
    printf '%s\n' "$checksum"
    if [[ $tool == tofu ]]; then checksum_for tar.gz; fi
    exit 0 ;;
  install) ;;
  *) fail 'Usage: setup.sh pin|checksums TOOL [VERSION], or setup.sh install TOOL VERSION DESTINATION [ARCHIVE].' ;;
esac

destination=${4:?Installation destination required}
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
archive=${5:-$scratch/$asset}
if [[ $# -lt 5 ]]; then
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --retry 2 --connect-timeout 15 --max-time 180 --output "$archive" "$base_url/$asset"
fi
actual=$(sha256sum -- "$archive")
[[ ${actual%% *} == "$checksum" ]] || fail "Archive checksum mismatch for $tool $version."
if [[ $extension == zip ]]; then
  unzip -p "$archive" "$tool" > "$scratch/$tool"
else
  tar -xOzf "$archive" "$tool" > "$scratch/$tool"
fi
install -D -m 0755 -- "$scratch/$tool" "$destination/$tool"
