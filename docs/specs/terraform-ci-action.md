---
status: in-progress
status_description: "Implementation is claimed on the feature branch."
branch: feat/terraform-ci-action
issue: https://github.com/vhco-pro/terraform-ci-action/issues/1
goal: "Consumers can run the same read-only Terraform or OpenTofu checks locally and in GitHub Actions."
covers:
  - action.yml
  - scripts/
  - tests/
  - examples/
  - .github/workflows/
  - README.md
  - LICENSE
---

# Terraform and OpenTofu CI action

## Context

### Owner summary

One action checks an explicitly chosen Terraform or OpenTofu root on Linux x64. The same check script runs with matching local tools. The quick Git hook uses the staged snapshot and leaves provider installation and policy scanning to full verification. Module behavior tests remain caller-owned.

Trivy is the initial policy scanner, with scope proved by a synthetic positive and negative pair. A new provider needs evidence for the controls the consumer relies on. The implementation uses a separate feature branch. Release and consumer rollout need separate approval.

### Background

The shared convention at [4635f7e](https://github.com/vhco-pro/docs/blob/4635f7e12f7a8d9b24046ef943bc382b0d74dff1/conventions/terraform-ansible.md) calls for one set of native commands across local checks and hosted CI. Duplicating workflows would duplicate tool pins and make verdicts drift. A local probe on Linux x64 observed successful backend-free validation and an undeclared-local refusal with Terraform 1.17.2 and OpenTofu 1.13.9. An isolated Trivy 0.70.0 probe passed private SSH ingress and blocked public SSH ingress in a synthetic AWS security group. Those runs establish fixture behavior on the installed tools. They precede verification of the action and installer pins.

## Scope

Deliver one composite, its portable check entry point, native Git hook example, public fixtures and release workflow. Support Ubuntu 24.04 x64 in GitHub Actions and Linux x64 locally. Check both engines on supported pins. Callers choose affected directories and own provider selection and optional plan-only module tests.

Live plan, apply, deployment, private repositories and live provider tests are outside this feature. A consumer that needs an integration test owns its target and approval.

## Design

- Inputs are `working-directory` (default `.`), `engine` (`terraform` or `tofu`, required), `engine-version` (exact verified release, required), `root-kind` (`deployable` by default, or `module`), and optional `tflint-config` (bundled recommended rules if empty). Reject absent required inputs, unsupported pin or platform, empty check scope, and paths resolving outside the checkout. Pass values through environment variables.
- Format with the selected engine, initialize with `-backend=false -input=false`, and validate. Deployable roots explicitly require a committed lockfile and use `-lockfile=readonly`. Initialize both root kinds in run-owned scratch storage with isolated engine data. Preserve relative module paths within the checkout snapshot. Leave the caller's source, lockfile and generated-file state intact on success and failure. Fail if a selected check cannot run.
- Run compiler, provider, linter and scanner children with an allowlisted environment containing the resolved tool paths, isolated HOME and temporary directories. Keep caller CLI configuration and ambient credentials out of the child process. Use local verification for trusted checkouts because providers and lint plugins execute code.
- Install the exact OpenTofu and TFLint binaries via vendor setup actions with verified checksums, or equivalent local verified downloads. Use a verified HashiCorp archive for Terraform and a verified Aqua archive for Trivy. Keep archive pins in updater-readable configuration and version outputs in `GITHUB_OUTPUT`. Return `engine-version`, `tflint-version` and `trivy-version`. Use caller-pinned provider lint plugins where configured.
- Run the Trivy Terraform source scanner with embedded checks and isolated cache. Block findings using the scanner exit code. Prove a known rule fails on the intended synthetic resource and the corrected version passes. Require consumers to map additional provider controls to tested rule IDs before claiming coverage. Keep exceptions control- and resource-specific with a reason and review date.
- Document raw commands in the README. Ship a native hook example for staged formatting, with engine selection supplied by the caller. The hook consumes index content and avoids dependency downloads. The full command and action share the shell check script. Document native mocked plan tests as caller-owned behavior checks.
- A callable fixture workflow runs on Ubuntu 24.04 with read-only contents permission and disabled checkout credential persistence. SHA-pin external actions with release comments. A default-branch push can call the shared GitVersion workflow after the fixtures pass. Pull requests run the fixtures with read-only permissions. Manual recovery accepts only an existing exact stable version tag that resolves to the tested commit. After the same fixture gate, recovery calls the shared GitHub Release action for that exact tag. Serialize publication across push and recovery runs and preserve existing releases.

## Acceptance Criteria

- [x] AC-01: A Linux x64 caller can check a Terraform or OpenTofu root with its selected engine and receive a blocking exit status for malformed or unformatted input, missing required dependencies, or a deployable lockfile failure. It leaves the caller checkout intact.
      Evidence: R-9 confirmed both native engines, worktree preservation and expected refusals.
- [x] AC-02: The check blocks the documented TFLint and Trivy violations and accepts their corrected fixtures.
      Evidence: R-9 confirmed both engines' clean cases and the TFLint and Trivy refusal cases.
- [x] AC-03: The composite reports actual installed tool versions and rejects invalid inputs, escaping paths, missing pins and incorrect artifact checksums. Provider and linter processes receive the isolated environment.
      Evidence: R-9 checked installed versions and output parity in public run 45858390370 and rechecked native setup and input refusals.
- [x] AC-04: The full check and native hook use the same formatter invocation and verdict for selected files. The hook formats in check mode against the index snapshot and leaves source and index intact.
      Evidence: R-9 verified staged parity, index preservation and that the tightened regression fails if either formatter skips the named file.
- [x] AC-05: The repository contains passing and expected-failing public fixture cases, lintable workflows and a release path that requires successful fixtures before tagging.
      Evidence: R-9 confirmed all three jobs in public run 45858390370 and the native lint and release gate fixtures.

## Test Plan

| Criterion | Proof |
| --- | --- |
| AC-01 | Run `tests/check.sh` with both pinned engines using a clean provider-using fixture, a formatting error, an undeclared reference, a lockfile mismatch and an unavailable required local module. Assert the failing stage. Compare the entire caller tree, including generated files, before and after each outcome. |
| AC-02 | Run `tests/check.sh` on paired lint and scanner fixtures. Assert the TFLint diagnostic ID for the selected rule and the Trivy finding ID and source location for the unrestricted ingress fixture. The corrected fixtures exit zero. |
| AC-03 | Run `tests/setup.sh` for the right and wrong digest and `tests/check.sh` for omitted engine, unsupported exact engine version, empty scope and an out-of-checkout path. A fixture child asserts that an exported synthetic credential sentinel and caller CLI configuration are absent. The callable workflow compares each reported version with the installed CLI. |
| AC-04 | Run `tests/hook.sh` in a disposable Git repository with differing index and worktree contents. Stage misformatted HCL and correct the working file to prove the hook blocks. Stage formatted HCL and misformat only the working file to prove the hook allows it. Compare the index and source before and after. |
| AC-05 | Lint workflows and examples with `actionlint`. Test the release gate on synthetic Git refs: default-branch push after passing fixtures and an existing exact stable recovery tag at the tested commit are eligible; PRs, failing fixtures, branches on dispatch, a prerelease tag such as `v1.2.3-rc.1` at the tested commit, and a tag pointing to another commit cannot publish. Hosted fixture evidence remains separate from local checks. |

## Tasks

- [x] T1 `tests/setup.sh`, `tests/check.sh`, `tests/hook.sh`, and `tests/release.sh` specify the commands and refusal cases. See each fail because its entry point is absent (AC-01, AC-02, AC-03, AC-04, AC-05).
      Evidence: Each test reached its missing setup, release, or hook entry point and failed; the check test first reached its missing tool resolver.
- [x] T2 `scripts/setup.sh` and tool pins install and identify verified artifacts. Run `tests/setup.sh` (AC-03).
      Evidence: tests/setup.sh rejected an invalid archive before install and verified the exact Terraform release archive and CLI version.
- [x] T3 `scripts/check.sh` runs the isolated native checks. Run `tests/check.sh` with both engines (AC-01, AC-02, AC-03).
      Evidence: tests/check.sh passed with both pinned engines, including a mismatched lockfile and an isolated child environment.
- [x] T4 `examples/native-hook/` uses the same formatter on index entries. Run `tests/hook.sh` (AC-04).
      Evidence: tests/hook.sh refused malformed staged HCL and accepted clean staged HCL with different worktree content.
- [x] T5 `action.yml`, `.github/workflows/`, and `README.md` wire local checks, fixtures and the release gate. Run `tests/release.sh` and `actionlint`. Observe the composite on a public runner when authorized (AC-03, AC-05).
      Evidence: actionlint, release gate fixtures, setup-action.sh outputs, and direct action fixture comparison passed locally. Hosted composite execution remains pending.

- [x] T6 `scripts/check.sh`, `examples/native-hook/`, and their fixtures enforce a committed lockfile and the selected engine's native source types. Run the two engine checks, both hook cases, and the staged-only lock refusal (AC-01, AC-02, AC-04).

      Evidence: Each regression failed before the fix. Both engine suites, both hooks, OpenTofu-only HCL/JSON with source precedence, the release guard and actionlint passed after the fix.

- [x] T7 `scripts/check.sh` and `tests/check.sh` reject roots that contain directories with configuration suffixes but no configuration files. Run both engine suites (AC-01).
      Evidence: The .tf-named directory fixture first passed an empty root incorrectly. Both native suites reject it after checking that a source is a file.

- [x] T8 `scripts/check.sh`, the native hook and their fixtures handle worktree deletions, internal OpenTofu symlinks and Terraform formatter file types. Verify plain diagnostics and read the setup test's version from the manifest (AC-01, AC-03, AC-04).
      Evidence: The deletion, symlink, staged mock format and redirected diagnostics regressions first failed against the prior code. Both engines' native check and hook suites, OpenTofu file cases, Terraform setup, release fixtures and actionlint passed after the fixes.

## Open Questions

None.

## Review Log

| Date | Review | Kind | Commit | Model | Isolation | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-11-26 | R-1 | spec | `3c8f33420365fb05c5795c7dc22404434aa480f3` | unknown | procedural | Child tool isolation and release recovery require explicit proof. |
| 2026-11-26 | R-2 | spec | `ccb3e91a5cab5f4a0ddec8371a85e63ff6d7d1ba` | unknown | procedural | Add a prerelease-tag refusal case. |
| 2026-11-26 | R-3 | spec | `7fde52a105f0fa1401f5c8bf35ad75ce162183a2` | unknown | procedural | No findings. |
| 2026-11-26 | R-3 | spec | `7fde52a105f0fa1401f5c8bf35ad75ce162183a2` | n/a | n/a | accepted by owner |
| 2026-11-26 | R-4 | implementation | `9d975469a76a271a9834c0505046b9b326b4d3f1` | unknown | procedural | OpenTofu file discovery and committed-lockfile enforcement need fixes. |
| 2026-11-26 | R-5 | implementation | `75b3f077ccb1d2b2aff315515b22d562265e0890` | unknown | procedural | Native findings resolved. Hosted checks pending. |
| 2026-11-26 | R-6 | implementation | `b3cc69cf602f7c55070e97aec499bf4ab817cac9` | unknown | procedural | Native criteria met. Hosted execution pending. |
| 2026-11-26 | R-7 | implementation | `be39185bc301c7ab26f889a85097b998663a56b5` | unknown | procedural | Hosted fixtures passed. Worktree snapshots and hook formatting need fixes. |
| 2026-11-26 | R-8 | implementation | `863b523fb0dc6cf99f71c83e8f80138dd9061c7e` | unknown | procedural | All five criteria met. Tighten the formatter regression’s assertion. |
| 2026-11-26 | R-9 | implementation | `eb1b4b1f79828eacc2ac0cda024e175174c58d99` | unknown | procedural | All five criteria met. |
| 2026-11-26 | R-10 | implementation | `6622432a030331c4e0eedc49669e21be26c47ab7` | unknown | procedural | All five criteria met with the new OpenTofu pin and hosted fixture matrix. |
| 2026-11-26 | R-11 | implementation | `f19ddf9a11f58994e053622622171c2dc7f29691` | unknown | procedural | All five criteria met. The Scorecard provider enforces the exact publication ref. |
| 2026-11-26 | R-12 | implementation | `0b3f8779d92cbc1ba00611cf7a0f717f962c6941` | unknown | procedural | All criteria met with the released CodeQL pin. |

### R-1

FINDING: F-01
KIND: factual
SEVERITY: blocking
WHERE: Context owner summary, Scope, Design lines 38-43, Acceptance Criteria AC-01 and AC-03, Test Plan AC-01 and AC-03
EVIDENCE: Design lets the checkout select provider and TFLint plugin code. It constrains input paths but does not constrain the environment inherited by that code when the shell entry point runs locally. Backend-free initialization does not prevent a provider or plugin process from reading credentials already exported by the caller. The pinned coding convention at lines 95-97 requires an explicit allowlisted environment for processes running user-supplied code.
PROPOSAL: Specify a minimal child environment and isolated tool configuration for both entry points. Add a local fixture that proves a credential-shaped sentinel in the caller environment is absent from the child, and state which checkouts users may safely verify locally.

FINDING: F-02
KIND: factual
SEVERITY: should-fix
WHERE: Context owner summary, Design line 39, Acceptance Criteria AC-01, Test Plan AC-01
EVIDENCE: Design places module initialization in temporary storage but says nothing equivalent for deployable roots. Terraform's CLI environment reference says initialized working-directory data goes into .terraform unless TF_DATA_DIR is set. The AC-01 proof compares tracked inputs only, so generated files in the caller checkout could pass the proof.
PROPOSAL: Put initialization data for both root kinds in run-owned scratch space while preserving relative module paths. Verify that a provider-using fixture leaves no new files in the caller checkout, including on failure.

FINDING: F-03
KIND: factual
SEVERITY: should-fix
WHERE: Design line 43, Acceptance Criteria AC-05, Test Plan AC-05
EVIDENCE: Pinned GitHub Actions conventions at lines 117-119 require dispatch of an existing exact tag and validation of that tag. The selected shared workflow accepts only runs-on and dry-run and derives its tag from GitVersion. The design requires safe retries but leaves exact-tag validation, ref selection and recovery outside the release proof.
PROPOSAL: Specify which events can start a release and how the caller validates an exact recovery tag and its commit before any write. Prove that an authorized existing tag can recover and that an invalid or disallowed ref refuses.

FINDING: F-04
KIND: factual
SEVERITY: should-fix
WHERE: Context owner summary, Design line 42, Acceptance Criteria AC-04, Test Plan AC-04
EVIDENCE: The design limits the hook to formatting, but AC-04 says the full command and hook share the check behavior. The proof does not name the violation used in the staged and unstaged cases. An implementer could duplicate formatter invocation or interpret AC-04 as requiring full scans during a commit.
PROPOSAL: State that the hook shares the full check's formatter invocation and verdict for the staged inputs. Use a formatting-only violation in both index and worktree cases.

FINDING: F-05
KIND: factual
SEVERITY: should-fix
WHERE: Acceptance Criteria AC-01 and AC-03, Test Plan AC-01 and AC-03
EVIDENCE: AC-01 requires a missing-dependency refusal, and AC-03 requires a missing-pin refusal. The AC-01 row lists formatting, validation and lockfile fixtures, while AC-03 lists omitted engine, empty scope, escaping paths and digest cases. Neither row requires a missing dependency or an exact version with no verified pin. An omitted engine or a corrupt checksum does not exercise either path.
PROPOSAL: Add a fixture with an unavailable required dependency and a separate input with an exact unsupported engine version. Require each to fail at its intended check.

### R-2

FINDING: F-01
KIND: factual
SEVERITY: should-fix
WHERE: Design line 44, Test Plan AC-05
EVIDENCE: The revised design permits recovery only for an exact stable version tag. The revised proof rejects branches and tags that point to another commit, but every case could pass if recovery accepted a prerelease tag pointing to the tested commit.
PROPOSAL: Add a recovery case for a tag such as v1.2.3-rc.1 that points to the tested commit. Require it to refuse publication while the stable tag v1.2.3 remains eligible.

### R-3

NO FINDINGS

### R-4

CRITERION: AC-01 A Linux x64 caller can check a Terraform or OpenTofu root with its selected engine and receive a blocking exit status for malformed or unformatted input, missing required dependencies, or a deployable lockfile failure. It leaves the caller checkout intact.
VERDICT: not met
EVIDENCE: Both native suites passed from a temporary export of 9d975469a76a271a9834c0505046b9b326b4d3f1. Additional fixtures showed that the wrapper rejected a valid root containing only main.tofu and accepted a deployable root whose lockfile was staged but absent from HEAD.

CRITERION: AC-02 The check blocks the documented TFLint and Trivy violations and accepts their corrected fixtures.
VERDICT: met
EVIDENCE: `tests/check.sh terraform` and `tests/check.sh tofu` passed from the exact-commit export. Both engines accepted the corrected fixtures and blocked `terraform_unused_declarations` and `AWS-0107`. Trivy identified `policy/main.tf` as the source of the policy violation.

CRITERION: AC-03 The composite reports actual installed tool versions and rejects invalid inputs, escaping paths, missing pins and incorrect artifact checksums. Provider and linter processes receive the isolated environment.
VERDICT: not verified
EVIDENCE: The exact-commit native suites rejected invalid engine input, an escaping working directory, an unsupported engine version and an incorrect archive checksum. The synthetic child did not receive the caller credential sentinel or CLI configuration. The direct script reported the expected versions for both engines. The hosted composite step and its outputs were not observed.

CRITERION: AC-04 The full check and native hook use the same formatter invocation and verdict for selected files. The hook formats in check mode against the index snapshot and leaves source and index intact.
VERDICT: not met
EVIDENCE: `tests/hook.sh` passed from the exact-commit export. A separate disposable index containing misformatted `main.tofu` passed the hook with exit 0 while the pinned `tofu fmt -check main.tofu` returned 3 for the same file.

CRITERION: AC-05 The repository contains passing and expected-failing public fixture cases, lintable workflows and a release path that requires successful fixtures before tagging.
VERDICT: not verified
EVIDENCE: The public fixture files passed and failed as expected through the native script with both engines. `actionlint` and `tests/release.sh` passed from the exact-commit export. The release jobs depend on the callable fixture workflow through the gate job. The hosted fixture outcome was not observed.

FINDING: F-01
KIND: factual
SEVERITY: blocking
WHERE: scripts/check.sh:70-71, tests/check.sh, AC-01
EVIDENCE: `scripts/check.sh` identifies configuration only through `.tf` and `.tf.json` files. A disposable OpenTofu module containing only a well-formatted `main.tofu` exited 1 with `No Terraform configuration in working-directory.` The pinned OpenTofu engine initialized and validated the same module successfully. OpenTofu supports `.tofu` and `.tofu.json` configuration files.
PROPOSAL: Discover configuration files according to the selected engine. Add an OpenTofu-only fixture that reaches formatting, validation, linting and policy scanning.

FINDING: F-02
KIND: factual
SEVERITY: should-fix
WHERE: examples/native-hook/.githooks/pre-commit:17, tests/hook.sh, AC-04
EVIDENCE: The hook excludes `.tofu` and `.tofutest.hcl`, which the pinned OpenTofu formatter checks. In a disposable repository the hook exited 0 for staged misformatted `main.tofu`, while `tofu fmt -check main.tofu` exited 3.
PROPOSAL: Select staged format candidates using the chosen engine's supported extensions. Exercise both the staged refusal and unstaged allowance with an OpenTofu-specific file.

FINDING: F-03
KIND: factual
SEVERITY: should-fix
WHERE: scripts/check.sh:58-59 and 74-76, tests/check.sh:25-49, README.md:23-25, AC-01
EVIDENCE: The guard checks for a lockfile in the snapshot of indexed paths. A disposable deployable root passed after staging `.terraform.lock.hcl` even though `HEAD` did not contain it. The design explicitly requires a committed lockfile, and the current positive fixture never commits its lockfile.
PROPOSAL: Enforce the committed-lockfile contract for deployable roots and align the README. Commit the positive fixture's lockfile and add a refusal case for a staged-only lockfile.

### R-5

CRITERION: AC-01 A Linux x64 caller can check a Terraform or OpenTofu root with its selected engine and receive a blocking exit status for malformed or unformatted input, missing required dependencies, or a deployable lockfile failure. It leaves the caller checkout intact.
VERDICT: met
EVIDENCE: `tests/check.sh terraform`, `tests/check.sh tofu` and `tests/opentofu-files.sh` passed in temporary exports of `75b3f077ccb1d2b2aff315515b22d562265e0890`. Both engines refused a staged-only lockfile, a conflicting provider version, an unavailable local module, invalid configuration and bad formatting. The checkout-preservation checks passed. OpenTofu-only HCL and JSON roots passed.

CRITERION: AC-02 The check blocks the documented TFLint and Trivy violations and accepts their corrected fixtures.
VERDICT: met
EVIDENCE: Both native check suites at the exact commit accepted corrected fixtures and blocked `terraform_unused_declarations` and `AWS-0107`. Trivy attributed the AWS finding to `policy/main.tf`. The OpenTofu file suite also detected an unused declaration in an OpenTofu-only module.

CRITERION: AC-03 The composite reports actual installed tool versions and rejects invalid inputs, escaping paths, missing pins and incorrect artifact checksums. Provider and linter processes receive the isolated environment.
VERDICT: not verified
EVIDENCE: Exact-commit native suites refused invalid inputs, an escaping path, an unsupported pin and a wrong archive checksum. The synthetic child confirmed the credential sentinel and caller CLI configuration were absent. Both fixture runs reported the expected installed versions through the direct script. Hosted composite execution and its output parity were not observed.

CRITERION: AC-04 The full check and native hook use the same formatter invocation and verdict for selected files. The hook formats in check mode against the index snapshot and leaves source and index intact.
VERDICT: met
EVIDENCE: `tests/hook.sh terraform` and `tests/hook.sh tofu` passed from the exact commit. Each blocked staged bad formatting and allowed a clean index with bad formatting only in the working file. The index and working file were preserved in both cases.

CRITERION: AC-05 The repository contains passing and expected-failing public fixture cases, lintable workflows and a release path that requires successful fixtures before tagging.
VERDICT: not verified
EVIDENCE: At the exact commit, both engines passed and failed the public fixture files as intended through the direct script. `actionlint` and `tests/release.sh` passed. Both publication jobs depend on the callable fixture workflow through the release gate. Hosted fixture execution was not observed.

### R-6

CRITERION: AC-01 A Linux x64 caller can check a Terraform or OpenTofu root with its selected engine and receive a blocking exit status for malformed or unformatted input, missing required dependencies, or a deployable lockfile failure. It leaves the caller checkout intact.
VERDICT: met
EVIDENCE: `tests/check.sh terraform`, `tests/check.sh tofu` and `tests/opentofu-files.sh` passed in temporary exports of `b3cc69cf602f7c55070e97aec499bf4ab817cac9`. Both engine suites verified checkout preservation and refused malformed configuration, bad formatting, an unavailable module, lockfile failures and a root whose only matching name was a directory. OpenTofu-only HCL and JSON roots passed.

CRITERION: AC-02 The check blocks the documented TFLint and Trivy violations and accepts their corrected fixtures.
VERDICT: met
EVIDENCE: Both native suites at the exact commit accepted corrected fixtures and blocked `terraform_unused_declarations` and `AWS-0107`. Trivy identified `policy/main.tf` as the source of the policy violation. The OpenTofu file suite also blocked an unused declaration in an OpenTofu-only root.

CRITERION: AC-03 The composite reports actual installed tool versions and rejects invalid inputs, escaping paths, missing pins and incorrect artifact checksums. Provider and linter processes receive the isolated environment.
VERDICT: not verified
EVIDENCE: Native input, scope, path, pin, checksum and child-environment fixtures passed at the exact commit. The direct entry point reported the expected installed versions for both engines. Hosted composite execution and its output parity remain unobserved.

CRITERION: AC-04 The full check and native hook use the same formatter invocation and verdict for selected files. The hook formats in check mode against the index snapshot and leaves source and index intact.
VERDICT: met
EVIDENCE: `tests/hook.sh terraform` and `tests/hook.sh tofu` passed at the exact commit. Each blocked bad formatting in the index, allowed a clean index with bad formatting only in the working file, and preserved both the index and working file.

CRITERION: AC-05 The repository contains passing and expected-failing public fixture cases, lintable workflows and a release path that requires successful fixtures before tagging.
VERDICT: not verified
EVIDENCE: Both engines passed and failed the public fixture files as intended through the direct entry point at the exact commit. `actionlint` and `tests/release.sh` passed. The publication jobs depend on the callable fixture workflow through the gate job. Hosted fixture execution remains unobserved.

### R-7

CRITERION: AC-01 A Linux x64 caller can check a Terraform or OpenTofu root with its selected engine and receive a blocking exit status for malformed or unformatted input, missing required dependencies, or a deployable lockfile failure. It leaves the caller checkout intact.
VERDICT: not met
EVIDENCE: The exact-commit native suites passed on both engines, including malformed and unformatted files, a missing module, lockfile refusals, and checkout preservation. In a separate disposable checkout, the same valid Terraform root passed before an unrelated tracked file was removed from the worktree. After that removal the full check exited 2 before reaching the selected root. A separate valid OpenTofu root using an internal symlink initialized and validated, then failed during source projection.

CRITERION: AC-02 The check blocks the documented TFLint and Trivy violations and accepts their corrected fixtures.
VERDICT: met
EVIDENCE: tests/check.sh terraform and tests/check.sh tofu passed from a temporary export of be39185bc301c7ab26f889a85097b998663a56b5. Each accepted the corrected fixtures, refused terraform_unused_declarations, and attributed AWS-0107 to policy/main.tf. tests/opentofu-files.sh also refused an unused declaration in an OpenTofu-only root.

CRITERION: AC-03 The composite reports actual installed tool versions and rejects invalid inputs, escaping paths, missing pins and incorrect artifact checksums. Provider and linter processes receive the isolated environment.
VERDICT: met
EVIDENCE: GitHub run 45846043328 checked out be39185bc301c7ab26f889a85097b998663a56b5 in both fixture jobs. Their successful comparison steps reported Terraform 1.17.2 or OpenTofu 1.13.10, TFLint 0.66.0, and Trivy 0.76.2. Native setup and input tests from the exact commit refused the wrong digest, missing engine and version inputs, the unsupported version, an escaping path, and an empty scope. The engine observer and a separate TFLint observer confirmed that the synthetic credential and caller CLI configuration were absent. The same allowlisted runner launches the engine and TFLint plugin paths.

CRITERION: AC-04 The full check and native hook use the same formatter invocation and verdict for selected files. The hook formats in check mode against the index snapshot and leaves source and index intact.
VERDICT: not met
EVIDENCE: Both tests/hook.sh engine runs passed staged and unstaged cases in temporary repositories and preserved the source and index. In two additional disposable Terraform repositories at the exact commit, the hook exited 0 for a misformatted staged .tfmock.hcl or .tfquery.hcl file. The full check exited 1 at formatting for each of those files.

CRITERION: AC-05 The repository contains passing and expected-failing public fixture cases, lintable workflows and a release path that requires successful fixtures before tagging.
VERDICT: met
EVIDENCE: GitHub run 45846043328 checked out be39185bc301c7ab26f889a85097b998663a56b5 in all three jobs. Both engine jobs observed the composite pass and the expected formatting failure, then passed the direct comparison. The workflow lint and release fixture job also passed. Local actionlint and tests/release.sh passed from the exact export. Both publication jobs depend on the gate, which depends on the callable fixture workflow. The shared workflow at its pinned commit runs tag creation after this caller gate. No publishing run was needed to verify the gate.

FINDING: F-01
KIND: factual
SEVERITY: should-fix
WHERE: scripts/check.sh:56-60, README.md:3-6, AC-01
EVIDENCE: The full check passes every cached checkout path to tar. A disposable checkout with a valid selected infra root passed before removal of a tracked notes.txt outside that root, then exited 2 with tar reporting that notes.txt could not be found. The selected root was unchanged.
PROPOSAL: Include tracked worktree files that still exist in the snapshot and retain explicit checks for files the selected root requires. Add a fixture with an unstaged deletion outside the selected root.

FINDING: F-02
KIND: factual
SEVERITY: should-fix
WHERE: examples/native-hook/.githooks/pre-commit:17-20, tests/hook.sh, AC-04
EVIDENCE: The hook's extension filter omits .tfmock.hcl and .tfquery.hcl. With Terraform 1.17.2, the hook exited 0 for each separately staged misformatted file while the full check named the file and exited 1 at formatting.
PROPOSAL: Match the supported formatter file types for the selected engine. Verify staged hook and full-check parity for the two Terraform file types.

FINDING: F-03
KIND: factual
SEVERITY: should-fix
WHERE: scripts/.tool-versions:1, tests/setup.sh:7-17, pinned conventions/delivery.md under Pinning and updates
EVIDENCE: tests/setup.sh duplicates the Terraform version in the managed manifest. In a scratch copy, changing the manifest version and its matching checksum key let the pin resolver return the new version. The setup test immediately refused because it still requested 1.17.2. The delivery convention places tool configuration once next to its owning component.
PROPOSAL: Read Terraform's selected version from the manifest through the existing pin resolver and compare the installed CLI with that version. Continue to require an independently verified digest for every update.

FINDING: F-04
KIND: factual
SEVERITY: should-fix
WHERE: scripts/check.sh:61-67 and 104-115, AC-01
EVIDENCE: A tracked OpenTofu configuration symlink to a regular .tofu file in another directory inside a disposable checkout passed the script's confinement check, initialization and validation. Source projection removed the symlink target before reading the symlink, then exited 1 because the selected configuration could no longer be read.
PROPOSAL: Read the OpenTofu source contents before replacing or removing any source names. Verify that an internal symlink still reaches linting and scanning.

FINDING: F-05
KIND: factual
SEVERITY: should-fix
WHERE: scripts/check.sh:28-34, pinned conventions/terminal-output.md under Colour, streams and interaction
EVIDENCE: In both engines, a malformed file sent through scripts/check.sh format with redirected output and NO_COLOR=0 produced ANSI styling bytes. The terminal standard defaults non-TTY output to plain text and treats a nonempty NO_COLOR value as a request to suppress styling.
PROPOSAL: Configure formatter diagnostics to stay plain in redirected runs and when the caller requests no colour. Check redirected diagnostics from both engine paths.

### R-8

CRITERION: AC-01 A Linux x64 caller can check a Terraform or OpenTofu root with its selected engine and receive a blocking exit status for malformed or unformatted input, missing required dependencies, or a deployable lockfile failure. It leaves the caller checkout intact.
VERDICT: met
EVIDENCE: tests/check.sh passed for Terraform and OpenTofu in an export of 863b523fb0dc6cf99f71c83e8f80138dd9061c7e. Both suites verified checkout preservation and the expected formatting, validation, missing dependency and lockfile refusals. The former failure cases passed in this review. A selected Terraform root completed after an unrelated tracked worktree deletion, and tests/opentofu-files.sh verified that a tracked internal OpenTofu symlink reached linting and scanning.

CRITERION: AC-02 The check blocks the documented TFLint and Trivy violations and accepts their corrected fixtures.
VERDICT: met
EVIDENCE: The two native check suites at 863b523fb0dc6cf99f71c83e8f80138dd9061c7e accepted the corrected fixtures and refused terraform_unused_declarations and AWS-0107. Trivy attributed AWS-0107 to policy/main.tf. tests/opentofu-files.sh also confirmed the lint refusal in an OpenTofu-only root.

CRITERION: AC-03 The composite reports actual installed tool versions and rejects invalid inputs, escaping paths, missing pins and incorrect artifact checksums. Provider and linter processes receive the isolated environment.
VERDICT: met
EVIDENCE: GitHub Test run 45857577399 used 863b523fb0dc6cf99f71c83e8f80138dd9061c7e. Both composite output comparisons matched the installed tools. Terraform was 1.17.2, OpenTofu 1.13.10, TFLint 0.66.0 and Trivy 0.76.2. Exact-commit local checks refused omitted and invalid inputs, unsupported pins, an empty scope, an escaping path and an incorrect digest. The engine and TFLint observers verified that the synthetic caller credential and CLI configuration were absent. The shared native runner applies that environment to the engine and linter child paths.

CRITERION: AC-04 The full check and native hook use the same formatter invocation and verdict for selected files. The hook formats in check mode against the index snapshot and leaves source and index intact.
VERDICT: met
EVIDENCE: Both hook suites at 863b523fb0dc6cf99f71c83e8f80138dd9061c7e passed the staged and unstaged cases and preserved the source and index. In separate fixtures with one violation each, the native hook and full Terraform check named and refused the same misformatted .tfmock.hcl and .tfquery.hcl files. Redirected formatter diagnostics from both engines contained no ANSI control sequences with NO_COLOR unset or set to 0.

CRITERION: AC-05 The repository contains passing and expected-failing public fixture cases, lintable workflows and a release path that requires successful fixtures before tagging.
VERDICT: met
EVIDENCE: All three jobs in GitHub Test run 45857577399 checked out 863b523fb0dc6cf99f71c83e8f80138dd9061c7e and succeeded. The engine logs showed composite success, the intended composite formatting failure and successful comparison with direct execution for both engines. Local actionlint and tests/release.sh passed from the exact export. Both publishing jobs depend on the release gate following the callable fixture workflow. The pinned shared workflow creates the tag after the caller gate.

FINDING: F-01
KIND: factual
SEVERITY: should-fix
WHERE: tests/hook.sh:25 and 32-44, pinned conventions/testing.md under Prove the test catches the defect
EVIDENCE: The new recursive formatter assertion checks only the exit status while the earlier fixture still leaves main.tf misformatted. A control with a correctly formatted .tfmock.hcl file exited 3 and listed only main.tf, so that assertion cannot establish that the formatter checked the mock or query file. Independent isolated local fixtures established that both production paths reach the intended files at this commit.
PROPOSAL: Restore the working copy of main.tf before the extension cases and require the native formatter and hook to name the intended file in their refusal.

### R-9

CRITERION: AC-01 A Linux x64 caller can check a Terraform or OpenTofu root with its selected engine and receive a blocking exit status for malformed or unformatted input, missing required dependencies, or a deployable lockfile failure. It leaves the caller checkout intact.
VERDICT: met
EVIDENCE: tests/check.sh passed for both engines in a temporary export of eb1b4b1f79828eacc2ac0cda024e175174c58d99. The fixtures verified checkout preservation and refused incorrect formatting, invalid configuration, a missing local module, and lockfile failures. A separate selected Terraform root completed with an unrelated tracked worktree deletion. tests/opentofu-files.sh passed an internal symlink through validation, linting and scanning.

CRITERION: AC-02 The check blocks the documented TFLint and Trivy violations and accepts their corrected fixtures.
VERDICT: met
EVIDENCE: Both exact-commit native check suites accepted the corrected fixtures and refused terraform_unused_declarations and AWS-0107. Trivy traced the policy violation to policy/main.tf. The OpenTofu file suite also refused an unused declaration in an OpenTofu-only root.

CRITERION: AC-03 The composite reports actual installed tool versions and rejects invalid inputs, escaping paths, missing pins and incorrect artifact checksums. Provider and linter processes receive the isolated environment.
VERDICT: met
EVIDENCE: The composite comparison steps in GitHub run 45858390370 at eb1b4b1f79828eacc2ac0cda024e175174c58d99 reported and matched Terraform 1.17.2 or OpenTofu 1.13.10, TFLint 0.66.0 and Trivy 0.76.2. Local checks refused omitted and invalid inputs, an unsupported pin, an escaping path, an empty scope and a wrong digest. The engine and TFLint observers confirmed the synthetic caller credential and CLI configuration were absent. The native runner uses that environment for the engine and linter child paths.

CRITERION: AC-04 The full check and native hook use the same formatter invocation and verdict for selected files. The hook formats in check mode against the index snapshot and leaves source and index intact.
VERDICT: met
EVIDENCE: At eb1b4b1f79828eacc2ac0cda024e175174c58d99, each local hook suite passed ten consecutive runs, verifying the staged and unstaged cases and preservation of the source and index. The recursive Terraform formatter and hook each named the intended mock and query files when refusing them. In temporary copies, the regression failed when the hook skipped either file type and when the recursive formatter reported a failure for an unrelated file. The hosted Terraform job also named each intended file in both formatter paths.

CRITERION: AC-05 The repository contains passing and expected-failing public fixture cases, lintable workflows and a release path that requires successful fixtures before tagging.
VERDICT: met
EVIDENCE: All three jobs in GitHub Test run 45858390370 used eb1b4b1f79828eacc2ac0cda024e175174c58d99 and succeeded. Both engine jobs completed the passing composite, observed the intended formatting failure and matched the direct verdicts. Local actionlint and tests/release.sh passed from the exact export. Both publishing jobs depend on the gate after the callable fixture workflow. The pinned shared workflow performs tag creation after that gate.

### R-10

CRITERION: AC-01 A Linux x64 caller can check a Terraform or OpenTofu root with its selected engine and receive a blocking exit status for malformed or unformatted input, missing required dependencies, or a deployable lockfile failure. It leaves the caller checkout intact.
VERDICT: met
EVIDENCE: The local check suites passed from an export of 6622432a030331c4e0eedc49669e21be26c47ab7 on Terraform 1.17.2, OpenTofu 1.13.10 and OpenTofu 1.13.9. Each verified checkout preservation and refused bad formatting, invalid configuration, an unavailable local module and lockfile failures. Both OpenTofu file suites passed, and an independent 1.13.9 run accepted a selected root with an unrelated tracked worktree deletion.

CRITERION: AC-02 The check blocks the documented TFLint and Trivy violations and accepts their corrected fixtures.
VERDICT: met
EVIDENCE: All three local engine variants accepted the corrected fixtures and blocked terraform_unused_declarations and AWS-0107 at 6622432a030331c4e0eedc49669e21be26c47ab7. Trivy traced the policy finding to policy/main.tf. Both OpenTofu file suites also refused an unused declaration in an OpenTofu-only root.

CRITERION: AC-03 The composite reports actual installed tool versions and rejects invalid inputs, escaping paths, missing pins and incorrect artifact checksums. Provider and linter processes receive the isolated environment.
VERDICT: met
EVIDENCE: All three engine jobs in GitHub Test run 45871420211 at 6622432a030331c4e0eedc49669e21be26c47ab7 matched their composite outputs against the installed Terraform 1.17.2, OpenTofu 1.13.10 or OpenTofu 1.13.9 binary, with TFLint 0.66.0 and Trivy 0.76.2. OpenTofu's published 1.13.9 SHA256SUMS matched both committed digests. Both Linux x64 archives verified and contained identical executables, and local setup installed 1.13.9 from the verified ZIP and refused a wrong archive before installation. The local suites and direct probes refused omitted or invalid inputs, an unsupported pin, an empty scope and an escaping path. Engine and linter observers confirmed the synthetic caller credential and CLI configuration were absent.

CRITERION: AC-04 The full check and native hook use the same formatter invocation and verdict for selected files. The hook formats in check mode against the index snapshot and leaves source and index intact.
VERDICT: met
EVIDENCE: Local hook fixtures passed at 6622432a030331c4e0eedc49669e21be26c47ab7 for Terraform 1.17.2 and both OpenTofu versions. They refused misformatted staged content, accepted clean staged content despite misformatted working files and preserved the index and source. The Terraform formatter and hook each named the staged mock and query fixtures in the expected refusals.

CRITERION: AC-05 The repository contains passing and expected-failing public fixture cases, lintable workflows and a release path that requires successful fixtures before tagging.
VERDICT: met
EVIDENCE: All four jobs in GitHub Test run 45871420211 used 6622432a030331c4e0eedc49669e21be26c47ab7 and succeeded. All three composite variants passed the clean fixture, refused the formatting fixture and matched direct execution. Hosted workflow lint, ShellCheck and release guard fixtures passed, and local actionlint and tests/release.sh also passed. Both publishing jobs depend on the gate after the callable fixture workflow. The pinned shared workflow creates the tag after that gate.

### R-11

CRITERION: AC-01 A Linux x64 caller can check a Terraform or OpenTofu root with its selected engine and receive a blocking exit status for malformed or unformatted input, missing required dependencies, or a deployable lockfile failure. It leaves the caller checkout intact.
VERDICT: met
EVIDENCE: In GitHub Test run 45872115226 at f19ddf9a11f58994e053622622171c2dc7f29691, native check suites passed on Terraform 1.17.2 and OpenTofu 1.13.10 and 1.13.9. The suites assert checkout preservation and refuse bad formatting, invalid configuration, an unavailable local module and lockfile failures. Both OpenTofu file suites passed. The previously reviewed native entry points and fixtures are unchanged.

CRITERION: AC-02 The check blocks the documented TFLint and Trivy violations and accepts their corrected fixtures.
VERDICT: met
EVIDENCE: All three exact-commit fixture jobs in run 45872115226 passed the native tests that accept the corrected configurations and refuse terraform_unused_declarations and AWS-0107. The tests assert the policy location policy/main.tf. Both OpenTofu jobs also passed the dedicated file suite that checks the lint refusal in an OpenTofu-only root.

CRITERION: AC-03 The composite reports actual installed tool versions and rejects invalid inputs, escaping paths, missing pins and incorrect artifact checksums. Provider and linter processes receive the isolated environment.
VERDICT: met
EVIDENCE: The three composite comparisons in GitHub run 45872115226 at f19ddf9a11f58994e053622622171c2dc7f29691 matched the installed Terraform 1.17.2 or OpenTofu 1.13.10 or 1.13.9, plus TFLint 0.66.0 and Trivy 0.76.2. The hosted native input, scope, checksum and synthetic child-environment fixtures passed. An exact-export comparison confirmed both 1.13.9 digests still matched the previously verified published SHA256SUMS. The installer and isolated runner are unchanged from the review that verified both artifacts and ran the separate TFLint observer.

CRITERION: AC-04 The full check and native hook use the same formatter invocation and verdict for selected files. The hook formats in check mode against the index snapshot and leaves source and index intact.
VERDICT: met
EVIDENCE: All three hook test steps in GitHub run 45872115226 passed at f19ddf9a11f58994e053622622171c2dc7f29691. They refuse staged bad formatting, accept a clean staged version despite a misformatted worktree file, and compare source and index state. The Terraform case requires both formatter paths to name the intended mock and query files. Neither formatter path nor its tests changed since the independent checks.

CRITERION: AC-05 The repository contains passing and expected-failing public fixture cases, lintable workflows and a release path that requires successful fixtures before tagging.
VERDICT: met
EVIDENCE: GitHub Test run 45872115226 succeeded in all four jobs at f19ddf9a11f58994e053622622171c2dc7f29691. The three composite variants passed the clean fixture, refused the formatting fixture and matched direct execution. Workflow lint, ShellCheck and the release guard passed on the runner. Local actionlint and tests/release.sh passed in an exact export. Both tag and recovery jobs depend on the release gate after the callable fixture workflow. The separate CodeQL run 45872115858 uploaded the exact Actions analysis with zero results.

FINDING: F-01
KIND: factual
SEVERITY: should-fix
WHERE: .github/workflows/scorecard.yml:18-22
EVIDENCE: GitHub Actions string equality ignores case. The caller condition admits a manually selected branch whose name differs from the default branch only by case. A disposable Git repository confirmed that main and MAIN are distinct refs. The pinned upstream Scorecard action checks the full default ref with case-sensitive equality and refuses this invocation before publishing, so the caller runs a job it was intended to skip. [GitHub expression rules](https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#operators), [Pinned Scorecard validation](https://github.com/ossf/scorecard-action/blob/fa7117db83c52d787ae5a89f350999701505d78e/options/options.go)
PROPOSAL: Gate the reusable workflow on a case-sensitive comparison of the fully qualified default ref and cover public default, other branch and tag cases.

### R-12

CRITERION: AC-01 A Linux x64 caller can check a Terraform or OpenTofu root with its selected engine and receive a blocking exit status for malformed or unformatted input, missing required dependencies, or a deployable lockfile failure. It leaves the caller checkout intact.
VERDICT: met
EVIDENCE: GitHub Test run 45877864721 at 0b3f8779d92cbc1ba00611cf7a0f717f962c6941 passed the native check suites on Terraform 1.17.2 and OpenTofu 1.13.10 and 1.13.9. The suites assert checkout preservation and refuse bad formatting, invalid configuration, an unavailable local module and lockfile failures. Both OpenTofu file suites passed. The independently verified native entry points and fixtures are unchanged.

CRITERION: AC-02 The check blocks the documented TFLint and Trivy violations and accepts their corrected fixtures.
VERDICT: met
EVIDENCE: All three exact-commit fixture jobs in run 45877864721 passed the native cases that accept the corrected configurations and refuse terraform_unused_declarations and AWS-0107. The fixtures assert the policy location policy/main.tf. Both OpenTofu file suites also passed the case that refuses an unused declaration in an OpenTofu-only root.

CRITERION: AC-03 The composite reports actual installed tool versions and rejects invalid inputs, escaping paths, missing pins and incorrect artifact checksums. Provider and linter processes receive the isolated environment.
VERDICT: met
EVIDENCE: The three hosted comparison steps in run 45877864721 at 0b3f8779d92cbc1ba00611cf7a0f717f962c6941 reported and matched Terraform 1.17.2 or OpenTofu 1.13.10 or 1.13.9, plus TFLint 0.66.0 and Trivy 0.76.2. Hosted native input, scope, checksum and child-environment fixtures passed. The installer, archive pins and isolated runner are unchanged from the independent review that verified both published OpenTofu 1.13.9 archives, rejected invalid inputs and an incorrect archive, and directly observed the isolated linter process.

CRITERION: AC-04 The full check and native hook use the same formatter invocation and verdict for selected files. The hook formats in check mode against the index snapshot and leaves source and index intact.
VERDICT: met
EVIDENCE: All three hosted hook steps passed at 0b3f8779d92cbc1ba00611cf7a0f717f962c6941. The fixtures require the hook to refuse staged bad formatting, accept clean staged contents despite a bad worktree file and preserve the source and index. The Terraform extension cases require both formatter paths to name the intended mock and query files. The formatter and its fixtures are unchanged since the independent positive and negative checks.

CRITERION: AC-05 The repository contains passing and expected-failing public fixture cases, lintable workflows and a release path that requires successful fixtures before tagging.
VERDICT: met
EVIDENCE: Test run 45877864721 succeeded in all four jobs at 0b3f8779d92cbc1ba00611cf7a0f717f962c6941. Each composite variant passed the clean fixture, refused the formatting fixture and matched direct execution. Hosted workflow lint, ShellCheck and the release guard passed. Local actionlint and tests/release.sh passed in an exact export. The publication jobs depend on the release gate following the callable fixture workflow. The exact CodeQL run 45877865197 used the published v1.2.5 workflow at 119c3c5c884b2b9a6529e741b239eac288942262, logged persist-credentials: false at checkout and uploaded an Actions analysis with zero results.

## Sources

- [Terraform validate](https://developer.hashicorp.com/terraform/cli/commands/validate) and [OpenTofu validate](https://opentofu.org/docs/cli/commands/validate/) document backend-free initialization.
- [TFLint](https://github.com/terraform-linters/tflint) documents rules and plugins. [Trivy Terraform coverage](https://trivy.dev/docs/latest/coverage/iac/terraform/) documents source policy scanning.
- [HashiCorp Terraform style skill](https://github.com/hashicorp/agent-skills/blob/5e30fa5c867ba6777c37e4206babfd08049c396f/plugins/terraform/skills/terraform-style-guide/SKILL.md) applies to HCL. [HashiCorp Terraform test skill](https://github.com/hashicorp/agent-skills/blob/5e30fa5c867ba6777c37e4206babfd08049c396f/plugins/terraform/skills/terraform-test/SKILL.md) and [OpenTofu test](https://opentofu.org/docs/cli/commands/test/) describe plan tests and mocks.
- [PowerShell fixture workflow](https://github.com/vhco-pro/pwsh-ci-action/blob/v0.1.1/.github/workflows/test.yml) demonstrates checking direct and composite verdicts. [GitHub release workflow](https://github.com/vhco-pro/gh-release-workflow/blob/b18de6d2f305f971afe01ba31e17bde5966b1567/.github/workflows/gh-release.yml) owns GitVersion tagging and publication.
