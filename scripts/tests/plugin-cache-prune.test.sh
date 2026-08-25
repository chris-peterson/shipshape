#!/usr/bin/env bash
# Hermetic tests for plugin-cache-prune.sh.
#
# Every case rebuilds a throwaway ~/.claude/plugins tree (CLAUDE_PLUGINS_DIR),
# runs the prune, and asserts on both the output and what survived on disk —
# a refusal that still deletes is the failure this suite exists to catch. The
# live-lease case uses the test process's own PID.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin-cache-prune.sh"

pass=0; fail=0
ok()    { echo "  ok: $1"; pass=$((pass + 1)); }
bad()   { echo "  FAIL: $1"; fail=$((fail + 1)); }
has()   { case "$OUT" in *"$1"*) ok "$2" ;; *) bad "$2 (missing '$1')" ;; esac; }
gone()  { [ -e "$ROOT/$1" ] && bad "$2 (still there)" || ok "$2"; }
kept()  { [ -e "$ROOT/$1" ] && ok "$2" || bad "$2 (deleted!)"; }
exited(){ [ "$RC" = "$1" ] && ok "$2" || bad "$2 (exit $RC, want $1)"; }

ROOT=""
fixture() {
  [ -n "$ROOT" ] && rm -rf "$ROOT"
  ROOT=$(mktemp -d)
  mkdir -p "$ROOT/cache/mp1/alpha/0.9.0" "$ROOT/cache/mp1/alpha/1.0.0" \
           "$ROOT/cache/mp1/beta/0.1.0" "$ROOT/cache/mp2/gone/1.0.0" \
           "$ROOT/data/gone-mp2" "$ROOT/data/oldstate-mp3" "$ROOT/data/beta-inline"
  echo x > "$ROOT/cache/mp1/alpha/0.9.0/file"
  echo state > "$ROOT/data/oldstate-mp3/history.json"
}
prune() { OUT=$(CLAUDE_PLUGINS_DIR="$ROOT" bash "$SCRIPT" "$@" 2>&1); RC=$?; }
trap 'rm -rf "$ROOT"' EXIT

# --- the ordinary delete ------------------------------------------------------
fixture
prune cache/mp1/alpha/0.9.0 data/gone-mp2
exited 0 "a clean run exits 0"
has "pruned  cache/mp1/alpha/0.9.0" "reports the cache dir it deleted"
has "pruned=2 skipped=0"            "totals count both"
gone "cache/mp1/alpha/0.9.0" "stale version dir deleted"
gone "data/gone-mp2"         "empty orphan data dir deleted"
kept "cache/mp1/alpha/1.0.0" "the sibling current version survives"

# --- the parent directories ---------------------------------------------------
fixture
prune cache/mp1/beta/0.1.0
gone "cache/mp1/beta" "a plugin dir left empty is cleared"
kept "cache/mp1"      "the marketplace dir is never cleared"
has "pruned  cache/mp1/beta (empty plugin dir)" "the parent removal is reported"

fixture
echo junk > "$ROOT/cache/mp1/beta/.DS_Store"
prune cache/mp1/beta/0.1.0
kept "cache/mp1/beta" "a plugin dir holding a stray file is left alone"

# A plugin dir left empty by an earlier run is prunable in its own right, but
# only through rmdir — never as a recursive delete of whatever it holds.
fixture
mkdir -p "$ROOT/cache/mp1/leftover"
prune cache/mp1/leftover
exited 0 "an already-empty plugin dir is accepted"
gone "cache/mp1/leftover" "  and cleared"

fixture
prune cache/mp1/alpha
exited 0 "a plugin dir still holding versions is not an error"
has "skipped cache/mp1/alpha (not empty)" "  it is skipped, not emptied"
kept "cache/mp1/alpha/1.0.0" "  and its versions survive"

# --- refusals: the wrong depth is not deletable at any depth ------------------
for target in cache/mp1 cache data data/gone-mp2/nested elsewhere/x; do
  fixture
  prune "$target"
  exited 2 "refuses $target"
  kept "cache/mp1" "  and deletes nothing ($target)"
done

fixture
prune cache/../../etc
exited 2 "refuses a traversal path"
kept "cache/mp1" "  and deletes nothing (traversal)"

# A refusal alongside valid paths still prunes the valid ones and still exits 2.
fixture
prune cache/mp1 cache/mp1/alpha/0.9.0
exited 2 "a mixed batch exits 2"
gone "cache/mp1/alpha/0.9.0" "  the valid path in a mixed batch is still pruned"
kept "cache/mp1/alpha/1.0.0" "  the refused path is untouched"

# --- the lease is re-checked at delete time -----------------------------------
fixture
LSTART=$(ps -p $$ -o lstart= | sed 's/^ *//;s/ *$//')
mkdir -p "$ROOT/cache/mp1/alpha/0.9.0/.in_use"
printf '{"pid":%s,"procStart":"%s"}' "$$" "$LSTART" > "$ROOT/cache/mp1/alpha/0.9.0/.in_use/lease"
prune cache/mp1/alpha/0.9.0
exited 0 "a live lease is a skip, not an error"
has "skipped cache/mp1/alpha/0.9.0 (in use)" "the skip names the reason"
kept "cache/mp1/alpha/0.9.0" "a live-leased dir is never deleted"

# --- data dirs ----------------------------------------------------------------
fixture
prune data/oldstate-mp3
has "needs --data-confirmed" "a non-empty data dir is skipped by default"
kept "data/oldstate-mp3" "  and survives"

fixture
prune --data-confirmed data/oldstate-mp3
gone "data/oldstate-mp3" "--data-confirmed deletes it"

fixture
prune data/beta-inline
has "inline install artifact" "an -inline data dir is skipped"
kept "data/beta-inline" "  and survives"

# --- input handling -----------------------------------------------------------
fixture
OUT=$(printf 'cache/mp1/alpha/0.9.0\n#totals stale=1 reclaimable=4K\n' \
      | CLAUDE_PLUGINS_DIR="$ROOT" bash "$SCRIPT" 2>&1); RC=$?
exited 0 "reads paths on stdin, ignoring scan's #totals line"
gone "cache/mp1/alpha/0.9.0" "  and prunes what it read"

fixture
prune cache/mp1/alpha/9.9.9
exited 0 "a path that is already gone is not an error"
has "absent  cache/mp1/alpha/9.9.9" "  and is reported as absent"

echo
echo "plugin-cache-prune: pass=$pass fail=$fail"
[ "$fail" = 0 ]
