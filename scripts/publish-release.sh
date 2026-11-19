#!/usr/bin/env bash
# Bind the release to the workflow revision. An existing tag may be annotated.
set -euo pipefail
tag="${1:?release tag required}"
shift
ref="refs/tags/$tag"
git check-ref-format "$ref"
if [[ "$tag" == -* ]]; then
  echo "::error::release tag cannot start with a dash"
  exit 1
fi

remote="${GITHUB_SERVER_URL:?}/${GITHUB_REPOSITORY:?}.git"
refs="$(git ls-remote --tags "$remote" "$ref" "$ref^{}")"
if [[ -z "$refs" ]]; then
  # Create only. A concurrent tag creation fails here and can be inspected on retry.
  gh api --method POST "repos/$GITHUB_REPOSITORY/git/refs" -f "ref=$ref" -f "sha=${GITHUB_SHA:?}" --silent
else
  target="$(awk -v ref="$ref" '$2 == ref {direct=$1} $2 == ref "^{}" {peeled=$1} END {print peeled ? peeled : direct}' <<< "$refs")"
  if [[ "$target" != "${GITHUB_SHA:?}" ]]; then
    echo "::error::release tag $tag does not resolve to the built commit $GITHUB_SHA"
    exit 1
  fi
fi

exec gh release create "$tag" --repo "$GITHUB_REPOSITORY" --verify-tag --target "$GITHUB_SHA" "$@"
