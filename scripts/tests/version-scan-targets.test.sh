#!/usr/bin/env bash
# Hermetic tests for version-scan-targets.sh.
#
# Builds a throwaway install manifest and plugin data dir, then drives the
# declaration through the states the skill has to tell apart: nothing decided
# yet, a decision recorded, a checkout that has moved, a plugin uninstalled
# since the decision, and a hand-added repo no manifest names.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/version-scan-targets.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

eq() {
  if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want '$2', got '$1')"; fi
}

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export CLAUDE_PLUGINS_DIR="$ROOT/plugins"
export CLAUDE_PLUGIN_DATA="$ROOT/data"
mkdir -p "$CLAUDE_PLUGINS_DIR" "$CLAUDE_PLUGIN_DATA"
DECL="$CLAUDE_PLUGIN_DATA/version-scan-targets.json"

cat > "$CLAUDE_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{ "version": 2,
  "plugins": {
    "alpha@mp1": [{ "scope": "user", "installPath": "/x/alpha" }],
    "beta@mp1":  [{ "scope": "user", "installPath": "/x/beta" }],
    "gamma@mp2": [{ "scope": "user", "installPath": "/x/gamma" }] } }
JSON

SRC_A="$ROOT/src/alpha"; mkdir -p "$SRC_A"
SRC_X="$ROOT/src/extra"; mkdir -p "$SRC_X"

drift() { bash "$SCRIPT" --drift 2>/dev/null; }
field() { drift | jq -c "$1"; }

echo "== nothing decided yet"
eq "$(field '.new | sort')" '["alpha@mp1","beta@mp1","gamma@mp2"]' "every installed plugin is new"
eq "$(field '.settled')" 'false' "not settled with questions outstanding"
eq "$(field '.scan')" '[]' "no deep-scan set yet"
if [ -f "$DECL" ]; then bad "--drift wrote the declaration"; else ok "--drift changes nothing"; fi

echo "== recording decisions"
bash "$SCRIPT" --set alpha@mp1 scan "$SRC_A" >/dev/null 2>&1
eq "$?" '0' "scan with a real directory is accepted"
bash "$SCRIPT" --set beta@mp1 skip >/dev/null 2>&1
bash "$SCRIPT" --set gamma@mp2 skip >/dev/null 2>&1
eq "$(field '.new')" '[]' "nothing new once every plugin is decided"
eq "$(field '.settled')" 'true' "settled once every question is answered"
eq "$(field '[.scan[].key]')" '["alpha@mp1"]' "the scan set holds only what was marked scan"
eq "$(field '.skip | sort')" '["beta@mp1","gamma@mp2"]' "skips are reported"
eq "$(drift | jq -r '.scan[0].src')" "$SRC_A" "the recorded source path comes back"

echo "== a hand-added repo no manifest names"
bash "$SCRIPT" --set shipyard scan "$SRC_X" >/dev/null 2>&1
eq "$(field '[.scan[].key] | sort')" '["alpha@mp1","shipyard"]' "a bare key joins the scan set"
eq "$(field '.gone')" '[]' "a bare key is never reported as gone"
eq "$(field '.settled')" 'true' "a bare key raises no question"

echo "== a checkout that has moved"
mv "$SRC_A" "$ROOT/src/alpha-moved"
eq "$(field '[.unreadable[].key]')" '["alpha@mp1"]' "a missing source path is reported unreadable"
eq "$(field '[.scan[].key]')" '["shipyard"]' "and is kept out of the scan set"
eq "$(field '.settled')" 'false' "an unreadable source path is a question"
mv "$ROOT/src/alpha-moved" "$SRC_A"
eq "$(field '.settled')" 'true' "restoring the checkout settles it again"

echo "== a plugin uninstalled since the decision"
cat > "$CLAUDE_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{ "version": 2,
  "plugins": {
    "alpha@mp1": [{ "scope": "user", "installPath": "/x/alpha" }],
    "delta@mp3": [{ "scope": "user", "installPath": "/x/delta" }] } }
JSON
eq "$(field '.gone | sort')" '["beta@mp1","gamma@mp2"]' "decisions for uninstalled plugins are reported gone"
eq "$(field '.new')" '["delta@mp3"]' "a newly installed plugin is new"
eq "$(field '.settled')" 'false' "drift in either direction is a question"

echo "== forgetting"
bash "$SCRIPT" --forget beta@mp1 >/dev/null 2>&1
bash "$SCRIPT" --forget gamma@mp2 >/dev/null 2>&1
eq "$(field '.gone')" '[]' "a forgotten key stops being reported"

echo "== refusals"
bash "$SCRIPT" --set eps@mp1 scan "$ROOT/src/nope" >/dev/null 2>&1
eq "$?" '2' "scan refuses a path that is not a directory"
eq "$(drift | jq -r '.new | index("eps@mp1") // "absent"')" 'absent' "and records nothing"
bash "$SCRIPT" --set alpha@mp1 maybe >/dev/null 2>&1
eq "$?" '2' "an unknown action is refused"
bash "$SCRIPT" --set alpha@mp1 scan >/dev/null 2>&1
eq "$?" '2' "scan without a source path is refused"
eq "$(drift | jq -r '.scan[] | select(.key=="alpha@mp1") | .src')" "$SRC_A" "a refused --set leaves the prior decision intact"

echo "== an unreadable declaration is not an empty one"
cp "$DECL" "$ROOT/decl.bak"
echo 'not json' > "$DECL"
OUT=$(bash "$SCRIPT" --drift 2>&1); rc=$?
eq "$rc" '1' "a corrupt declaration exits non-zero"
case "$OUT" in *"not readable as a declaration"*) ok "and says why" ;; *) bad "and says why (got '$OUT')" ;; esac
eq "$(cat "$DECL")" 'not json' "and leaves the file untouched"
cp "$ROOT/decl.bak" "$DECL"

echo "== missing inputs"
OUT=$(CLAUDE_PLUGIN_DATA= bash "$SCRIPT" --drift 2>&1); rc=$?
eq "$rc" '1' "no CLAUDE_PLUGIN_DATA exits non-zero"
case "$OUT" in *"CLAUDE_PLUGIN_DATA is unset"*) ok "and names the reason" ;; *) bad "and names the reason" ;; esac
OUT=$(CLAUDE_PLUGINS_DIR="$ROOT/absent" bash "$SCRIPT" --drift 2>&1); rc=$?
eq "$rc" '1' "no install manifest exits non-zero"
case "$OUT" in *"no install manifest"*) ok "and names the reason" ;; *) bad "and names the reason" ;; esac

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
