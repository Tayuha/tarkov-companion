#!/usr/bin/env bash
#
# Static audit of the client's network destinations.
#
# Read-only: this script makes no network requests and writes no files. It
# compares the executable allowlist, the documented allowlist, and the literal
# hosts found in production client sources.
#
# The scan covers app/lib and app/packages/*/lib. Tests are excluded because
# they intentionally use fake loopback and `.test` hosts; the allowlist tests
# live under app/packages/data/test/net.
#
# A host is accepted when it is listed in NetworkAllowlist.productionHosts and
# in the "Allowed hosts" table of docs/network.md. A host listed under
# "Text-only hosts" is accepted only as UI copy, never as a request target.
#
# Usage:
#   bash scripts/audit-network.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOWLIST_FILE="$ROOT/app/packages/data/lib/src/net/host_allowlist.dart"
NETWORK_DOC="$ROOT/docs/network.md"

failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

normalize_hosts() {
  tr '[:upper:]' '[:lower:]' | sed '/^[[:space:]]*$/d' | sort -u
}

for file in "$ALLOWLIST_FILE" "$NETWORK_DOC"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: missing %s\n' "$file" >&2
    exit 2
  fi
done

mapfile -t ALLOWLIST_HOSTS < <(
  sed -n '/productionHosts = {/,/};/p' "$ALLOWLIST_FILE" |
    grep -oE "'[^']+'" | tr -d "'" | normalize_hosts
)

mapfile -t DOC_HOSTS < <(
  sed -n '/^## Allowed hosts/,/^## /p' "$NETWORK_DOC" |
    grep -E '^\| `[^`]+`' | sed -E 's/^\| `([^`]+)`.*/\1/' | normalize_hosts
)

mapfile -t TEXT_ONLY_HOSTS < <(
  sed -n '/^## Text-only hosts/,/^## /p' "$NETWORK_DOC" |
    grep -E '^- `[^`]+`' | sed -E 's/^- `([^`]+)`.*/\1/' | normalize_hosts
)

if [[ "${#ALLOWLIST_HOSTS[@]}" -eq 0 ]]; then
  fail "no hosts parsed from $ALLOWLIST_FILE"
fi

if [[ "${#DOC_HOSTS[@]}" -eq 0 ]]; then
  fail "no hosts parsed from the Allowed hosts table in $NETWORK_DOC"
fi

printf 'Network audit (static, read-only)\n'
printf '  allowlist: %d host(s) in host_allowlist.dart\n' "${#ALLOWLIST_HOSTS[@]}"
printf '  docs:      %d host(s) in docs/network.md\n' "${#DOC_HOSTS[@]}"

if ! diff -u \
  <(printf '%s\n' "${ALLOWLIST_HOSTS[@]-}") \
  <(printf '%s\n' "${DOC_HOSTS[@]-}") >/dev/null; then
  fail "the executable allowlist and docs/network.md disagree"
  diff -u \
    <(printf '%s\n' "${ALLOWLIST_HOSTS[@]-}") \
    <(printf '%s\n' "${DOC_HOSTS[@]-}") |
    sed 's/^/  /' >&2 || true
fi

mapfile -t SOURCE_FILES < <(
  find "$ROOT/app/lib" "$ROOT"/app/packages/*/lib \
    -type f -name '*.dart' 2>/dev/null | sort
)

if [[ "${#SOURCE_FILES[@]}" -eq 0 ]]; then
  fail "no client Dart sources found under app/lib or app/packages/*/lib"
fi

# Conservative literal detection:
#   * any http(s) URL, regardless of TLD;
#   * a quoted string that looks like a bare domain with a common TLD, so
#     `Uri.parse('host.example.com/x')` is caught even without a scheme.
# Quoted file names and identifiers such as `item_image.dart`,
# `settings.activeProfileId`, or the window method channel
# `dev.tarkovcompanion/window` do not end in one of the listed TLDs.
HOST_PATTERN="https?://[A-Za-z0-9._-]+|['\"][A-Za-z0-9][A-Za-z0-9.-]*\\.[A-Za-z]{2,}['\"/]"

declare -A OBSERVED=()
declare -A SEEN_PROBLEM=()

allowlisted() {
  local host="$1" candidate
  for candidate in "${ALLOWLIST_HOSTS[@]}"; do
    [[ "$candidate" == "$host" ]] && return 0
  done
  return 1
}

text_only() {
  local host="$1" candidate
  for candidate in "${TEXT_ONLY_HOSTS[@]}"; do
    [[ "$candidate" == "$host" ]] && return 0
  done
  return 1
}

for file in "${SOURCE_FILES[@]}"; do
  # The allowlist definition is the source of truth and is compared above.
  if [[ "$(basename "$file")" == "host_allowlist.dart" ]]; then
    continue
  fi

  while IFS= read -r match; do
    if [[ -z "$match" ]]; then
      continue
    fi

    line_no="${match%%:*}"
    text="${match#*:}"

    # Skip documentation comments; they describe destinations rather than
    # construct requests. The executable URL in manifest_fetcher.dart is not a
    # comment and is still scanned.
    trimmed="${text#"${text%%[![:space:]]*}"}"
    case "$trimmed" in
      '///'* | '//'* | '*'*) continue ;;
    esac

    hosts="$(
      {
        # URL hosts: trust the scheme and accept any TLD.
        grep -oE 'https?://[A-Za-z0-9._-]+' <<<"$text" |
          sed -E 's#^https?://##; s/^/u:/' || true
        # Bare quoted hosts: require a common TLD to avoid Dart identifiers.
        grep -oE "['\"][A-Za-z0-9][A-Za-z0-9.-]*\\.[A-Za-z]{2,}['\"/]" <<<"$text" |
          sed -E "s/^['\"]//; s/['\"/]$//; s/^/b:/" || true
      } |
        while IFS= read -r tagged; do
          kind="${tagged%%:*}"
          host="${tagged#*:}"
          if [[ "$kind" == "b" ]]; then
            [[ "$host" =~ \.(com|net|org|dev|io|app|co|uk|de|ru|info|xyz|me|sh|cloud|tech|gg|tv|ai|edu|gov|us|eu|fr|jp|cn|nl|se|no|fi|it|es|ca|au|br|in)$ ]] || continue
          fi
          printf '%s\n' "$host"
        done |
        tr '[:upper:]' '[:lower:]' | sort -u
    )"

    while IFS= read -r host; do
      if [[ -z "$host" ]]; then
        continue
      fi
      OBSERVED["$host"]=1

      if allowlisted "$host"; then
        continue
      fi

      if text_only "$host"; then
        # A text-only host must stay UI copy. If it appears on a line that
        # builds a request, the display-only exemption does not apply.
        if [[ "$text" =~ (Uri\.(parse|https|http)|\.get(Text|Bytes)?\(|AllowlistedHttpClient|http\.Client) ]]; then
          fail "${file#"$ROOT"/}:$line_no: text-only host '$host' appears in request-shaped code"
        fi
        continue
      fi

      problem="$file:$line_no:$host"
      if [[ -z "${SEEN_PROBLEM[$problem]-}" ]]; then
        SEEN_PROBLEM["$problem"]=1
        fail "${file#"$ROOT"/}:$line_no: literal host '$host' is not in the allowlist or docs/network.md"
      fi
    done <<<"$hosts"
  done < <(grep -nE "$HOST_PATTERN" "$file" || true)
done

if [[ "${#OBSERVED[@]}" -eq 0 ]]; then
  fail "no literal hosts found; the scan is probably broken"
fi

printf '  observed:  %d literal host(s) in production sources\n' "${#OBSERVED[@]}"
while IFS= read -r host; do
  if [[ -z "$host" ]]; then
    continue
  fi
  if allowlisted "$host"; then
    printf '    allow  %s\n' "$host"
  elif text_only "$host"; then
    printf '    text   %s (display copy only)\n' "$host"
  else
    printf '    OTHER  %s\n' "$host"
  fi
done < <(printf '%s\n' "${!OBSERVED[@]}" | sort)

if [[ "$failures" -ne 0 ]]; then
  printf '\n%d audit failure(s).\n' "$failures" >&2
  exit 1
fi

printf '\nOK: every literal client host is on the documented allowlist.\n'
printf 'This is a static review; a captured-request run is still a manual gate\n'
printf 'step (see docs/verification.md).\n'
