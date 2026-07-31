#!/usr/bin/env bash
# Hermetic tests for hooks/claude-code-version-callbacks.sh.
#
# Points CLAUDE_PLUGIN_DATA at a throwaway dir and puts a stub `claude` first on
# PATH, so the hook reads a version we choose and writes its state and callback
# document inside the fixture, never the real plugin data dir.
#
# Covers the contract the script's header promises: silent at steady state,
# emits the document verbatim on a version change, treats a comments-only
# document as unfilled, and records the version on every run so one change fires
# exactly once.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/hooks/claude-code-version-callbacks.sh"
BASH_BIN="$(command -v bash)"  # absolute, so the claude-missing case can blank PATH

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
contains() {  # $1 label  $2 haystack  $3 needle
  case "$2" in
    *"$3"*) echo "  ok: $1"; pass=$((pass + 1)) ;;
    *) echo "  FAIL: $1 (no '$3' in output)"; fail=$((fail + 1)) ;;
  esac
}

# Build a fresh fixture. $1 = version the stub `claude` reports. Sets DATA,
# CALLBACKS, STATE, and STUB_BIN (prepend to PATH).
setup() {
  DATA=$(mktemp -d /tmp/ccvc-data.XXXXXX)
  CALLBACKS="$DATA/on-claude-code-version-change.md"
  STATE="$DATA/state/claude-code-version"
  STUB_BIN=$(mktemp -d /tmp/ccvc-bin.XXXXXX)
  printf '#!/bin/sh\nprintf "%%s (Claude Code)\\n" "%s"\n' "$1" > "$STUB_BIN/claude"
  chmod +x "$STUB_BIN/claude"
}
hook() {  # run the hook against the fixture, stdout captured by the caller
  env CLAUDE_PLUGIN_DATA="$DATA" PATH="$STUB_BIN:$PATH" bash "$SCRIPT"
}
bump() {  # change the version the stub reports
  printf '#!/bin/sh\nprintf "%%s (Claude Code)\\n" "%s"\n' "$1" > "$STUB_BIN/claude"
}
fill() {  # write real instructions into the callback document
  printf 'Re-train the artifacts: /my-retrain-command\n' > "$CALLBACKS"
}

# --- First run: records the version, seeds the document, names it, no callbacks. ---
setup 2.1.220
out=$(hook)
check "first run records the version"            "$(cat "$STATE")"                      "2.1.220"
check "first run seeds the callback document"     "$([ -f "$CALLBACKS" ] && echo present)" "present"
contains "first run names the document path"      "$out" "on-claude-code-version-change.md"
contains "first run says nothing fires yet"       "$out" "only comments"

# --- Seeded document is one multi-line comment, so it reads as unfilled. ---
contains "seeded document opens a comment"        "$(cat "$CALLBACKS")" "<!-- shipshape:"
contains "seeded document closes its comment"     "$(cat "$CALLBACKS")" "-->"

# --- Same version again: silent, and the document is left alone. ---
before=$(cat "$CALLBACKS")
out=$(hook)
check "unchanged version prints nothing"          "$out"                                  ""
check "unchanged version leaves document intact"  "$(cat "$CALLBACKS")"                   "$before"

# --- Version changed but the document is still unfilled: silent, state advances. ---
bump 2.2.4
out=$(hook)
check "unfilled document emits nothing"           "$out"                                  ""
check "unfilled run still records the version"    "$(cat "$STATE")"                       "2.2.4"

# --- Version changed with a filled-in document: delta line plus the document. ---
fill
bump 2.3.0
out=$(hook)
contains "delta names both versions"              "$out" "2.2.4 → 2.3.0"
contains "document instructions emitted"          "$out" "/my-retrain-command"
contains "framed as instructions to follow now"   "$out" "Follow these instructions now"
check "changed run records the new version"       "$(cat "$STATE")"                       "2.3.0"

# --- One change fires exactly once: the next run at the same version is silent. ---
out=$(hook)
check "second run at same version is silent"      "$out"                                  ""

# --- A patch bump fires too (any change in the version string). ---
bump 2.3.1
out=$(hook)
contains "patch bump fires"                       "$out" "2.3.0 → 2.3.1"

# --- Comments are dropped; the instructions around them survive intact. ---
cat > "$CALLBACKS" <<'DOC'
<!-- a note to myself the hook should not pass on -->

Step one: /first-command
<!-- multi-line note
     still a note
     end of note -->
Step two: /second-command
DOC
bump 2.5.0
out=$(hook)
contains "content before a comment survives"      "$out" "Step one: /first-command"
contains "content after a comment survives"       "$out" "Step two: /second-command"
case "$out" in
  *"note to myself"*|*"still a note"*)
    echo "  FAIL: comments are not emitted"; fail=$((fail + 1)) ;;
  *) echo "  ok: comments are not emitted"; pass=$((pass + 1)) ;;
esac
# The delta line, its framing line, a blank, then the two instruction lines: the
# leading blank line of the document itself is trimmed.
check "emitted body starts at the instructions"   "$(printf '%s\n' "$out" | sed -n '5p')" "Step one: /first-command"

# --- A document holding only comments and blanks is unfilled. ---
printf '<!-- just a note -->\n\n<!-- and another -->\n' > "$CALLBACKS"
bump 2.6.0
out=$(hook)
check "comments-and-blanks-only is unfilled"      "$out"                                  ""

# --- Deleting the document re-seeds it rather than disabling the hook. ---
rm "$CALLBACKS"
bump 2.4.0
out=$(hook)
check "deleted document is re-seeded"             "$([ -f "$CALLBACKS" ] && echo present)" "present"
check "re-seeded document emits nothing"          "$out"                                  ""

# --- First run with a document already filled in (state lost, document kept). ---
setup 2.1.220
fill
out=$(hook)
contains "first run notices a filled document"    "$out" "already holds instructions"
check "first run still records the version"       "$(cat "$STATE")"                       "2.1.220"
check "first run emits no callbacks"              "$(printf '%s\n' "$out" | grep -c '/my-retrain-command')" "0"

# --- CLAUDE_PLUGIN_DATA unset: reported, nothing written. ---
setup 2.1.220
out=$(env PATH="$STUB_BIN:$PATH" bash "$SCRIPT")
contains "unset data dir is reported"             "$out" "CLAUDE_PLUGIN_DATA"
check "unset data dir writes no state"            "$([ -e "$STATE" ] || echo absent)"      "absent"
run 0 "unset data dir still exits 0"              env PATH="$STUB_BIN:$PATH" bash "$SCRIPT"

# --- claude not on PATH: reported, nothing written. ---
setup 2.1.220
out=$(env CLAUDE_PLUGIN_DATA="$DATA" PATH=/nonexistent "$BASH_BIN" "$SCRIPT")
contains "missing claude is reported"             "$out" "not on PATH"
check "missing claude writes no state"            "$([ -e "$STATE" ] || echo absent)"      "absent"

# --- claude present but failing: reported, nothing written. ---
setup 2.1.220
printf '#!/bin/sh\necho "boom" >&2\nexit 1\n' > "$STUB_BIN/claude"
out=$(hook)
contains "failing claude is reported"             "$out" "could not read the Claude Code version"
check "failing claude writes no state"            "$([ -e "$STATE" ] || echo absent)"      "absent"

echo
echo "claude-code-version-callbacks: pass=$pass fail=$fail"
[ "$fail" = 0 ]
