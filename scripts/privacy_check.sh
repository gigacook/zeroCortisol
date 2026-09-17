#!/usr/bin/env bash
# Pre-push privacy gate: greps tracked/staged files (and optional extra files, e.g. a
# commit message) for marker words listed in private/personal_markers.txt.
# The marker list itself is private and git-ignored; without it the check is skipped.
#   scripts/privacy_check.sh [extra-file ...]
# Exit 0 = no hits (or skipped), 1 = hits found.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKERS="$ROOT/private/personal_markers.txt"
cd "$ROOT"

if [[ ! -f "$MARKERS" ]]; then
  echo "NOTICE: private/personal_markers.txt not found; privacy check skipped."
  exit 0
fi

PATTERNS="$(mktemp)"
trap 'rm -f "$PATTERNS"' EXIT
grep -v '^[[:space:]]*#' "$MARKERS" | sed '/^[[:space:]]*$/d' > "$PATTERNS"
[[ -s "$PATTERNS" ]] || { echo "NOTICE: marker list is empty; privacy check skipped."; exit 0; }

FILES=()
while IFS= read -r -d '' f; do FILES+=("$f"); done < <(git ls-files -z --cached 2>/dev/null)
FILES+=("$@")

# Nothing tracked may live in local-only folders.
if printf '%s\n' "${FILES[@]}" | grep -E '^(source|private|build)/' ; then
  echo "FAIL: files from local-only folders are tracked/staged (listed above)."
  exit 1
fi

hits=0
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  if grep -I -n -i -w -F -f "$PATTERNS" -- "$f" >/dev/null 2>&1; then
    echo "HIT: $f (line numbers: $(grep -I -n -i -w -F -f "$PATTERNS" -- "$f" | cut -d: -f1 | tr '\n' ' '))"
    hits=$((hits + 1))
  fi
done

echo "privacy check: ${#FILES[@]} file(s) scanned, $hits file(s) with marker hits"
[[ $hits -eq 0 ]]
