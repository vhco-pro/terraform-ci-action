#!/usr/bin/env bash
set -euo pipefail
if [[ ${RELEASE_TEST_RESULT:-} != success ]]; then printf 'mode=none\n'; exit 0; fi
case "${GITHUB_EVENT_NAME:-}" in
  push)
    if [[ ${GITHUB_REF:-} == "refs/heads/${RELEASE_DEFAULT_BRANCH:?Missing default branch}" ]]; then
      printf 'mode=version\n'
    else
      printf 'mode=none\n'
    fi
    ;;
  workflow_dispatch)
    ref=${GITHUB_REF:-}
    if [[ ! $ref =~ ^refs/tags/v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
      printf '%s\n' 'Recovery requires an existing exact stable version tag.' >&2
      exit 1
    fi
    tag_commit=$(git rev-parse --verify "$ref^{commit}")
    tested=$(git rev-parse --verify "${GITHUB_SHA:?Missing tested SHA}^{commit}")
    [[ $tag_commit == "$tested" ]] || { printf '%s\n' 'Recovery tag differs from the tested commit.' >&2; exit 1; }
    printf 'mode=recover\ntag=%s\n' "${ref#refs/tags/}"
    ;;
  *) printf 'mode=none\n' ;;
esac
