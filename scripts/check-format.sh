#!/usr/bin/env bash
#
# Opt-in formatting check for the files this repository formats.
#
#   bash scripts/check-format.sh                 # Dart + the release/CI docs added by this change
#   bash scripts/check-format.sh --all           # every tracked text path (currently reports drift)
#   bash scripts/check-format.sh --dart-only
#   bash scripts/check-format.sh --prettier-only
#
# Dart uses the default 80-column width, which is what the existing tree already
# uses. Prettier is configured in .prettierrc.json for the pipeline and docs;
# the existing docs/pipeline sources have not been reformatted in this change,
# so --all is advisory until a dedicated formatting pass lands.
#
# This script only checks. To apply the formatter deliberately:
#   dart format app
#   npx prettier@3.10.1 --write <paths>

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRETTIER_VERSION="3.10.1"
DART_LINE_LENGTH="${DART_LINE_LENGTH:-80}"

RUN_DART=1
RUN_PRETTIER=1
ALL=0
SCOPE=(
  ".github"
  "README.md"
  "docs/release.md"
  "docs/roadmap.md"
  "docs/linux-package.md"
)

usage() {
  sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  case "$arg" in
    --all)
      ALL=1
      SCOPE=(".")
      ;;
    --dart-only)
      RUN_PRETTIER=0
      ;;
    --prettier-only)
      RUN_DART=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument %s\n' "$arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

failures=0

if [[ "$RUN_DART" == "1" ]]; then
  if [[ -n "${FLUTTER:-}" ]]; then
    DART_BIN="$(dirname "$FLUTTER")/dart"
  elif command -v dart >/dev/null 2>&1; then
    DART_BIN="$(command -v dart)"
  elif [[ -x "$HOME/.local/flutter/bin/dart" ]]; then
    DART_BIN="$HOME/.local/flutter/bin/dart"
  else
    DART_BIN=""
  fi

  if [[ -z "$DART_BIN" || ! -x "$DART_BIN" ]]; then
    printf 'error: dart not found; set FLUTTER=/path/to/flutter or put dart on PATH\n' >&2
    exit 2
  fi

  printf '==> dart format --line-length %s app\n' "$DART_LINE_LENGTH"
  if ! ( cd "$ROOT" && "$DART_BIN" format \
      --output=none --set-exit-if-changed \
      --line-length "$DART_LINE_LENGTH" app ); then
    printf 'Dart formatting differs; run: dart format app\n' >&2
    failures=1
  fi
fi

if [[ "$RUN_PRETTIER" == "1" ]]; then
  if ! command -v npx >/dev/null 2>&1; then
    printf 'error: npx not found; install Node.js or run --dart-only\n' >&2
    exit 2
  fi

  if [[ "$ALL" == "0" ]]; then
    printf 'note: checking only the release/CI docs; use --all for the whole tree.\n'
  fi

  printf '==> prettier %s --check %s\n' "$PRETTIER_VERSION" "${SCOPE[*]}"
  if ! ( cd "$ROOT" && npx --yes "prettier@${PRETTIER_VERSION}" \
      --config .prettierrc.json \
      --ignore-path .prettierignore \
      --check "${SCOPE[@]}" ); then
    printf 'Prettier formatting differs for the paths above.\n' >&2
    printf 'Existing docs/pipeline drift is reported separately; do not reformat unrelated files.\n' >&2
    failures=1
  fi
fi

exit "$failures"
