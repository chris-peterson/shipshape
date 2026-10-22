#!/usr/bin/env bash
# Hermetic tests for scripts/jq.sh: the skill's jq reads find a fetched jq where
# the system has none.

set -uo pipefail
. "$(dirname "$0")/wrap-tools.sh"

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/jq.sh"
BASH_BIN="$(command -v bash)"

FIXTURES=$(mktemp -d /tmp/jq-sh.XXXXXX)
trap 'rm -rf "$FIXTURES"' EXIT

pass=0; fail=0
check() {  # $1 label  $2 actual  $3 expected
  if [ "$2" = "$3" ]; then echo "  ok: $1"; pass=$((pass + 1))
  else echo "  FAIL: $1 (got '$2', want '$3')"; fail=$((fail + 1)); fi
}

TOOLS="$FIXTURES/tools" DATA="$FIXTURES/data"
mkdir -p "$TOOLS" "$DATA/bin"
wrap_tools "$DATA/bin" jq

# --- No system jq: the fetched one answers. ---
out=$(printf '{"a":1}' | env PATH="$TOOLS" CLAUDE_PLUGIN_DATA="$DATA" "$BASH_BIN" "$SCRIPT" -r '.a' 2>&1); rc=$?
check "a fetched jq answers"                 "$out" "1"
check "and exits 0"                          "$rc"  "0"

# --- jq's own exit code comes back, so `jq -e` still works as a test. ---
printf '{"a":false}' | env PATH="$TOOLS" CLAUDE_PLUGIN_DATA="$DATA" "$BASH_BIN" "$SCRIPT" -e '.a' >/dev/null 2>&1
check "jq -e's exit code passes through"     "$?"   "1"

# --- No jq anywhere: a loud failure, not an empty answer. ---
printf '{"a":1}' | env -u CLAUDE_PLUGIN_DATA PATH="$TOOLS" "$BASH_BIN" "$SCRIPT" -r '.a' >/dev/null 2>&1
check "no jq at all exits 127"               "$?"   "127"

echo
echo "jq: pass=$pass fail=$fail"
[ "$fail" = 0 ]
