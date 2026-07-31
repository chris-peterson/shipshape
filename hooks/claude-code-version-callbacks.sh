#!/usr/bin/env bash
# SessionStart hook: emit your re-training instructions when Claude Code's
# version changes.
#
# A new Claude Code version can change what your AI artifacts need to know:
# hook schemas, settings keys, skill frontmatter. This hook notices the version
# moved and hands Claude the document you wrote about what to do next, so the
# re-training happens at the top of the session rather than whenever you
# remember it.
#
# Hooks cannot invoke a slash command directly. What SessionStart *can* do is
# write to stdout, which Claude Code adds as context Claude sees and acts on
# (https://code.claude.com/docs/en/hooks). So the document is the mechanism:
# whatever it says to run is what runs. Its comments are dropped on the way out,
# which is what lets the seeded template explain itself without the explanation
# arriving as an instruction.
#
# State and the document both live under $CLAUDE_PLUGIN_DATA, the directory
# Claude Code guarantees survives plugin updates
# (https://code.claude.com/docs/en/plugins-reference#persistent-data-directory).
# The version cache would not: an update moves the plugin to a new version dir
# and shipshape itself prunes the old one.
#
# Steady state is silent. Output happens on exactly three occasions: the first
# run (to name the document you can fill in), a version change with a filled-in
# document, and a missing prerequisite.

set -euo pipefail

: "${CLAUDE_PLUGIN_DATA:=}"

if [ -z "$CLAUDE_PLUGIN_DATA" ]; then
  printf '# shipshape\n\nVersion-change callbacks need `${CLAUDE_PLUGIN_DATA}`, which this Claude Code did not set. Update Claude Code to enable them.\n'
  exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
  printf '# shipshape\n\nVersion-change callbacks read the version from `claude --version`, and `claude` is not on PATH.\n'
  exit 0
fi

CALLBACKS="$CLAUDE_PLUGIN_DATA/on-claude-code-version-change.md"
STATE="$CLAUDE_PLUGIN_DATA/state/claude-code-version"

# `claude --version` prints "2.1.220 (Claude Code)"; the first field is the
# version. Report rather than exit non-zero if it fails: a hook that errors on
# every session start is noise, and the same convention covers a missing jq in
# enforce-autoupdate.sh.
if ! version_line="$(claude --version 2>&1)"; then
  printf '# shipshape\n\nVersion-change callbacks could not read the Claude Code version:\n\n    %s\n' "$version_line"
  exit 0
fi
current="$(printf '%s\n' "$version_line" | awk 'NR == 1 {print $1}')"

if [ -z "$current" ]; then
  printf '# shipshape\n\n`claude --version` printed no version, so there is nothing to compare against.\n'
  exit 0
fi

mkdir -p "$(dirname "$STATE")"

# Seed the document whenever it's absent, so the name never has to be guessed.
# Comment lines only: until a real line is added, has_instructions() reads it as
# unfilled and no callbacks fire.
if [ ! -e "$CALLBACKS" ]; then
  cat > "$CALLBACKS" <<'TEMPLATE'
<!-- shipshape: what to do when Claude Code's version changes. -->
<!-- Write instructions here, naming the commands you want run. They are
     handed to Claude at the start of the first session after an upgrade.
     For example:

       Re-train my AI artifacts against this Claude Code version:
         1. /my-retrain-command
         2. /plugin-maintenance

     Comments are dropped, so nothing fires while this file holds only this
     one. -->
TEMPLATE
fi

# The document's content: its lines with HTML comment blocks (single- or
# multi-line) and leading blanks dropped. One test of content decides both
# whether the document is filled in and what gets emitted, so the seeded
# template can explain itself without becoming an instruction.
content() {
  awk '
    /^[[:space:]]*<!--/ { skip = 1 }
    skip { if (/-->/) skip = 0; next }
    !started && /^[[:space:]]*$/ { next }
    { started = 1; print }
  ' "$CALLBACKS"
}

has_instructions() {
  [ -n "$(content)" ]
}

# First run: nothing to compare against. Record the version and name the
# document, so the next upgrade has somewhere to read from.
if [ ! -s "$STATE" ]; then
  printf '%s\n' "$current" > "$STATE"
  printf '# shipshape: tracking Claude Code %s\n\n' "$current"
  printf 'On the next Claude Code version change, shipshape will hand Claude whatever this document says:\n\n'
  printf '    %s\n\n' "$CALLBACKS"
  if has_instructions; then
    printf 'It already holds instructions, so they will fire on the next version change.\n'
  else
    printf 'It holds only comments right now, so nothing will fire until you write instructions into it.\n'
  fi
  exit 0
fi

previous="$(tr -d '[:space:]' < "$STATE")"
[ "$previous" = "$current" ] && exit 0

# Record the new version before emitting, so a change is consumed exactly once
# even if this session ends abruptly.
printf '%s\n' "$current" > "$STATE"

has_instructions || exit 0

printf '# shipshape: Claude Code %s → %s\n\n' "$previous" "$current"
printf 'Claude Code changed version since the last session. Follow these instructions now, before anything else:\n\n'
content
