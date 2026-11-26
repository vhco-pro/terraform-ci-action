# Terraform and OpenTofu CI action

Check one root on Linux x64 with its declared engine. The action formats in check
mode, initializes without a backend, validates, runs TFLint and scans the source
with Trivy. It uses a temporary copy of the tracked checkout. Local checks
execute provider and lint plugin code, so run them on trusted checkouts.

## GitHub Actions

Checkout the caller repository with credentials persistence disabled, then call
`vhco-pro/terraform-ci-action` at a full released commit SHA. The
[fixture workflow](.github/workflows/test.yml) exercises the action by path.
Set the workflow job's contents permission to read and use Ubuntu 24.04 x64.

| Input | Default |
| --- | --- |
| `engine` | Required. `terraform` or `tofu`. |
| `engine-version` | Required. Exact version in [the tool pins](scripts/.tool-versions). |
| `working-directory` | `.` within the checkout. |
| `root-kind` | `deployable`. Choose `module` for a reusable module. |
| `tflint-config` | Bundled recommended rules. An override is relative to the checked root. |

Outputs are `engine-version`, `tflint-version`, and `trivy-version`. A deployable
root needs a tracked `.terraform.lock.hcl`. Each caller selects its affected roots,
including dependents when a shared module changes.

## Local check and hook

In a Linux x64 checkout of this action, use Bash, Git, jq, curl, unzip and tar.
Install the selected engine, TFLint and Trivy from the pinned manifest with
`scripts/setup.sh install TOOL VERSION DESTINATION`. Add that destination to
`PATH`. From the caller checkout, run the pinned `scripts/check.sh` with
`TERRAFORM_CI_ENGINE` and `TERRAFORM_CI_ENGINE_VERSION` set. Optional environment
settings match the action inputs as `TERRAFORM_CI_WORKING_DIRECTORY`,
`TERRAFORM_CI_ROOT_KIND`, and `TERRAFORM_CI_TFLINT_CONFIG`.

Copy [the native hook](examples/native-hook/.githooks/pre-commit) to
`.githooks/pre-commit` and set the repo-local `core.hooksPath` to `.githooks`
after checking for existing hooks. Set `TERRAFORM_CI_CHECK` to the pinned
check script and select the engine and directory for the hook. It reads
the staged version of relevant files. Use full verification before pushing.

For diagnosis from a disposable copy, run these native commands with
`engine=terraform` or `engine=tofu`:

```sh
"$engine" fmt -check -recursive
"$engine" init -backend=false -input=false -lockfile=readonly
"$engine" validate
tflint --init
tflint
trivy config --misconfig-scanners terraform --skip-check-update --exit-code 1 .
```

Use `-lockfile=readonly` for deployable roots. Callers can run their own
`terraform test` or `tofu test` on dedicated plan-only fixtures with mocked
providers. Real plans, applies and live provider tests belong to a separate
authorized job.

The public scanner fixture covers AWS SSH ingress only (AWS-0107).
Prove rule coverage for the providers and controls you rely on. Use
resource-specific exceptions with a reason and review date.

## Maintainer checks

Run `tests/setup.sh`, `tests/check.sh terraform`, `tests/check.sh tofu`,
`tests/hook.sh`, `tests/release.sh`, and `actionlint`. Update archive digests
from upstream release metadata when changing the versions. A version change
without a matching digest fails setup.
