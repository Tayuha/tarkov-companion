#!/usr/bin/env bash
#
# Preflight and launcher for the manual offline verification checklist.
#
# This script never uses root and never changes a firewall, route, or network
# interface. It inspects the local database read-only, reports whether an
# unprivileged network namespace is available, and (with --launch) starts the
# app inside that namespace so no packets can leave the machine.
#
# The authoritative checklist, expected messages, and result boxes live in
# docs/verification.md. Use this script together with that document.
#
# Usage:
#   bash scripts/verify-offline.sh                  # inspect, then print steps
#   bash scripts/verify-offline.sh --launch         # inspect, then launch offline
#   bash scripts/verify-offline.sh --data-root DIR  # inspect a different tree
#
# Environment:
#   TARKOV_DATA_ROOT  Data root to inspect. Defaults to
#                     ${XDG_DATA_HOME:-$HOME/.local/share}/tarkov_companion.
#   TARKOV_APP        AppImage or bundle executable to launch.
#
# If unprivileged network namespaces are unavailable, disable networking from
# the desktop's network menu (for example, turn Wi-Fi off) and run the app by
# hand. Do not add firewall rules and do not run this script with sudo.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCH=0

DATA_ROOT="${TARKOV_DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/tarkov_companion}"

usage() {
  sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --launch)
      LAUNCH=1
      shift
      ;;
    --data-root)
      if [[ "$#" -lt 2 ]]; then
        printf 'error: --data-root needs a directory\n' >&2
        exit 2
      fi
      DATA_ROOT="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

DB="$DATA_ROOT/db/tarkov_companion.sqlite"
status=0

printf 'Offline verification preflight (read-only)\n'
printf '  data root: %s\n' "$DATA_ROOT"

if [[ ! -d "$DATA_ROOT" ]]; then
  if [[ "$LAUNCH" -eq 0 ]]; then
    printf '  FAIL: data root does not exist; run an online sync first.\n' >&2
    exit 1
  fi
  printf '  empty:     no data root yet (first-run-with-no-network case)\n'
fi

if [[ -d "$DATA_ROOT" && ! -f "$DB" ]]; then
  if [[ "$LAUNCH" -eq 0 ]]; then
    printf '  FAIL: no database at %s\n' "$DB" >&2
    printf '        Complete a first run before testing offline behaviour.\n' >&2
    exit 1
  fi
  printf '  empty:     no database yet (the first-run gate will run)\n'
fi

if [[ -f "$DB" ]]; then
  printf '  database:  %s (%s bytes)\n' "$DB" "$(stat -c '%s' "$DB" 2>/dev/null || printf '?')"

  if command -v sqlite3 >/dev/null 2>&1; then
    version="$(sqlite3 -readonly "$DB" 'PRAGMA user_version;' 2>/dev/null || true)"
    if [[ -z "$version" ]]; then
      printf '  FAIL: sqlite3 cannot read the database; it may be corrupt.\n' >&2
      printf '        Use the recovery checklist in docs/verification.md.\n' >&2
      status=1
    else
      printf '  schema:    user_version=%s\n' "$version"
      printf '  datasets by mode:\n'
      sqlite3 -readonly -header -column "$DB" \
        "SELECT mode, count(*) AS applied, MAX(datetime(appliedAt, 'unixepoch')) AS newest FROM datasetState GROUP BY mode ORDER BY mode;" \
        2>/dev/null | sed 's/^/    /' || printf '    (datasetState not readable)\n'
      total="$(sqlite3 -readonly "$DB" 'SELECT count(*) FROM datasetState;' 2>/dev/null || printf '0')"
      if [[ "$total" == "0" ]]; then
        printf '  WARN: no applied datasets; this tree will show the first-run gate.\n'
      fi
    fi
  else
    printf '  sqlite3:   not installed; skipping the read-only dataset summary.\n'
    printf '             Install sqlite3 if you want the count, or continue manually.\n'
  fi
fi

if [[ -d "$DATA_ROOT/downloads" ]]; then
  printf '  downloads: %s\n' "$(du -sh "$DATA_ROOT/downloads" 2>/dev/null | cut -f1)"
elif [[ -d "$DATA_ROOT" ]]; then
  printf '  downloads: missing (the sync may not have completed)\n'
fi

if [[ -d "$DATA_ROOT/logs" ]]; then
  recovery_hits="$(
    grep -Rhs 'read-only recovery mode' "$DATA_ROOT/logs" 2>/dev/null |
      wc -l | tr -d ' ' || true
  )"
  if [[ "$recovery_hits" != "0" ]]; then
    printf '  WARN: the log records %s recovery-mode open(s); this tree is not a healthy baseline.\n' "$recovery_hits"
  else
    printf '  logs:      no recovery-mode entry found\n'
  fi
fi

NET_MODE=""
if unshare -n true 2>/dev/null; then
  NET_MODE="unshare -n"
elif unshare -Urn true 2>/dev/null; then
  NET_MODE="unshare -Urn"
fi

if [[ -n "$NET_MODE" ]]; then
  printf '  offline:   %s is available (unprivileged, no firewall change)\n' "$NET_MODE"
else
  printf '  offline:   no unprivileged network namespace on this host\n'
  printf '             Disable networking from the desktop menu, then run the app manually.\n'
fi

find_app() {
  if [[ -n "${TARKOV_APP:-}" ]]; then
    printf '%s\n' "$TARKOV_APP"
    return 0
  fi

  local candidate
  for candidate in \
    "$ROOT"/dist/TarkovCompanion-*-x86_64.AppImage \
    "$ROOT/app/build/linux/x64/release/bundle/tarkov_companion" \
    "$ROOT/app/build/linux/x64/debug/bundle/tarkov_companion"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

printf '\nManual sequence (record PASS/FAIL in docs/verification.md):\n'
printf '  1. Launch once with networking disabled; confirm the window opens.\n'
printf '  2. Items: saved rows render, search and filters still work.\n'
printf '  3. Open an item detail: stats, prices and quest use render locally.\n'
printf '  4. Quests: saved list and available/catalog views render.\n'
printf '  5. Open a quest detail; complete an objective and confirm it persists.\n'
printf '  6. Profiles: activate, export and re-import a profile with networking off.\n'
printf '  7. About: version, bundle age, attribution and licence render.\n'
printf '  8. Press a visible retry/Check now; expect a non-blocking offline status.\n'
printf '  9. Restart offline; data and progress are still present.\n'
printf ' 10. Image cache: see the known limitation in docs/verification.md.\n'
printf '\nFirst-run-with-no-network is a separate check with an empty data root:\n'
printf '  export XDG_DATA_HOME=/tmp/tc-offline-empty\n'
printf '  bash scripts/verify-offline.sh --launch\n'
printf '  Expected gate heading: "Could not get the game data", with a Retry button.\n'

if [[ "$LAUNCH" -eq 0 ]]; then
  printf '\nPreflight only. Re-run with --launch to start the app offline.\n'
  exit "$status"
fi

if [[ "$status" -ne 0 ]]; then
  printf '\nRefusing to launch: fix the preflight failure above.\n' >&2
  exit "$status"
fi

if [[ -z "$NET_MODE" ]]; then
  printf '\nRefusing to launch without a network namespace.\n' >&2
  printf 'Disable networking from the desktop menu and run the app by hand.\n' >&2
  exit 2
fi

APP_BIN="$(find_app || true)"
if [[ -z "$APP_BIN" ]]; then
  printf '\nCould not find an app executable. Build one or set TARKOV_APP:\n' >&2
  printf '  bash scripts/package-linux.sh\n' >&2
  printf '  TARKOV_APP=dist/TarkovCompanion-0.1.0-x86_64.AppImage bash scripts/verify-offline.sh --launch\n' >&2
  exit 2
fi

if [[ "$(basename "$DATA_ROOT")" == "tarkov_companion" ]]; then
  export XDG_DATA_HOME="$(dirname "$DATA_ROOT")"
else
  printf 'warning: the app resolves its own tarkov_companion/ data directory;\n' >&2
  printf '         --data-root %s is used for inspection only.\n' "$DATA_ROOT" >&2
fi

printf '\nLaunching %s with networking disabled...\n' "$APP_BIN"
read -r -a net_cmd <<<"$NET_MODE"
exec "${net_cmd[@]}" -- "$APP_BIN"
