#!/usr/bin/env bash
# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0
#
# changelog.sh — Prepend a version section to CHANGELOG.md from the commit
# subjects since the most recent tag, mirroring the PaveDB changelog format.
#
# Usage:
#   scripts/changelog.sh <VERSION>            # write CHANGELOG.md
#   CHANGELOG_PATH=- scripts/changelog.sh X   # preview on stdout, no write
#
# Commit subjects are grouped by their leading [tag], which is stripped from
# the bullet. Subjects without a tag, and chore commits, are skipped.

set -euo pipefail

VERSION="${1:-}"
if [[ -z $VERSION ]]; then
  echo "usage: scripts/changelog.sh <VERSION>" >&2
  exit 2
fi

CHANGELOG_PATH="${CHANGELOG_PATH:-CHANGELOG.md}"
HEADER='<!-- (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com> -->
<!-- SPDX-License-Identifier: Apache-2.0 -->'

# Anchor on the newest tag; without one, take the whole history.
last_tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if [[ -n $last_tag ]]; then
  range="${last_tag}..HEAD"
else
  range="HEAD"
fi

# tag -> section title. Anything else keeps its own tag, capitalised.
section_of() {
  case "${1,,}" in
    doc | docs) echo "Documentation" ;;
    sdk) echo "SDK" ;;
    infra) echo "Infrastructure" ;;
    fix) echo "Bug Fixes" ;;
    test) echo "Testing" ;;
    perf) echo "Performance" ;;
    pkg) echo "Packaging" ;;
    *) echo "${1^}" ;;
  esac
}

entries="$(git log --reverse --format=%s "$range")"

declare -A groups=()
declare -a order=()

while IFS= read -r subject; do
  [[ -z $subject ]] && continue
  [[ ${subject,,} == chore* ]] && continue
  [[ $subject != \[* ]] && continue

  tag="${subject%%\]*}"
  tag="${tag#\[}"
  bullet="${subject#*\]}"
  bullet="${bullet# }"
  [[ -z $bullet ]] && continue

  # Crop overlong subjects the way the core changelog does.
  if ((${#bullet} > 80)); then
    bullet="${bullet:0:77}..."
  fi
  bullet="${bullet^}"

  section="$(section_of "$tag")"
  if [[ -z ${groups[$section]:-} ]]; then
    order+=("$section")
  fi
  # Skip a bullet already recorded in this section.
  if [[ $'\n'"${groups[$section]:-}" == *$'\n'"- $bullet"$'\n'* ]]; then
    continue
  fi
  groups[$section]+="- $bullet"$'\n'
done <<<"$entries"

if ((${#order[@]} == 0)); then
  echo "no tagged commits in $range" >&2
  exit 1
fi

# Largest section first, then alphabetical, matching the core changelog.
mapfile -t sorted < <(
  for section in "${order[@]}"; do
    count="$(grep -c '^- ' <<<"${groups[$section]}")"
    printf '%s\t%s\n' "$count" "$section"
  done | sort -k1,1nr -k2,2f | cut -f2
)

entry="## ${VERSION} — $(date +%F)"$'\n'
for section in "${sorted[@]}"; do
  entry+=$'\n'"### ${section}"$'\n'"${groups[$section]}"
done
entry+=$'\n'"---"$'\n'

if [[ $CHANGELOG_PATH == "-" ]]; then
  printf '%s' "$entry"
  exit 0
fi

if [[ -f $CHANGELOG_PATH ]]; then
  body="$(tail -n +3 "$CHANGELOG_PATH")"
else
  body=""
fi

# Regenerating a version that is not tagged yet replaces its entry rather than
# stacking a second one.
if [[ -n $body ]]; then
  body="$(awk -v marker="## ${VERSION} — " '
    BEGIN { skipping = 0; done = 0 }
    !done && index($0, marker) == 1 { skipping = 1; done = 1; next }
    skipping && $0 == "---" { skipping = 0; next }
    !skipping { print }
  ' <<<"$body")"
fi

{
  printf '%s\n\n' "$HEADER"
  printf '%s' "$entry"
  if [[ -n ${body//[$'\n' ]/} ]]; then
    printf '%s\n' "$body"
  fi
} >"${CHANGELOG_PATH}.tmp"

mv "${CHANGELOG_PATH}.tmp" "$CHANGELOG_PATH"
printf '%s' "$entry"
