#!/usr/bin/env bash
set -euo pipefail

fail() { printf '%s\n' "$*" >&2; exit 1; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
engine=${TERRAFORM_CI_ENGINE:-}
case "$engine" in
  terraform|tofu) ;;
  *) fail 'engine must be terraform or tofu.' ;;
esac
engine_bin=$(type -P "$engine") || fail "Required tool is missing: $engine"
mode=${1:-check}
case "$mode" in
  check) [[ $# -eq 0 ]] || fail 'Unexpected check arguments.' ;;
  format) shift; [[ $# -gt 0 ]] || fail 'Supply at least one file to format.' ;;
  *) fail "Unknown check mode: $mode" ;;
esac
requested=${TERRAFORM_CI_ENGINE_VERSION:-}
[[ $mode == format || -n $requested ]] || fail 'engine-version is required.'
IFS=$'\t' read -r engine_version _ <<< "$("$script_dir/setup.sh" pin "$engine" "$requested")"
[[ -n $engine_version ]] || fail 'Unsupported engine version or missing pin.'

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/home" "$scratch/tmp"
: > "$scratch/terraform.rc"
tool_path="$(dirname -- "$engine_bin"):/usr/bin:/bin"
run() {
  env -i PATH="$tool_path" HOME="$scratch/home" TMPDIR="$scratch/tmp" LC_ALL=C \
    TF_IN_AUTOMATION=1 TF_DATA_DIR="$scratch/engine" TF_CLI_CONFIG_FILE="$scratch/terraform.rc" "$@"
}
installed=$(run "$engine_bin" version -json | jq -er .terraform_version)
[[ $installed == "$engine_version" ]] || fail "$engine $engine_version is required, found $installed."
check_format() { run "$engine_bin" fmt -check "$@" || fail 'Formatting failed.'; }
if [[ $mode == format ]]; then
  check_format "$@"
  exit 0
fi

workspace=$(realpath -e -- "${TERRAFORM_CI_WORKSPACE:-${GITHUB_WORKSPACE:-.}}")
[[ $(git -C "$workspace" rev-parse --show-toplevel) == "$workspace" ]] || fail 'Use the checkout root as workspace.'
working_directory=${TERRAFORM_CI_WORKING_DIRECTORY:-.}
[[ $working_directory != /* ]] || fail 'working-directory must be checkout-relative.'
root=$(realpath -m -- "$workspace/$working_directory")
case "$root" in
  "$workspace"|"$workspace"/*) ;;
  *) fail 'working-directory escapes the checkout.' ;;
esac
relative=$(realpath --relative-to="$workspace" -- "$root")
root_kind=${TERRAFORM_CI_ROOT_KIND:-deployable}
case "$root_kind" in
  deployable|module) ;;
  *) fail 'root-kind must be deployable or module.' ;;
esac

tree=$scratch/tree
mkdir -p "$tree"
git -C "$workspace" ls-files --cached --deduplicate -z |
  tar -cf "$scratch/source.tar" -C "$workspace" --no-recursion --null -T -
tar -xf "$scratch/source.tar" -C "$tree"
while IFS= read -r -d '' link; do
  resolved=$(realpath -m -- "$link")
  case "$resolved" in
    "$tree"/*) ;;
    *) fail "Tracked symlink escapes the checkout: ${link#"$tree/"}" ;;
  esac
done < <(find "$tree" -type l -print0)
root="$tree/$relative"
shopt -s nullglob
sources=("$root"/*.tf "$root"/*.tf.json)
if [[ $engine == tofu ]]; then sources+=("$root"/*.tofu "$root"/*.tofu.json); fi
has_sources=false
for source in "${sources[@]}"; do
  if [[ -f $source ]]; then has_sources=true; break; fi
done
[[ $has_sources == true ]] || fail 'No Terraform configuration in working-directory.'

init_flags=(-backend=false -input=false -no-color)
if [[ $root_kind == deployable ]]; then
  [[ -f $root/.terraform.lock.hcl ]] && git -C "$workspace" cat-file -e "HEAD:$relative/.terraform.lock.hcl" 2>/dev/null || fail 'A deployable root needs a committed .terraform.lock.hcl.'
  init_flags+=(-lockfile=readonly)
fi

lint_bin=$(type -P tflint) || fail 'Required tool is missing: tflint'
scan_bin=$(type -P trivy) || fail 'Required tool is missing: trivy'
tool_path="$(dirname -- "$lint_bin"):$(dirname -- "$scan_bin"):$tool_path"
IFS=$'\t' read -r lint_version _ <<< "$("$script_dir/setup.sh" pin tflint)"
IFS=$'\t' read -r scan_version _ <<< "$("$script_dir/setup.sh" pin trivy)"
[[ $(run "$lint_bin" --version | sed -n '1p') == "TFLint version $lint_version" ]] || fail "TFLint $lint_version is required."
[[ $(run "$scan_bin" --version | sed -n '1p') == "Version: $scan_version" ]] || fail "Trivy $scan_version is required."

config=$script_dir/tflint.hcl
if [[ -n ${TERRAFORM_CI_TFLINT_CONFIG:-} ]]; then
  [[ $TERRAFORM_CI_TFLINT_CONFIG != /* ]] || fail 'tflint-config must be checkout-relative.'
  config=$(realpath -e -- "$root/$TERRAFORM_CI_TFLINT_CONFIG") || fail 'Missing tflint-config.'
  [[ $config == "$tree/"* && -f $config ]] || fail 'tflint-config escapes the checkout or is not a file.'
fi
printf '{}\n' > "$scratch/trivy.yaml"
cd -- "$root"
check_format -recursive
run "$engine_bin" init "${init_flags[@]}" || fail 'Initialization failed.'
run "$engine_bin" validate -no-color || fail 'Validation failed.'
# Analyze the selected engine's view. TFLint reads .tf and .tf.json only.
find "$tree" \( -type f -o -type l \) \( -name '*.tofu' -o -name '*.tofu.json' \) -print0 > "$scratch/tofu-sources"
while IFS= read -r -d '' source; do
  if [[ $engine == tofu ]]; then
    case "$source" in
      *.tofu.json) target=${source%.tofu.json}.tf.json ;;
      *.tofu) target=${source%.tofu}.tf ;;
    esac
    cp -L -- "$source" "$scratch/projected"
    mv -fT -- "$scratch/projected" "$target"
  fi
  rm -- "$source"
done < "$scratch/tofu-sources"
run "$lint_bin" --config="$config" --init || fail 'TFLint plugin initialization failed.'
run "$lint_bin" --config="$config" --format=compact || fail 'TFLint failed.'
run "$scan_bin" config --config "$scratch/trivy.yaml" --cache-dir "$scratch/trivy-cache" \
  --misconfig-scanners terraform --skip-check-update --skip-version-check --disable-telemetry \
  --exit-code 1 --format table . || fail 'Trivy policy check failed.'
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  printf 'engine-version=%s\ntflint-version=%s\ntrivy-version=%s\n' "$engine_version" "$lint_version" "$scan_version" >> "$GITHUB_OUTPUT"
fi
