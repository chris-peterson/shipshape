#!/usr/bin/env bash
# SessionStart hook: announce a Claude Code version change, and hand Claude the
# re-training instructions you wrote for it.
#
#   claude-code-version.sh              the hook — announce while a version is unacknowledged
#   claude-code-version.sh --ack [ver]  dismiss: record `ver` (default: the running version)
#
# Claude Code updates itself between launches. Two things go unnoticed when it
# does: the change itself, which turns a new behavior into a mystery until you
# think to check `claude --version` against the changelog; and the staleness it
# leaves in your AI artifacts, whose hook schemas, settings keys, and skill
# frontmatter were written against the version before it. Both key off the same
# comparison, so they're one hook: one `claude --version`, one marker, one emit.
#
# The marker holds the version the user has *acknowledged*, not the one last
# seen, so a version change survives the session it appears in — a session
# opened to do something else can't swallow it. A first run has nothing to
# compare against and writes the marker silently, which makes installing
# shipshape the acknowledgement of whatever version you're already on.
#
# The two halves land on the two channels a SessionStart hook has. The banner
# goes out as `systemMessage`, the only hook output Claude Code shows the user.
# `additionalContext` carries what Claude acts on: your document's instructions,
# and how to dismiss the banner — which a banner has no affordance of its own to
# do. So acknowledging the update in conversation, or having the instructions
# carried out, is what clears it.
#
# A hook cannot invoke a slash command, but `additionalContext` *is* context
# Claude acts on, which is what makes the document the mechanism: whatever it
# names is what runs, and it can carry the reasoning rather than just a list.
# Its comments are dropped on the way out, so the seeded template can explain
# itself without the explanation arriving as an instruction.
#
# State and document both live under $CLAUDE_PLUGIN_DATA, the directory Claude
# Code guarantees survives plugin updates
# (https://code.claude.com/docs/en/plugins-reference#persistent-data-directory).
# A version cache would not: an update moves shipshape to a new version dir, and
# /plugin-maintenance prunes the old one.
#
# Opt out with SHIPSHAPE_VERSION_NOTICE=off in the `env` block of
# ~/.claude/settings.json.

set -euo pipefail

CHANGELOG="https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md"
SELF="${BASH_SOURCE[0]}"
VERSION_RE='^[0-9][0-9A-Za-z.+-]*$'

mode=hook
ack_version=""
case "${1:-}" in
  "")     ;;
  --ack)  mode=ack; ack_version="${2:-}" ;;
  *)      printf 'usage: %s [--ack [version]]\n' "$SELF" >&2; exit 2 ;;
esac

if [ "$mode" = hook ] && [ "${SHIPSHAPE_VERSION_NOTICE:-on}" = "off" ]; then
  exit 0
fi

# A hook reports and stands down: erroring every session start is noise, and the
# same convention covers a missing jq in enforce-autoupdate.sh. `--ack` failing
# to record is the caller's problem to see, since nothing was dismissed.
bail() {
  [ "$mode" = ack ] && exit 1
  exit 0
}

if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
  printf 'shipshape: CLAUDE_PLUGIN_DATA is unset; cannot track the Claude Code version.\n' >&2
  bail
fi

# The callback document is arbitrary user markdown, so the emitted JSON is built
# by jq rather than printf — there is no escaping to get right by hand.
if ! command -v jq >/dev/null 2>&1; then
  printf 'shipshape: jq is not on PATH; version notice skipped.\n' >&2
  bail
fi

marker="$CLAUDE_PLUGIN_DATA/acknowledged-version"
CALLBACKS="$CLAUDE_PLUGIN_DATA/on-claude-code-version-change.md"

record() {  # $1 version — written via a temp file so a concurrent reader never sees a torn marker
  mkdir -p "$CLAUDE_PLUGIN_DATA"
  local tmp; tmp="$(mktemp "${marker}.XXXXXX")"
  printf '%s\n' "$1" > "$tmp"
  mv "$tmp" "$marker"
}

# stderr is dropped rather than folded in: a node warning or an update notice
# printed ahead of the version would otherwise be parsed *as* the version, and a
# warning that varies per run (a PID) would announce a change every session.
read_version() {
  local reported
  if ! reported="$(claude --version 2>/dev/null)"; then
    printf 'shipshape: `claude --version` failed; version notice skipped.\n' >&2
    return 1
  fi
  reported="${reported%% *}"  # "2.1.227 (Claude Code)" → "2.1.227"
  if ! [[ "$reported" =~ $VERSION_RE ]]; then
    printf 'shipshape: unrecognized version string "%s"; version notice skipped.\n' "$reported" >&2
    return 1
  fi
  printf '%s' "$reported"
}

if [ "$mode" = ack ]; then
  # The version to record is the one that was announced, passed through the
  # emitted instruction. Claude Code can update its own binary mid-session, so
  # re-reading it here would record a version the user was never shown and
  # silently swallow that change.
  if [ -z "$ack_version" ]; then
    ack_version="$(read_version)" || bail
  elif ! [[ "$ack_version" =~ $VERSION_RE ]]; then
    printf 'shipshape: "%s" is not a version.\n' "$ack_version" >&2
    bail
  fi
  record "$ack_version"
  printf 'shipshape: acknowledged Claude Code %s.\n' "$ack_version"
  exit 0
fi

current="$(read_version)" || bail

# Seeded whenever absent, so the name never has to be guessed. Comment lines
# only: until a real line is added, content() reads it as unfilled.
if [ ! -e "$CALLBACKS" ]; then
  mkdir -p "$CLAUDE_PLUGIN_DATA"
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

# The document's lines with HTML comment spans and leading blanks removed. One
# test of content decides both whether the document is filled in and what gets
# emitted, so the seeded template explains itself without becoming an
# instruction. Spans are matched across the line rather than at its start, so an
# inline `<!-- note -->` neither leaks nor takes the instruction beside it with
# it.
content() {
  awk '
    {
      rest = $0; out = ""; touched = inc
      while (length(rest) > 0) {
        if (inc) {
          p = index(rest, "-->")
          if (p == 0) { rest = ""; break }
          inc = 0; touched = 1; rest = substr(rest, p + 3)
        } else {
          p = index(rest, "<!--")
          if (p == 0) { out = out rest; rest = ""; break }
          out = out substr(rest, 1, p - 1)
          inc = 1; touched = 1; rest = substr(rest, p + 4)
        }
      }
      sub(/[[:space:]]+$/, "", out)
      if (out == "" && touched) next        # the line was comment through and through
      if (!started && out == "") next       # leading blanks
      started = 1
      print out
    }
    END {
      # Silence with no signal is the failure mode here: an unclosed comment
      # swallows the rest of the document, and the hook would just go quiet.
      if (inc) print "shipshape: unclosed <!-- in " FILENAME "; the rest of the document was read as a comment." > "/dev/stderr"
    }
  ' "$CALLBACKS"
}

acknowledged=""
if [ -f "$marker" ]; then
  acknowledged="$(cat "$marker")"
  # Validated like `current`: the marker sits in a user-writable directory, and
  # a mangled one would otherwise be announced as the version you came from.
  if ! [[ "$acknowledged" =~ $VERSION_RE ]]; then
    acknowledged=""
  fi
fi

if [ "$acknowledged" = "$current" ]; then
  exit 0
fi

# Nothing acknowledged yet — installing shipshape acknowledges the version
# you're already on, so there's no delta to announce.
if [ -z "$acknowledged" ]; then
  record "$current"
  exit 0
fi

# The marker stays put: the notice repeats each session until `--ack` clears it.
# GitHub slugifies the changelog's `## 2.1.227` heading by dropping the dots.
banner="Claude Code $acknowledged → $current · $CHANGELOG#${current//./}"

context="Claude Code moved from $acknowledged to $current. The banner announcing it repeats every session until dismissed."
instructions="$(content)"
if [ -n "$instructions" ]; then
  context="$context

The user's re-training instructions for a version change follow. Carry them out
now, before anything else:

$instructions"
fi
context="$context

Dismiss the banner by running:

    CLAUDE_PLUGIN_DATA=$(printf '%q' "$CLAUDE_PLUGIN_DATA") bash $(printf '%q' "$SELF") --ack $current

Run it once the user has acknowledged the update — the instructions above have
been carried out, they ask what changed and you show them the changelog entry,
or they say thanks and move on. Don't run it unprompted while they haven't seen
it."

jq -nc --arg banner "$banner" --arg context "$context" \
  '{systemMessage: $banner, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}}'
