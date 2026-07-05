#!/usr/bin/env bash
# Hermetic tests for hooks/enforce-autoupdate.sh.
#
# Overrides HOME to a throwaway tree so the hook reads its known_marketplaces
# and writes its settings.json inside a fixture ~/.claude, never the real one.
# Covers the merge invariants the script's header promises: arm only when a
# marketplace is missing the flag, preserve unrelated keys, and no-op (no churn)
# once everything is already auto-updating.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/hooks/enforce-autoupdate.sh"
BASH_BIN="$(command -v bash)"  # absolute, so the jq-missing case can blank PATH

pass=0; fail=0
run() {  # $1 expected-exit  $2 label  $3.. command (env prefix ok)
  local want="$1" label="$2"; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then echo "  ok: $label"; pass=$((pass + 1))
  else echo "  FAIL: $label (exit $got, want $want)"; fail=$((fail + 1)); fi
}
check() {  # $1 label  $2 actual  $3 expected
  if [ "$2" = "$3" ]; then echo "  ok: $1"; pass=$((pass + 1))
  else echo "  FAIL: $1 (got '$2', want '$3')"; fail=$((fail + 1)); fi
}

# Build a fresh fixture HOME. $1 = known_marketplaces.json body ("" to omit),
# $2 = settings.json body ("" to omit). Sets HOME_DIR + SETTINGS.
setup() {
  HOME_DIR=$(mktemp -d /tmp/ea-home.XXXXXX)
  SETTINGS="$HOME_DIR/.claude/settings.json"
  mkdir -p "$HOME_DIR/.claude/plugins"
  [ -n "$1" ] && printf '%s\n' "$1" > "$HOME_DIR/.claude/plugins/known_marketplaces.json"
  [ -n "$2" ] && printf '%s\n' "$2" > "$SETTINGS"
  return 0
}
get() { jq -r "$1" "$SETTINGS" 2>/dev/null; }  # read a field from the fixture settings

# --- No marketplaces registered → nothing to enforce, no settings written. ---
setup "" ""
run 0 "no known marketplaces is a no-op"        env HOME="$HOME_DIR" bash "$SCRIPT"
check "settings.json not created"               "$([ -f "$SETTINGS" ] || echo absent)" "absent"

# --- Known file present but empty ({}) → no keys pending, no write. ---
setup '{}' ""
run 0 "empty known marketplaces is a no-op"     env HOME="$HOME_DIR" bash "$SCRIPT"
check "settings.json still not created"         "$([ -f "$SETTINGS" ] || echo absent)" "absent"

# --- One pending marketplace, no prior settings → armed. ---
setup '{"mp1":{"source":"github:a/b"}}' ""
run 0 "arms a pending marketplace"              env HOME="$HOME_DIR" bash "$SCRIPT"
check "mp1 autoUpdate set true"                 "$(get '.extraKnownMarketplaces.mp1.autoUpdate')" "true"
check "mp1 source preserved"                    "$(get '.extraKnownMarketplaces.mp1.source')"     "github:a/b"

# --- Partial state: mp1 already armed, mp2 pending, unrelated key present. ---
setup '{"mp1":{"source":"s1"},"mp2":{"source":"s2"}}' \
      '{"model":"opus","extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":true}}}'
run 0 "arms only the pending marketplace"       env HOME="$HOME_DIR" bash "$SCRIPT"
check "unrelated key preserved"                 "$(get '.model')"                                 "opus"
check "already-armed mp1 stays true"            "$(get '.extraKnownMarketplaces.mp1.autoUpdate')" "true"
check "pending mp2 armed"                        "$(get '.extraKnownMarketplaces.mp2.autoUpdate')" "true"

# --- Everything already armed → no-op, and settings.json is NOT rewritten. ---
setup '{"mp1":{"source":"s1"}}' \
      '{"extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":true}}}'
before=$(cat "$SETTINGS")
run 0 "all-armed run exits without writing"     env HOME="$HOME_DIR" bash "$SCRIPT"
check "settings.json byte-identical (no churn)" "$(cat "$SETTINGS")" "$before"

# --- jq absent → surfaced, conservative no-op, nothing written. ---
setup '{"mp1":{"source":"s1"}}' ""
run 0 "missing jq is a conservative no-op"      env HOME="$HOME_DIR" PATH=/nonexistent "$BASH_BIN" "$SCRIPT"
check "settings.json not created without jq"    "$([ -f "$SETTINGS" ] || echo absent)" "absent"

echo
echo "enforce-autoupdate: pass=$pass fail=$fail"
[ "$fail" = 0 ]
