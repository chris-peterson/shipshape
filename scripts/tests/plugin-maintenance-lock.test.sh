#!/usr/bin/env bash
# Hermetic tests for plugin-maintenance-lock.sh.
#
# Uses PLUGIN_MAINT_LOCK to point the lock at a throwaway file and simulates
# distinct sessions by setting CLAUDE_CODE_SESSION_ID per invocation.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin-maintenance-lock.sh"
LOCK=$(mktemp -u /tmp/pm-lock.XXXXXX.json)
export PLUGIN_MAINT_LOCK="$LOCK"

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

rm -f "$LOCK"

run 0 "acquire on fresh lock (session A)"        env CLAUDE_CODE_SESSION_ID=A bash "$SCRIPT" acquire
check "lockfile created" "$([ -f "$LOCK" ] && echo yes)" "yes"
run 0 "re-acquire same session (A, re-entrant)"  env CLAUDE_CODE_SESSION_ID=A bash "$SCRIPT" acquire
run 3 "acquire while A holds (session B) bails"  env CLAUDE_CODE_SESSION_ID=B bash "$SCRIPT" acquire
run 0 "release by non-owner (B) is a no-op"      env CLAUDE_CODE_SESSION_ID=B bash "$SCRIPT" release
check "lockfile still present after B release" "$([ -f "$LOCK" ] && echo yes)" "yes"
run 0 "release by owner (A)"                      env CLAUDE_CODE_SESSION_ID=A bash "$SCRIPT" release
check "lockfile removed after A release" "$([ -f "$LOCK" ] || echo gone)" "gone"

# Stale steal: A holds, but PLUGIN_MAINT_STALE=0 makes any existing lock stale.
env CLAUDE_CODE_SESSION_ID=A bash "$SCRIPT" acquire >/dev/null 2>&1
run 0 "stale lock is stolen (B, stale=0)"         env CLAUDE_CODE_SESSION_ID=B PLUGIN_MAINT_STALE=0 bash "$SCRIPT" acquire
check "lock now owned by B" "$(sed -n 's/.*"session"[^"]*"\([^"]*\)".*/\1/p' "$LOCK")" "B"

run 2 "usage error on bad subcommand"             env CLAUDE_CODE_SESSION_ID=A bash "$SCRIPT" frobnicate

# A caller with no session id (pin-plugin, run between sessions) supplies its own
# identity, because the pid fallback would differ between its acquire and release
# and the release would leave the lock behind.
rm -f "$LOCK"
run 0 "acquire with an explicit owner"  env -u CLAUDE_CODE_SESSION_ID PLUGIN_MAINT_OWNER=owner-1 bash "$SCRIPT" acquire
check "owner recorded" "$(sed -n 's/.*"session"[^"]*"\([^"]*\)".*/\1/p' "$LOCK")" "owner-1"
run 3 "another owner bails"             env -u CLAUDE_CODE_SESSION_ID PLUGIN_MAINT_OWNER=owner-2 bash "$SCRIPT" acquire
run 0 "release by the same owner, from a different process" env -u CLAUDE_CODE_SESSION_ID PLUGIN_MAINT_OWNER=owner-1 bash "$SCRIPT" release
check "lockfile removed" "$([ -f "$LOCK" ] || echo gone)" "gone"

rm -f "$LOCK"
echo
echo "plugin-maintenance-lock: pass=$pass fail=$fail"
[ "$fail" = 0 ]
