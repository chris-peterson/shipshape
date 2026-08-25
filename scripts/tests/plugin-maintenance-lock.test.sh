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

# An unreadable lock age must not be read as "old enough to steal". Shadow
# `stat` with a stub that fails the way an unrecognized dialect would, leaving
# the rest of the toolchain on PATH.
SHADOW=$(mktemp -d)
printf '#!/bin/sh\nexit 1\n' > "$SHADOW/stat"
chmod +x "$SHADOW/stat"
rm -f "$LOCK"
env CLAUDE_CODE_SESSION_ID=A bash "$SCRIPT" acquire >/dev/null 2>&1
run 3 "unreadable lock age is not stolen (no usable stat)" \
  env PATH="$SHADOW:$PATH" CLAUDE_CODE_SESSION_ID=C bash "$SCRIPT" acquire
check "lock still owned by A" "$(sed -n 's/.*"session"[^"]*"\([^"]*\)".*/\1/p' "$LOCK")" "A"
ERR=$(env PATH="$SHADOW:$PATH" CLAUDE_CODE_SESSION_ID=C bash "$SCRIPT" acquire 2>&1 >/dev/null)
case "$ERR" in
  *"cannot read the age"*) echo "  ok: the refusal says why"; pass=$((pass + 1)) ;;
  *) echo "  FAIL: the refusal says why (got '$ERR')"; fail=$((fail + 1)) ;;
esac
# The stale steal must still work when stat does read — an unreadable age is the
# only thing this guard blocks.
run 0 "a readable stale lock is still stolen" \
  env CLAUDE_CODE_SESSION_ID=B PLUGIN_MAINT_STALE=0 bash "$SCRIPT" acquire
rm -f "$SHADOW/stat"; rmdir "$SHADOW"

run 2 "usage error on bad subcommand"             env CLAUDE_CODE_SESSION_ID=A bash "$SCRIPT" frobnicate

rm -f "$LOCK"
echo
echo "plugin-maintenance-lock: pass=$pass fail=$fail"
[ "$fail" = 0 ]
