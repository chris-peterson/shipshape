#!/usr/bin/env bash
# Hermetic tests for plugin-cache-scan.sh.
#
# Builds a throwaway ~/.claude/plugins tree (CLAUDE_PLUGINS_DIR) holding one of
# every case the classifier has to tell apart, runs the scan once, and asserts
# on the rows. The live-lease case uses the test process's own PID, so nothing
# here depends on a real plugin cache or a real session.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin-cache-scan.sh"

pass=0; fail=0
ok()   { echo "  ok: $1"; pass=$((pass + 1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail + 1)); }
has()  { case "$OUT" in *"$1"*) ok "$2" ;; *) bad "$2 (missing '$1')" ;; esac; }
hasnt(){ case "$OUT" in *"$1"*) bad "$2 (found '$1')" ;; *) ok "$2" ;; esac; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

mkcache() { mkdir -p "$ROOT/cache/$1"; echo x > "$ROOT/cache/$1/file"; }
mkdata()  { mkdir -p "$ROOT/data/$1"; }

mkcache mp1/alpha/1.0.0            # current — the manifest's installPath
mkcache mp1/alpha/0.9.0            # stale, no lease
mkcache mp1/alpha/0.8.0            # stale, live lease
mkcache mp2/gone/1.0.0             # orphan — no manifest key at all
mkcache mp1/robot-sheriff/2.0.0    # current, and a hyphenated plugin name
mkcache mp2/shared/1.0.0           # current via another marketplace's row

mkdir -p "$ROOT/cache/mp2/leftover"          # plugin dir, every version gone
mkdir -p "$ROOT/cache/mp2/strays"            # same, but holding a stray file
echo junk > "$ROOT/cache/mp2/strays/.DS_Store"

mkdata alpha-mp1                   # installed
mkdata robot-sheriff-mp1           # installed, hyphenated name
mkdata beta-inline                 # local-testing artifact
mkdata gone-mp2                    # orphan, empty
mkdata oldstate-mp3                # orphan, non-empty
echo state > "$ROOT/data/oldstate-mp3/history.json"

# A live lease on 0.8.0: this process's real PID and start time.
LSTART=$(ps -p $$ -o lstart= | sed 's/^ *//;s/ *$//')
mkdir -p "$ROOT/cache/mp1/alpha/0.8.0/.in_use"
printf '{"pid":%s,"procStart":"%s"}' "$$" "$LSTART" > "$ROOT/cache/mp1/alpha/0.8.0/.in_use/lease"

cat > "$ROOT/installed_plugins.json" <<JSON
{"plugins":{
  "alpha@mp1":         [{"scope":"user","version":"1.0.0","installPath":"$ROOT/cache/mp1/alpha/1.0.0"}],
  "robot-sheriff@mp1": [{"scope":"user","version":"2.0.0","installPath":"$ROOT/cache/mp1/robot-sheriff/2.0.0"}],
  "shared@mp1":        [{"scope":"user","version":"1.0.0","installPath":"$ROOT/cache/mp2/shared/1.0.0"}]
}}
JSON

OUT=$(CLAUDE_PLUGINS_DIR="$ROOT" bash "$SCRIPT" 2>&1)

has   "cache/mp1/alpha/0.9.0|stale|prunable"  "stale version with no lease is prunable"
has   "cache/mp1/alpha/0.8.0|stale|in-use"    "stale version with a live lease is in use"
has   "cache/mp2/gone/1.0.0|orphan|prunable"  "cache whose plugin key is gone is an orphan"
hasnt "cache/mp1/alpha/1.0.0"                 "the installPath dir is omitted"
hasnt "cache/mp1/robot-sheriff/2.0.0"         "hyphenated plugin's current dir is omitted"
hasnt "cache/mp2/shared/1.0.0"                "a dir shared across marketplaces reads as current"

has   "data/gone-mp2|orphan-data|empty"       "empty orphan data dir"
has   "data/oldstate-mp3|orphan-data|nonempty" "non-empty orphan data dir"
hasnt "data/alpha-mp1"                        "installed plugin's data dir is omitted"
hasnt "data/robot-sheriff-mp1"                "hyphenated plugin's data dir is omitted"
hasnt "beta-inline"                           "an -inline data dir never appears"

has   "cache/mp2/leftover|empty-plugin|prunable" "a plugin dir with no versions left"
hasnt "cache/mp2/strays"                      "a plugin dir holding a stray file is not reported"
has   "#totals stale=1 stale_in_use=1 orphan=1 orphan_in_use=0 empty_plugin=1 orphan_data=2" "totals line counts each class"

# No manifest -> nothing can be classified. Fail loudly rather than reporting
# every cache dir as an orphan, which is what an empty keys set would do.
rm "$ROOT/installed_plugins.json"
OUT=$(CLAUDE_PLUGINS_DIR="$ROOT" bash "$SCRIPT" 2>&1); got=$?
[ "$got" = 1 ] && ok "missing manifest exits 1" || bad "missing manifest exits 1 (got $got)"
has "no install manifest" "missing manifest says why"

echo
echo "plugin-cache-scan: pass=$pass fail=$fail"
[ "$fail" = 0 ]
