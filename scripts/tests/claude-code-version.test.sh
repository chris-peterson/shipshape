#!/usr/bin/env bash
# Hermetic tests for hooks/claude-code-version.sh.
#
# Stubs `claude` on PATH and points CLAUDE_PLUGIN_DATA at a throwaway dir, so
# the hook reads a version the test controls and writes its marker and callback
# document inside the fixture, never the real plugin data dir. Cases that test
# the *absence* of CLAUDE_PLUGIN_DATA run under `env -u`, since inheriting a
# real one would write to it.
#
# Covers what the script promises: silence on a first run and at steady state, a
# banner that repeats every session until it's acknowledged, a handoff to the
# skill rather than the guide's own text, `--guide` reading the document back
# with its comments stripped, `--status` as a read-only view of both versions,
# and a conservative no-op whenever a prerequisite is missing.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/hooks/claude-code-version.sh"
BASH_BIN="$(command -v bash)"  # absolute, so the claude-missing case can blank PATH

FIXTURES=$(mktemp -d /tmp/ccv-fixtures.XXXXXX)
trap 'rm -rf "$FIXTURES"' EXIT

pass=0; fail=0
check() {  # $1 label  $2 actual  $3 expected
  if [ "$2" = "$3" ]; then echo "  ok: $1"; pass=$((pass + 1))
  else echo "  FAIL: $1 (got '$2', want '$3')"; fail=$((fail + 1)); fi
}
contains() {  # $1 label  $2 haystack  $3 needle
  case "$2" in
    *"$3"*) echo "  ok: $1"; pass=$((pass + 1)) ;;
    *) echo "  FAIL: $1 ('$2' lacks '$3')"; fail=$((fail + 1)) ;;
  esac
}
lacks() {  # $1 label  $2 haystack  $3 needle
  case "$2" in
    *"$3"*) echo "  FAIL: $1 ('$3' leaked)"; fail=$((fail + 1)) ;;
    *) echo "  ok: $1"; pass=$((pass + 1)) ;;
  esac
}

# Fresh fixture: a data dir for the marker and document, and a bin dir holding a
# `claude` that reports $1 in the real command's "<version> (Claude Code)" shape.
setup() {
  DATA=$(mktemp -d "$FIXTURES/data.XXXXXX")
  BIN=$(mktemp -d "$FIXTURES/bin.XXXXXX")
  MARKER="$DATA/acknowledged-version"
  CALLBACKS="$DATA/on-claude-code-version-change.md"
  stub "$1"
}
stub() {
  printf '#!/bin/sh\nprintf "%%s (Claude Code)\\n" "%s"\n' "$1" > "$BIN/claude"
  chmod +x "$BIN/claude"
}
hook() {  # run the hook; sets OUT (stdout), ERR (stderr), RC. Extra args pass through as env.
  local err; err=$(mktemp "$FIXTURES/err.XXXXXX")
  OUT=$(env PATH="$BIN:$PATH" CLAUDE_PLUGIN_DATA="$DATA" "$@" bash "$SCRIPT" 2>"$err"); RC=$?
  ERR=$(cat "$err"); rm -f "$err"
}
run() {  # run the script with $@ as its arguments; sets OUT, ERR, RC
  local err; err=$(mktemp "$FIXTURES/err.XXXXXX")
  OUT=$(env PATH="$BIN:$PATH" CLAUDE_PLUGIN_DATA="$DATA" bash "$SCRIPT" "$@" 2>"$err"); RC=$?
  ERR=$(cat "$err"); rm -f "$err"
}
status() { run --status; }
guide() { run --guide; }
ack() {  # $@ — arguments after --ack
  OUT=$(env PATH="$BIN:$PATH" CLAUDE_PLUGIN_DATA="$DATA" bash "$SCRIPT" --ack "$@" 2>&1); RC=$?
}
marker() { [ -f "$MARKER" ] && cat "$MARKER" || echo absent; }
field() { printf '%s' "$OUT" | jq -r "$1" 2>/dev/null; }
ctx() { field '.hookSpecificOutput.additionalContext'; }
fill() { printf 'Re-train the artifacts: /my-retrain-command\n' > "$CALLBACKS"; }

# --- First run: installing acknowledges the version you're already on. ---
setup 2.1.0
hook
check "first run exits 0"                    "$RC"       "0"
check "first run prints no banner"           "$OUT"      ""
check "first run records the version"        "$(marker)" "2.1.0"
check "first run seeds the document"         "$([ -f "$CALLBACKS" ] && echo present)" "present"
contains "seeded document opens a comment"   "$(cat "$CALLBACKS")" "<!-- shipshape:"

# --- Unchanged version: no banner, no churn, document left alone. ---
before=$(cat "$CALLBACKS")
hook
check "unchanged version is silent"          "$OUT"      ""
check "unchanged version keeps marker"       "$(marker)" "2.1.0"
check "unchanged version keeps document"     "$(cat "$CALLBACKS")" "$before"

# --- Version moved: the banner, and a handoff to the skill. ---
stub 2.1.1
hook
check "changed version exits 0"              "$RC"       "0"
check "banner is valid JSON"                 "$(field 'has("systemMessage")')" "true"
contains "banner names both versions"        "$(field '.systemMessage')" "2.1.0 → 2.1.1"
contains "banner links the new entry"        "$(field '.systemMessage')" "CHANGELOG.md#211"
contains "banner names the command to run"   "$(field '.systemMessage')" "/claude-code-version"
check "unacknowledged version stays pending" "$(marker)" "2.1.0"
check "context is tagged SessionStart"       "$(field '.hookSpecificOutput.hookEventName')" "SessionStart"
contains "context names both versions"       "$(ctx)" "moved from 2.1.0 to 2.1.1"
contains "context hands off to the skill"    "$(ctx)" "claude-code-version\` skill"
contains "context says it repeats"           "$(ctx)" "repeats every session"

# --- Acknowledgement runs the guide, so the hook offers no shortcut past it. ---
lacks "context offers no raw ack command"    "$(ctx)" "--ack"
lacks "context leaks no data dir path"       "$(ctx)" "CLAUDE_PLUGIN_DATA="

# --- Undismissed, so the next session banners again. ---
hook
contains "next session banners again"        "$(field '.systemMessage')" "2.1.0 → 2.1.1"

# --- A second update while the first is pending compares against the ack'd version. ---
stub 2.1.2
hook
contains "banner spans both updates"         "$(field '.systemMessage')" "2.1.0 → 2.1.2"

# --- The dismissal path in the shape the skill runs it: the data dir arrives as
# an assignment prefix, since the variable reaches hook processes and not the
# shell a Bash tool call runs in. ---
OUT=$(env -u CLAUDE_PLUGIN_DATA PATH="$BIN:$PATH" "$BASH_BIN" -c \
  "CLAUDE_PLUGIN_DATA=$DATA $BASH_BIN $SCRIPT --ack 2.1.2" 2>&1); RC=$?
check "skill's ack command exits 0"          "$RC"       "0"
contains "skill's ack reports the version"   "$OUT"      "2.1.2"
check "skill's ack records the version"      "$(marker)" "2.1.2"
hook
check "session after ack is silent"          "$OUT"      ""

# --- --ack records what was announced, not what's on PATH at dismissal time. ---
stub 2.1.3
hook                                          # banner 2.1.2 → 2.1.3
stub 2.1.9                                    # Claude Code self-updates mid-session
ack 2.1.3
check "ack records the announced version"    "$(marker)" "2.1.3"
hook
contains "the swallowed update still lands"  "$(field '.systemMessage')" "2.1.3 → 2.1.9"
ack                                           # bare --ack falls back to the running version
check "bare ack records the running version" "$(marker)" "2.1.9"

# --- A filled guide is read through --guide, never emitted by the hook. ---
setup 2.1.0
hook
fill
stub 2.2.0
hook
contains "banner still names the versions"   "$(field '.systemMessage')" "2.1.0 → 2.2.0"
lacks "hook keeps the guide out of context"  "$(ctx)" "/my-retrain-command"
lacks "hook keeps the guide out of the banner" "$(field '.systemMessage')" "/my-retrain-command"
guide
check "--guide exits 0"                      "$RC"       "0"
check "--guide prints the instructions"      "$OUT"      "Re-train the artifacts: /my-retrain-command"

# --- A patch bump fires too (any change in the version string). ---
ack 2.2.0
stub 2.2.1
hook
contains "patch bump fires"                  "$(field '.systemMessage')" "2.2.0 → 2.2.1"

# --- Comments dropped; instructions around them survive, inline ones included. ---
cat > "$CALLBACKS" <<'DOC'
<!-- a note to myself the guide should not pass on -->

Step one: /first-command <!-- an inline aside -->
<!-- multi-line note
     still a note
     end of note --> Step two: /second-command
Step three: /third-command
DOC
guide
contains "content before a comment survives" "$OUT" "Step one: /first-command"
contains "content after an inline close survives" "$OUT" "Step two: /second-command"
contains "plain lines survive"               "$OUT" "Step three: /third-command"
lacks "standalone comments are dropped"      "$OUT" "note to myself"
lacks "inline comments are dropped"          "$OUT" "an inline aside"
lacks "multi-line comment bodies are dropped" "$OUT" "still a note"

# --- An unclosed comment is surfaced rather than silently swallowing the rest. ---
printf 'Step one: /first-command\n<!-- oops, never closed\nStep two: /second-command\n' > "$CALLBACKS"
guide
contains "unclosed comment is reported"      "$ERR" "unclosed <!--"
contains "text before it still emits"        "$OUT" "Step one: /first-command"

# --- Comments and blanks only reads as unfilled. ---
printf '<!-- just a note -->\n\n<!-- and another -->\n' > "$CALLBACKS"
guide
check "comments-and-blanks-only reads empty" "$OUT" ""
status
check "unfilled guide is reported unfilled"  "$(field '.guide.filled')" "false"
hook
contains "but the banner still fires"        "$(field '.systemMessage')" "2.2.0 → 2.2.1"

# --- A document holding JSON metacharacters survives both readers intact. ---
printf 'Run "/quote-command" \\ then check <tag> & done\n' > "$CALLBACKS"
guide
check "quotes and backslashes survive"       "$OUT" 'Run "/quote-command" \ then check <tag> & done'
status
check "quoted document keeps valid JSON"     "$(field '.guide.filled')" "true"

# --- Deleting the document re-seeds it rather than disabling the feature. ---
rm "$CALLBACKS"
hook
check "deleted document is re-seeded"        "$([ -f "$CALLBACKS" ] && echo present)" "present"
rm "$CALLBACKS"
guide
check "--guide re-seeds it too"              "$([ -f "$CALLBACKS" ] && echo present)" "present"

# --- --status: the read-only view every mode of the skill starts from. ---
setup 2.1.0
hook                                          # records 2.1.0, seeds the document
status
check "--status exits 0"                     "$RC"       "0"
check "--status reports the acknowledged"    "$(field '.acknowledged')" "2.1.0"
check "--status reports the running version" "$(field '.current')"      "2.1.0"
check "settled machine is not pending"       "$(field '.pending')"      "false"
check "--status reports the guide path"      "$(field '.guide.path')"   "$CALLBACKS"
check "seeded guide reads as unfilled"       "$(field '.guide.filled')" "false"
stub 2.1.1
status
check "a moved version is pending"           "$(field '.pending')"      "true"
check "--status links the running entry"     "$(field '.changelog')"    "https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#211"
check "--status leaves the marker alone"     "$(marker)"                "2.1.0"
fill
status
check "a written guide reads as filled"      "$(field '.guide.filled')" "true"

# --- Nothing acknowledged yet: reported as null, not as a pending upgrade. ---
setup 2.1.0
status
check "unrecorded marker reports null"       "$(field '.acknowledged')" "null"
check "unrecorded marker is not pending"     "$(field '.pending')"      "false"
check "--status records nothing"             "$(marker)"                "absent"

# --- Opt-out silences the banner, not the modes the user asked for. ---
setup 2.1.0
hook                                          # seed the marker
stub 2.1.1
hook SHIPSHAPE_VERSION_NOTICE=off
check "opt-out prints no banner"             "$OUT"      ""
check "opt-out leaves the marker alone"      "$(marker)" "2.1.0"
OUT=$(env PATH="$BIN:$PATH" CLAUDE_PLUGIN_DATA="$DATA" SHIPSHAPE_VERSION_NOTICE=off \
  bash "$SCRIPT" --status 2>/dev/null); RC=$?
check "opt-out still answers --status"       "$(field '.pending')" "true"
hook                                          # re-enabled: the pending delta still lands
contains "re-enabled banner shows the delta" "$(field '.systemMessage')" "2.1.0 → 2.1.1"

# --- No data dir: surfaced on stderr, nothing written, session unaffected. ---
setup 2.1.0
OUT=$(env -u CLAUDE_PLUGIN_DATA PATH="$BIN:$PATH" "$BASH_BIN" "$SCRIPT" 2>/dev/null); RC=$?
check "missing data dir exits 0"             "$RC"       "0"
check "missing data dir prints no banner"    "$OUT"      ""
check "missing data dir writes nothing"      "$(marker)" "absent"
for arg in --ack --status --guide; do
  env -u CLAUDE_PLUGIN_DATA PATH="$BIN:$PATH" "$BASH_BIN" "$SCRIPT" "$arg" >/dev/null 2>&1; RC=$?
  check "$arg without a data dir fails loudly" "$RC" "1"
done

# --- `claude` unreachable: conservative no-op, marker untouched. ---
setup 2.1.0
hook
OUT=$(env PATH=/nonexistent CLAUDE_PLUGIN_DATA="$DATA" "$BASH_BIN" "$SCRIPT" 2>/dev/null); RC=$?
check "unreachable claude exits 0"           "$RC"       "0"
check "unreachable claude is silent"         "$OUT"      ""
check "unreachable claude keeps marker"      "$(marker)" "2.1.0"
env PATH=/nonexistent CLAUDE_PLUGIN_DATA="$DATA" "$BASH_BIN" "$SCRIPT" --status >/dev/null 2>&1; RC=$?
check "unreachable claude fails --status"    "$RC"       "1"

# --- Version read off stdout only: a warning on stderr is not the version. ---
setup 2.1.0
hook
printf '#!/bin/sh\necho "(node:1234) Warning: something" >&2\necho "2.1.0 (Claude Code)"\n' > "$BIN/claude"
chmod +x "$BIN/claude"
hook
check "stderr chatter is not parsed as a version" "$OUT" ""
check "stderr chatter leaves the marker alone"    "$(marker)" "2.1.0"

# --- Unparseable version: reported, not banner'd, and not recorded. ---
setup 2.1.0
hook
stub "(unreleased build)"
hook
check "unparseable version is silent"        "$OUT"      ""
contains "unparseable version is surfaced"   "$ERR"      "unrecognized version string"
check "unparseable version keeps marker"     "$(marker)" "2.1.0"

# --- A mangled marker is not announced as the version you came from. ---
setup 2.1.0
hook
printf 'not a version"\n' > "$MARKER"
stub 2.1.1
hook
check "mangled marker prints no banner"      "$OUT"      ""
check "mangled marker is reset to current"   "$(marker)" "2.1.1"

# --- An unknown argument is a usage error, not a silent no-op. ---
setup 2.1.0
OUT=$(env PATH="$BIN:$PATH" CLAUDE_PLUGIN_DATA="$DATA" bash "$SCRIPT" --dismiss 2>/dev/null); RC=$?
check "unknown argument exits 2"             "$RC"       "2"
ack "not-a-version"
check "ack with a bad version fails loudly"  "$RC"       "1"

echo
echo "claude-code-version: pass=$pass fail=$fail"
[ "$fail" = 0 ]
