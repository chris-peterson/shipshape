#!/usr/bin/env bash
# Hermetic tests for hooks/enforce-autoupdate.sh.
#
# Overrides HOME to a throwaway tree so the hook reads its known_marketplaces
# and writes its settings.json inside a fixture ~/.claude, never the real one.
# Covers the merge invariants the script's header promises: enable only when a
# marketplace is missing the flag, preserve unrelated keys, and no-op (no churn)
# once everything is already auto-updating. Managed settings come from the
# fixture too: SHIPSHAPE_MANAGED_SETTINGS_DIR stands in for the OS directory and
# CLAUDE_CONFIG_DIR is cleared, so the machine's own policy never leaks in.

set -uo pipefail
unset CLAUDE_CONFIG_DIR
. "$(dirname "$0")/../platform.sh"
. "$(dirname "$0")/wrap-tools.sh"

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
# $2 = settings.json body ("" to omit). Sets HOME_DIR + SETTINGS, and points the
# managed-settings directory at an empty fixture one (MANAGED).
setup() {
  HOME_DIR=$(mktemp -d /tmp/ea-home.XXXXXX)
  SETTINGS="$HOME_DIR/.claude/settings.json"
  MANAGED="$HOME_DIR/managed"
  export SHIPSHAPE_MANAGED_SETTINGS_DIR="$MANAGED"
  mkdir -p "$HOME_DIR/.claude/plugins" "$MANAGED/managed-settings.d"
  [ -n "$1" ] && printf '%s\n' "$1" > "$HOME_DIR/.claude/plugins/known_marketplaces.json"
  [ -n "$2" ] && printf '%s\n' "$2" > "$SETTINGS"
  return 0
}
get() { jq -r "$1" "$SETTINGS" 2>/dev/null; }  # read a field from the fixture settings
remote() { printf '%s\n' "$1" > "$HOME_DIR/.claude/remote-settings.json"; }  # server-managed cache
managed() { printf '%s\n' "$1" > "$MANAGED/managed-settings.json"; }        # the OS policy file
absent() { [ -f "$SETTINGS" ] || echo absent; }

# --- No marketplaces registered → nothing to enforce, no settings written. ---
setup "" ""
run 0 "no known marketplaces is a no-op"        env HOME="$HOME_DIR" bash "$SCRIPT"
check "settings.json not created"               "$([ -f "$SETTINGS" ] || echo absent)" "absent"

# --- Known file present but empty ({}) → no keys pending, no write. ---
setup '{}' ""
run 0 "empty known marketplaces is a no-op"     env HOME="$HOME_DIR" bash "$SCRIPT"
check "settings.json still not created"         "$([ -f "$SETTINGS" ] || echo absent)" "absent"

# --- One pending marketplace, no prior settings → enabled. ---
setup '{"mp1":{"source":"github:a/b"}}' ""
run 0 "enables a pending marketplace"           env HOME="$HOME_DIR" bash "$SCRIPT"
check "mp1 autoUpdate set true"                 "$(get '.extraKnownMarketplaces.mp1.autoUpdate')" "true"
check "mp1 source preserved"                    "$(get '.extraKnownMarketplaces.mp1.source')"     "github:a/b"

# --- Partial state: mp1 already enabled, mp2 pending, unrelated key present. ---
setup '{"mp1":{"source":"s1"},"mp2":{"source":"s2"}}' \
      '{"model":"opus","extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":true}}}'
run 0 "enables only the pending marketplace"    env HOME="$HOME_DIR" bash "$SCRIPT"
check "unrelated key preserved"                 "$(get '.model')"                                 "opus"
check "already-enabled mp1 stays true"          "$(get '.extraKnownMarketplaces.mp1.autoUpdate')" "true"
check "pending mp2 enabled"                     "$(get '.extraKnownMarketplaces.mp2.autoUpdate')" "true"

# --- Everything already enabled → no-op, and settings.json is NOT rewritten. ---
setup '{"mp1":{"source":"s1"}}' \
      '{"extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":true}}}'
before=$(cat "$SETTINGS")
run 0 "all-enabled run exits without writing"   env HOME="$HOME_DIR" bash "$SCRIPT"
check "settings.json byte-identical (no churn)" "$(cat "$SETTINGS")" "$before"

# --- AUTO-07: a managed source's autoUpdate is the org's decision. ---

# No managed file anywhere → the user entry is written as before.
setup '{"mp1":{"source":"s1"}}' ""
run 0 "no managed file still enforces"          env HOME="$HOME_DIR" bash "$SCRIPT"
check "mp1 enabled with no managed policy"      "$(get '.extraKnownMarketplaces.mp1.autoUpdate')" "true"

# Server-managed true → no user entry for it; the unmanaged one is still enabled.
setup '{"mp1":{"source":"s1"},"mp2":{"source":"s2"}}' ""
remote '{"extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":true}}}'
out=$(env HOME="$HOME_DIR" bash "$SCRIPT" 2>&1)
check "managed-true marketplace gets no user entry" "$(get '.extraKnownMarketplaces | has("mp1")')" "false"
check "unmanaged mp2 still enabled"             "$(get '.extraKnownMarketplaces.mp2.autoUpdate')" "true"
case "$out" in *"- mp1"*) check "report leaves out the managed marketplace" "$out" "no mp1 row" ;;
  *) check "report leaves out the managed marketplace" ok ok ;; esac

# Server-managed false → the admin's off stands: no write, no message.
setup '{"mp1":{"source":"s1"}}' ""
remote '{"extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":false}}}'
out=$(env HOME="$HOME_DIR" bash "$SCRIPT" 2>&1)
check "managed false is not overridden"         "$(absent)" "absent"
check "all-managed run prints nothing"          "$out" ""

# A managed entry that leaves autoUpdate unset hasn't decided it → enforce.
setup '{"mp1":{"source":"s1"}}' ""
remote '{"extraKnownMarketplaces":{"mp1":{"source":"s1"}}}'
run 0 "managed entry without autoUpdate"        env HOME="$HOME_DIR" bash "$SCRIPT"
check "mp1 still enforced"                      "$(get '.extraKnownMarketplaces.mp1.autoUpdate')" "true"

# An existing user entry for a managed marketplace is left alone, not removed.
setup '{"mp1":{"source":"s1"},"mp2":{"source":"s2"}}' \
      '{"extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":true}}}'
remote '{"extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":false}}}'
run 0 "user entry beside a managed one"         env HOME="$HOME_DIR" bash "$SCRIPT"
check "user's own mp1 entry kept as written"    "$(get '.extraKnownMarketplaces.mp1.autoUpdate')" "true"
check "mp2 enabled alongside"                   "$(get '.extraKnownMarketplaces.mp2.autoUpdate')" "true"

# The OS managed-settings.json counts when nothing outranks it.
setup '{"mp1":{"source":"s1"}}' ""
managed '{"extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":true}}}'
run 0 "managed-settings.json sets it"           env HOME="$HOME_DIR" bash "$SCRIPT"
check "no user write under file policy"         "$(absent)" "absent"

# A drop-in counts, and a later drop-in's entry replaces the earlier one whole.
setup '{"mp1":{"source":"s1"},"mp2":{"source":"s2"}}' ""
managed '{"extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":true}}}'
printf '%s\n' '{"extraKnownMarketplaces":{"mp2":{"source":"s2","autoUpdate":true}}}' > "$MANAGED/managed-settings.d/10-b.json"
printf '%s\n' '{"extraKnownMarketplaces":{"mp1":{"source":"s1"}}}' > "$MANAGED/managed-settings.d/20-a.json"
run 0 "drop-ins merge in name order"            env HOME="$HOME_DIR" bash "$SCRIPT"
check "drop-in's autoUpdate is managed"         "$(get '.extraKnownMarketplaces | has("mp2")')" "false"
check "later drop-in's entry replaced it whole" "$(get '.extraKnownMarketplaces.mp1.autoUpdate')" "true"

# First source with a policy key wins: server policy hides the file's entry.
setup '{"mp1":{"source":"s1"}}' ""
remote '{"env":{"X":"1"}}'
managed '{"extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":true}}}'
run 0 "outranked file policy is ignored"        env HOME="$HOME_DIR" bash "$SCRIPT"
check "mp1 enforced under server policy"        "$(get '.extraKnownMarketplaces.mp1.autoUpdate')" "true"

# Control keys alone deliver no policy, so the file tier still wins.
setup '{"mp1":{"source":"s1"}}' ""
remote '{"wslInheritsWindowsSettings":true}'
managed '{"extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":true}}}'
run 0 "control-key-only server source"          env HOME="$HOME_DIR" bash "$SCRIPT"
check "file policy applies past it"             "$(absent)" "absent"

# managedSourcesBehavior "merge" in the top source reads every source.
setup '{"mp1":{"source":"s1"}}' ""
remote '{"managedSourcesBehavior":"merge","env":{"X":"1"}}'
managed '{"extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":true}}}'
run 0 "merged managed sources"                  env HOME="$HOME_DIR" bash "$SCRIPT"
check "file entry counts under merge"           "$(absent)" "absent"

# A managed file that doesn't parse delivers nothing → enforce.
setup '{"mp1":{"source":"s1"}}' ""
remote '{not json'
run 0 "unparseable managed file"                env HOME="$HOME_DIR" bash "$SCRIPT"
check "mp1 enforced past a broken cache"        "$(get '.extraKnownMarketplaces.mp1.autoUpdate')" "true"

# CLAUDE_CONFIG_DIR moves the config dir: known, settings, and the server cache.
setup "" ""
CONF="$HOME_DIR/conf"; mkdir -p "$CONF/plugins"
printf '%s\n' '{"mp1":{"source":"s1"},"mp2":{"source":"s2"}}' > "$CONF/plugins/known_marketplaces.json"
printf '%s\n' '{"extraKnownMarketplaces":{"mp1":{"source":"s1","autoUpdate":true}}}' > "$CONF/remote-settings.json"
run 0 "CLAUDE_CONFIG_DIR honored"               env HOME="$HOME_DIR" CLAUDE_CONFIG_DIR="$CONF" bash "$SCRIPT"
check "writes the config dir's settings"        "$(jq -r '.extraKnownMarketplaces.mp2.autoUpdate' "$CONF/settings.json" 2>/dev/null)" "true"
check "reads the config dir's server cache"     "$(jq -r '.extraKnownMarketplaces | has("mp1")' "$CONF/settings.json" 2>/dev/null)" "false"

# --- jq absent and can't be fetched → shown to the user, nothing written. ---
setup '{"mp1":{"source":"s1"}}' ""
out=$(env -u CLAUDE_PLUGIN_DATA HOME="$HOME_DIR" PATH=/nonexistent "$BASH_BIN" "$SCRIPT" 2>/dev/null)
check "missing jq is a conservative no-op"      "$?" "0"
check "settings.json not created without jq"    "$([ -f "$SETTINGS" ] || echo absent)" "absent"
banner=$(printf '%s' "$out" | jq -r '.systemMessage' 2>/dev/null)
case "$banner" in
  *"cannot turn on marketplace auto-update"*"/plugin"*"CLAUDE_PLUGIN_DATA is unset"*) check "missing jq is a banner naming the toggle and the reason" ok ok ;;
  *) check "missing jq is a banner naming the toggle and the reason" "$out" "a systemMessage" ;;
esac

# --- A jq fetch-jq.sh left in the data dir stands in for a system one. ---
setup '{"mp1":{"source":"s1"}}' ""
TOOLS=$(mktemp -d /tmp/ea-tools.XXXXXX)
wrap_tools "$TOOLS" cat mktemp mv sed
DATA=$(mktemp -d /tmp/ea-data.XXXXXX)
mkdir -p "$DATA/bin"
wrap_tools "$DATA/bin" jq
run 0 "a fetched jq enables the marketplace"    env HOME="$HOME_DIR" PATH="$TOOLS" CLAUDE_PLUGIN_DATA="$DATA" "$BASH_BIN" "$SCRIPT"
check "mp1 enabled with the fetched jq"         "$(get '.extraKnownMarketplaces.mp1.autoUpdate')" "true"

echo
echo "enforce-autoupdate: pass=$pass fail=$fail"
[ "$fail" = 0 ]
