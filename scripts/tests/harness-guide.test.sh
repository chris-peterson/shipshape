#!/usr/bin/env bash
# Hermetic tests for harness-guide.sh.
#
# Points CLAUDE_PLUGIN_DATA and CLAUDE_PLUGINS_DIR at a throwaway tree, so the
# guide is seeded and read inside the fixture and never in the real data dir.
# Covers an absent guide staying absent through every read, --seed writing both
# headings once, each section read on its own with ### subheadings kept and
# comments stripped, text outside the sections reported rather than run, the two
# older guides migrated on the first read, --installers listing what installed
# plugins ship, an inline mount reading the installed lane, and loud exits on bad
# input.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/harness-guide.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
eq() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want '$2', got '$1')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 ('$1' lacks '$2')" ;; esac; }

ROOT=$(mktemp -d /tmp/harness-guide.XXXXXX)
trap 'rm -rf "$ROOT"' EXIT

export CLAUDE_PLUGINS_DIR="$ROOT/plugins"
mkdir -p "$CLAUDE_PLUGINS_DIR"
printf '%s\n' '{ "version": 2, "plugins": { "shipshape@mp": [{ "scope": "user" }] } }' \
  > "$CLAUDE_PLUGINS_DIR/installed_plugins.json"
LANE="$ROOT/data/shipshape-mp"
GUIDE="$LANE/harness-maintenance-guide.md"

run() {  # sets OUT, ERR, RC; $1 is the data dir, the rest are arguments
  local data=$1; shift
  local err; err=$(mktemp "$ROOT/err.XXXXXX")
  OUT=$(CLAUDE_PLUGIN_DATA="$data" bash "$SCRIPT" "$@" 2>"$err"); RC=$?
  ERR=$(cat "$err"); rm -f "$err"
}
state() { [ -e "$GUIDE" ] && echo present || echo absent; }
field() { run "$LANE" --status; printf '%s' "$OUT" | jq -r "$1"; }

echo "== an absent guide stays absent through every read"
run "$LANE" --path
eq "$OUT" "$GUIDE" "--path prints the guide's path"
run "$LANE" --section upgrade
eq "$RC:$OUT" "0:" "--section prints nothing"
run "$LANE" --status
eq "$OUT" "{\"path\":\"$GUIDE\",\"present\":false,\"upgrade\":{\"filled\":false},\"plugins\":{\"filled\":false},\"stray\":false}" "--status reports it absent"
eq "$(state)" "absent" "and nothing created it"

echo "== --seed writes both headings, and both read as unfilled"
run "$LANE" --seed
eq "$RC:$OUT" "0:$GUIDE" "--seed prints the path"
has "$(cat "$GUIDE")" "## After a Claude Code upgrade" "the upgrade heading is seeded"
has "$(cat "$GUIDE")" "## After plugins change" "the plugins heading is seeded"
eq "$(field '[.present, .upgrade.filled, .plugins.filled, .stray] | join(",")')" "true,false,false,false" "both sections read as unfilled"

echo "== each half reads only its own section"
cat > "$GUIDE" <<'EOF'
<!-- my notes -->

## After a Claude Code upgrade

Re-capture the system prompt. <!-- inline aside -->

## After plugins change

1. /reload-plugins

### beacon
2. /beacon:install-beacon

EOF
run "$LANE" --section upgrade
eq "$OUT" "Re-capture the system prompt." "the upgrade section, comments stripped"
run "$LANE" --section plugins
eq "$OUT" "1. /reload-plugins

### beacon
2. /beacon:install-beacon" "the plugins section keeps its ### subheading"
eq "$(field '[.upgrade.filled, .plugins.filled, .stray] | join(",")')" "true,true,false" "--status reports both filled"
before=$(cat "$GUIDE")
run "$LANE" --seed
eq "$(cat "$GUIDE")" "$before" "--seed leaves a written guide alone"

echo "== headings match regardless of case and trailing space"
printf '## after a CLAUDE code upgrade  \nUpgrade step\n' > "$GUIDE"
run "$LANE" --section upgrade
eq "$OUT" "Upgrade step" "a heading in another case still opens its section"

echo "== text outside the two sections is reported, never run"
printf 'Loose step\n## After plugins change\nPlugin step\n## Someday\nOther step\n' > "$GUIDE"
run "$LANE" --section plugins
eq "$OUT" "Plugin step" "only the plugins section is printed"
has "$ERR" "outside its two sections" "and the stray text is named on stderr"
has "$ERR" "Loose step" "quoting its first line"
eq "$(field '.stray')" "true" "--status flags it"

echo "== comments are dropped; instructions around them survive"
cat > "$GUIDE" <<'EOF2'
## After a Claude Code upgrade
<!-- a note to myself the guide should not pass on -->

Step one: /first-command <!-- an inline aside -->
<!-- multi-line note
     still a note
     end of note --> Step two: /second-command
Step three: /third-command
EOF2
run "$LANE" --section upgrade
eq "$OUT" "Step one: /first-command
 Step two: /second-command
Step three: /third-command" "inline and multi-line comments are dropped, the steps kept"
printf '## After a Claude Code upgrade\nRun "/quote-command" \\ then check <tag> & done\n' > "$GUIDE"
run "$LANE" --section upgrade
eq "$OUT" 'Run "/quote-command" \ then check <tag> & done' "quotes and backslashes survive"
eq "$(field '.upgrade.filled')" "true" "and --status stays valid JSON"

echo "== an unclosed comment is surfaced"
printf '## After plugins change\nRun /foo\n<!-- never closed\nRun /bar\n' > "$GUIDE"
run "$LANE" --section plugins
eq "$OUT" "Run /foo" "content stops at the unclosed comment"
has "$ERR" "unclosed <!--" "and says so on stderr"

echo "== the two older guides move in on the first read"
rm "$GUIDE"
printf '<!-- seed -->\nRe-capture the system prompt.\n## Note\nkeep this\nthen /plugin-maintenance\n' > "$LANE/on-claude-code-version-change.md"
printf '<!-- seed -->\n1. /reload-plugins\n' > "$LANE/after-plugin-maintenance.md"
run "$LANE" --status
eq "$RC" "0" "the read exits 0"
has "$ERR" "moved your guide steps" "and says where they went"
run "$LANE" --section upgrade
eq "$OUT" "Re-capture the system prompt.
### Note
keep this" "the version guide lands under the upgrade heading, ## demoted and the /plugin-maintenance step dropped"
run "$LANE" --section plugins
eq "$OUT" "1. /reload-plugins" "the post-maintenance guide lands under the plugins heading"
eq "$(ls "$LANE")" "harness-maintenance-guide.md" "both old files are removed"
before=$(cat "$GUIDE")
printf 'Later edit\n' > "$LANE/on-claude-code-version-change.md"
run "$LANE" --status
eq "$(cat "$GUIDE")" "$before" "a guide already present is never overwritten"

echo "== old guides holding only comments leave the guide absent"
rm -f "$GUIDE"
printf '<!-- seed only -->\n' > "$LANE/on-claude-code-version-change.md"
run "$LANE" --status
eq "$(state)" "absent" "no guide is created, so the setup offer still runs"
eq "$([ -e "$LANE/on-claude-code-version-change.md" ] && echo kept || echo gone)" "gone" "and the old seed is removed"

echo "== --installers lists what the current install of each plugin ships"
mkdir -p "$ROOT/cache/beacon/2.0/commands" "$ROOT/cache/beacon/1.0/commands" \
         "$ROOT/cache/tack/1.0/skills/install-cli" "$ROOT/cache/plain/1.0"
touch "$ROOT/cache/beacon/2.0/commands/install-beacon.md" "$ROOT/cache/beacon/1.0/commands/install-old.md" \
      "$ROOT/cache/beacon/2.0/commands/status.md" "$ROOT/cache/tack/1.0/skills/install-cli/SKILL.md"
cat > "$CLAUDE_PLUGINS_DIR/installed_plugins.json" <<JSON
{ "version": 2, "plugins": {
  "shipshape@mp": [{ "scope": "user" }],
  "beacon@mp": [{ "scope": "user", "installPath": "$ROOT/cache/beacon/2.0" }],
  "tack@mp":   [{ "scope": "user", "installPath": "$ROOT/cache/tack/1.0" }],
  "plain@mp":  [{ "scope": "user", "installPath": "$ROOT/cache/plain/1.0" }] } }
JSON
run "$LANE" --installers
eq "$OUT" "/beacon:install-beacon
/tack:install-cli" "a command installer and an install-cli skill, from the current versions only"
OUT=$(CLAUDE_PLUGINS_DIR="$ROOT/none" bash "$SCRIPT" --installers 2>&1); RC=$?
eq "$RC" "1" "no install manifest is a loud failure"

echo "== an inline mount reads the installed lane's guide"
run "$ROOT/data/shipshape-inline" --path
eq "$OUT" "$GUIDE" "the inline lane resolves to the installed guide"

echo "== bad input is a loud failure"
OUT=$(env -u CLAUDE_PLUGIN_DATA bash "$SCRIPT" --status 2>&1); RC=$?
eq "$RC" "1" "exits 1 without CLAUDE_PLUGIN_DATA"
has "$OUT" "CLAUDE_PLUGIN_DATA is unset" "and names why"
for args in "" "--bogus" "--section" "--section other"; do
  # shellcheck disable=SC2086
  run "$LANE" $args
  eq "$RC" "2" "'$args' is a usage error"
done

echo
echo "harness-guide: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
