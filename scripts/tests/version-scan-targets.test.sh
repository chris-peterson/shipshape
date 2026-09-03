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
eq "$(field '.targets')" '[]' "no examined set yet"
eq "$(field '.mirror')" '""' "no mirror recorded"
if [ -f "$DECL" ]; then bad "--drift wrote the declaration"; else ok "--drift changes nothing"; fi

echo "== recording decisions"
bash "$SCRIPT" --set alpha@mp1 issue "$SRC_A" >/dev/null 2>&1
eq "$?" '0' "a disposition with a real directory is accepted"
bash "$SCRIPT" --set beta@mp1 skip >/dev/null 2>&1
bash "$SCRIPT" --set gamma@mp2 skip >/dev/null 2>&1
eq "$(field '.new')" '[]' "nothing new once every plugin is decided"
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

echo "== the claude-code mirror"
MIRROR="$ROOT/src/claude-code"; mkdir -p "$MIRROR"
bash "$SCRIPT" --set-mirror "$MIRROR" >/dev/null 2>&1
eq "$?" '0' "a real directory is accepted as the mirror"
eq "$(drift | jq -r '.mirror')" "$MIRROR" "the mirror comes back"
bash "$SCRIPT" --set-mirror "$ROOT/src/nowhere" >/dev/null 2>&1
eq "$?" '2' "a path that is not a directory is refused"
eq "$(drift | jq -r '.mirror')" "$MIRROR" "and the recorded mirror survives the refusal"
mv "$MIRROR" "$ROOT/src/cc-moved"
eq "$(drift | jq -r '.mirror')" '' "a mirror that has moved reads as absent"
eq "$(field '.settled')" 'true' "and is not a question — reads fall to gh"
OUT=$(bash "$SCRIPT" --drift 2>&1 >/dev/null)
case "$OUT" in *"reading through gh instead"*) ok "the fallback is surfaced on stderr" ;; *) bad "the fallback is surfaced on stderr (got '$OUT')" ;; esac
mv "$ROOT/src/cc-moved" "$MIRROR"
bash "$SCRIPT" --forget-mirror >/dev/null 2>&1
eq "$(drift | jq -r '.mirror')" '' "the mirror can be forgotten"

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
bash "$SCRIPT" --set eps@mp1 issue "$ROOT/src/nope" >/dev/null 2>&1
eq "$?" '2' "a disposition refuses a path that is not a directory"
eq "$(drift | jq -r '.new | index("eps@mp1") // "absent"')" 'absent' "and records nothing"
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
