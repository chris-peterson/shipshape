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

# Two marketplaces whose installLocation takes each of the two shapes Claude
# Code writes: a directory for a git-sourced marketplace, a bare file for one
# sourced from a marketplace.json URL. Both have to yield per-plugin sources,
# since that is what the first-run question groups by.
mkdir -p "$CLAUDE_PLUGINS_DIR/marketplaces/mp1/.claude-plugin"
cat > "$CLAUDE_PLUGINS_DIR/marketplaces/mp1/.claude-plugin/marketplace.json" <<'JSON'
{ "plugins": [
    { "name": "alpha", "source": { "source": "url", "url": "https://github.com/you/alpha.git" } },
    { "name": "beta",  "source": { "source": "url", "url": "https://github.com/you/beta.git" } } ] }
JSON
cat > "$CLAUDE_PLUGINS_DIR/marketplaces/mp2" <<'JSON'
{ "plugins": [
    { "name": "gamma", "source": "./plugins/gamma" } ] }
JSON
cat > "$CLAUDE_PLUGINS_DIR/known_marketplaces.json" <<JSON
{ "mp1": { "installLocation": "$CLAUDE_PLUGINS_DIR/marketplaces/mp1" },
  "mp2": { "installLocation": "$CLAUDE_PLUGINS_DIR/marketplaces/mp2" } }
JSON

drift() { bash "$SCRIPT" --drift 2>/dev/null; }
field() { drift | jq -c "$1"; }

echo "== nothing decided yet"
eq "$(field '[.new[].key] | sort')" '["alpha@mp1","beta@mp1","gamma@mp2"]' "every installed plugin is new"
eq "$(field '.settled')" 'false' "not settled with questions outstanding"
eq "$(field '.targets')" '[]' "no examined set yet"
if [ -f "$DECL" ]; then bad "--drift wrote the declaration"; else ok "--drift changes nothing"; fi

echo "== each outstanding plugin carries the source it ships from"
eq "$(drift | jq -r '.new[] | select(.key=="alpha@mp1") | .source')" 'https://github.com/you/alpha.git' "a directory installLocation yields its plugins' sources"
eq "$(drift | jq -r '.new[] | select(.key=="gamma@mp2") | .source')" './plugins/gamma' "and so does a bare-file installLocation"
eq "$(drift | jq -c '[.new[] | select(.source | startswith("https://github.com/you/")) | .key] | sort')" '["alpha@mp1","beta@mp1"]' "which is what lets one owner's plugins group together"

echo "== resolving a plugin's checkout without asking for a path"
# Two checkouts sharing a basename, as three `ai-tools` repos do on a real
# machine: the project index offers both, and only `origin` tells them apart.
HOME_ORIG="$HOME"
export HOME="$ROOT/home"; mkdir -p "$HOME"
mkalpha() {  # $1 dir  $2 origin url
  mkdir -p "$1"; git -C "$1" init -q 2>/dev/null
  git -C "$1" remote add origin "$2" 2>/dev/null
}
mkalpha "$ROOT/checkouts/you/alpha"   'git@github.com:you/alpha.git'
mkalpha "$ROOT/checkouts/other/alpha" 'https://github.com/other/alpha.git'
cat > "$HOME/.claude.json" <<JSON
{ "projects": {
    "$ROOT/checkouts/you/alpha":   {},
    "$ROOT/checkouts/other/alpha": {},
    "$ROOT/checkouts/unrelated":   {} } }
JSON
RES=$(bash "$SCRIPT" --resolve 2>/dev/null)
eq "$(printf '%s' "$RES" | jq -r '.[] | select(.key=="alpha@mp1") | .paths | join(",")')" "$ROOT/checkouts/you/alpha" "the checkout whose origin matches the source is found"
eq "$(printf '%s' "$RES" | jq -r '[.[] | select(.key=="alpha@mp1") | .paths[]] | length')" '1' "and the same-named repo under another owner is not offered"
eq "$(printf '%s' "$RES" | jq -r '[.[] | select(.key=="gamma@mp2")] | length')" '0' "a plugin bundled in its marketplace resolves to nothing"
export HOME="$HOME_ORIG"

echo "== recording decisions"
bash "$SCRIPT" --set alpha@mp1 issue "$SRC_A" >/dev/null 2>&1
eq "$?" '0' "a disposition with a real directory is accepted"
bash "$SCRIPT" --set beta@mp1 skip >/dev/null 2>&1
bash "$SCRIPT" --set gamma@mp2 skip >/dev/null 2>&1
eq "$(field '[.new[].key]')" '[]' "nothing new once every plugin is decided"
eq "$(field '.settled')" 'true' "settled once every question is answered"
eq "$(field '[.targets[].key]')" '["alpha@mp1"]' "the examined set holds only the non-skip rows"
eq "$(field '[.targets[].action]')" '["issue"]' "and carries each row's disposition"
eq "$(field '.skip | sort')" '["beta@mp1","gamma@mp2"]' "skips are reported"
eq "$(drift | jq -r '.targets[0].src')" "$SRC_A" "the recorded source path comes back"

echo "== every disposition round-trips"
for a in summarize issue edit; do
  bash "$SCRIPT" --set alpha@mp1 "$a" "$SRC_A" >/dev/null 2>&1
  eq "$(drift | jq -r '.targets[] | select(.key=="alpha@mp1") | .action')" "$a" "$a is recorded"
done
bash "$SCRIPT" --set alpha@mp1 issue "$SRC_A" >/dev/null 2>&1

echo "== a hand-added repo no manifest names"
bash "$SCRIPT" --set shipyard edit "$SRC_X" >/dev/null 2>&1
eq "$(field '[.targets[].key] | sort')" '["alpha@mp1","shipyard"]' "a bare key joins the examined set"
eq "$(field '.gone')" '[]' "a bare key is never reported as gone"
eq "$(field '.settled')" 'true' "a bare key raises no question"

echo "== a checkout that has moved"
mv "$SRC_A" "$ROOT/src/alpha-moved"
eq "$(field '[.unreadable[].key]')" '["alpha@mp1"]' "a missing source path is reported unreadable"
eq "$(field '[.targets[].key]')" '["shipyard"]' "and is kept out of the examined set"
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
eq "$(field '[.new[].key]')" '["delta@mp3"]' "a newly installed plugin is new"
eq "$(field '.settled')" 'false' "drift in either direction is a question"

echo "== forgetting"
bash "$SCRIPT" --forget beta@mp1 >/dev/null 2>&1
bash "$SCRIPT" --forget gamma@mp2 >/dev/null 2>&1
eq "$(field '.gone')" '[]' "a forgotten key stops being reported"

echo "== refusals"
bash "$SCRIPT" --set eps@mp1 issue "$ROOT/src/nope" >/dev/null 2>&1
eq "$?" '2' "a disposition refuses a path that is not a directory"
eq "$(drift | jq -r '[.new[].key] | index("eps@mp1") // "absent"')" 'absent' "and records nothing"
bash "$SCRIPT" --set alpha@mp1 maybe >/dev/null 2>&1
eq "$?" '2' "an unknown action is refused"
bash "$SCRIPT" --set alpha@mp1 issue >/dev/null 2>&1
eq "$?" '2' "a disposition without a source path is refused"
bash "$SCRIPT" --set beta@mp1 skip "$SRC_A" >/dev/null 2>&1
eq "$?" '2' "skip refuses a source path"
eq "$(drift | jq -r '.targets[] | select(.key=="alpha@mp1") | .src')" "$SRC_A" "a refused --set leaves the prior decision intact"

echo "== an unreadable declaration is not an empty one"
cp "$DECL" "$ROOT/decl.bak"
echo 'not json' > "$DECL"
OUT=$(bash "$SCRIPT" --drift 2>&1); rc=$?
eq "$rc" '1' "a corrupt declaration exits non-zero"
case "$OUT" in *"not readable as a declaration"*) ok "and says why" ;; *) bad "and says why (got '$OUT')" ;; esac
eq "$(cat "$DECL")" 'not json' "and leaves the file untouched"
cp "$ROOT/decl.bak" "$DECL"

echo "== a hand-written declaration is honored as-is"
cat > "$DECL" <<JSON
{ "version": 1,
  "targets": {
    "alpha@mp1": { "action": "edit", "src": "$SRC_A" },
    "delta@mp3": { "action": "skip" } } }
JSON
eq "$(drift | jq -r '.targets[] | select(.key=="alpha@mp1") | .action')" 'edit' "a hand-set disposition comes back unchanged"
eq "$(field '.skip')" '["delta@mp3"]' "and so does a hand-set skip"
bash "$SCRIPT" --set alpha@mp1 issue "$SRC_A" >/dev/null 2>&1
eq "$(jq -r '.targets["delta@mp3"].action' "$DECL")" 'skip' "a write carries the other rows over"
eq "$(jq -r '.version' "$DECL")" '1' "and leaves the schema version alone"

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
