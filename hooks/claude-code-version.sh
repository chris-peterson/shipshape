#!/usr/bin/env bash
# SessionStart hook: announce a Claude Code version change, and hand the
# handling to the skill that runs the instructions you wrote for it.
#
#   claude-code-version.sh              the hook — announce while a version is unacknowledged
#   claude-code-version.sh --ack [ver]  acknowledge: record `ver` (default: the running version)
#   claude-code-version.sh --status     report both versions and the guide, as JSON
#   claude-code-version.sh --guide      print the guide's content (nothing when unfilled)
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
# goes out as `systemMessage`, the only hook output Claude Code shows the user,
# and it names `/claude-code-version` so the person reading it has something to
# act on. `additionalContext` carries the same handoff for Claude: what moved,
# and the skill to run once the user has taken the update in.
#
# The guide the user wrote is dispatched by that skill, not emitted here. A hook
# cannot invoke a slash command, so handing over the document's text was once
# the only way to make it run — but this hook fires at every session start while
# a version is unacknowledged, and a one-time upgrade errand then ran again in
# every window that opened before someone dismissed the banner. Acknowledgement
# is the moment the errand belongs to, and the skill owns that moment: it reads
# the guide through `--guide`, carries it out, then records the version.
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
  "")        ;;
  --ack)     mode=ack; ack_version="${2:-}" ;;
  --status)  mode=status ;;
  --guide)   mode=guide ;;
  *)         printf 'usage: %s [--ack [version] | --status | --guide]\n' "$SELF" >&2; exit 2 ;;
esac

if [ "$mode" = hook ] && [ "${SHIPSHAPE_VERSION_NOTICE:-on}" = "off" ]; then
  exit 0
fi

# A hook reports and stands down: erroring every session start is noise, and the
# same convention covers a missing jq in enforce-autoupdate.sh. The other modes
# have a caller waiting on an answer, so a missing prerequisite is theirs to
# see — nothing was recorded and nothing can be reported.
bail() {
  [ "$mode" = hook ] || exit 1
  exit 0
}

if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
  printf 'shipshape: CLAUDE_PLUGIN_DATA is unset; cannot track the Claude Code version.\n' >&2
  bail
fi

# The emitted JSON carries a banner and a handoff naming both versions, so it is
# built by jq rather than printf — there is no escaping to get right by hand.
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
  # The version to record is the one that was announced, passed through by the
  # skill. Claude Code can update its own binary mid-session, so re-reading it
  # here would record a version the user was never shown and silently swallow
  # that change.
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

# Seeded whenever absent, so the name never has to be guessed. Comment lines
# only: until a real line is added, content() reads it as unfilled.
if [ ! -e "$CALLBACKS" ]; then
  mkdir -p "$CLAUDE_PLUGIN_DATA"
  cat > "$CALLBACKS" <<'TEMPLATE'
<!-- shipshape: what to do when Claude Code's version changes. -->
<!-- Write instructions here, naming the commands you want run. They are
     carried out once, when you acknowledge the upgrade with
     /claude-code-version. For example:

       Re-train my AI artifacts against this Claude Code version:
         1. /my-retrain-command
         2. /plugin-maintenance

     Comments are dropped, so nothing fires while this file holds only this
     one. -->
TEMPLATE
fi

# The document's lines with HTML comment spans and leading blanks removed. One
# test of content decides both whether the document is filled in and what gets
# carried out, so the seeded template explains itself without becoming an
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
      # swallows the rest of the document, and the reader would just go quiet.
      if (inc) print "shipshape: unclosed <!-- in " FILENAME "; the rest of the document was read as a comment." > "/dev/stderr"
    }
  ' "$CALLBACKS"
}

if [ "$mode" = guide ]; then
  content
  exit 0
fi

acknowledged=""
if [ -f "$marker" ]; then
  acknowledged="$(cat "$marker")"
  # Validated like the running version: the marker sits in a user-writable
  # directory, and a mangled one would otherwise be announced as the version you
  # came from.
  if ! [[ "$acknowledged" =~ $VERSION_RE ]]; then
    acknowledged=""
  fi
fi

current="$(read_version)" || bail

# GitHub slugifies the changelog's `## 2.1.227` heading by dropping the dots.
entry="$CHANGELOG#${current//./}"

if [ "$mode" = status ]; then
  # A query never writes: an unacknowledged version stays unacknowledged, so
  # asking what's pending can't be what dismisses it.
  filled=false
  if [ -n "$(content)" ]; then filled=true; fi
  jq -n --arg ack "$acknowledged" --arg cur "$current" --arg entry "$entry" \
        --arg guide "$CALLBACKS" --argjson filled "$filled" \
    '{acknowledged: (if $ack == "" then null else $ack end),
      current: $cur,
      pending: ($ack != "" and $ack != $cur),
      changelog: $entry,
      guide: {path: $guide, filled: $filled}}'
  exit 0
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

# The marker stays put: the notice repeats each session until it's acknowledged.
#
# The skill is what gets named, rather than a shell command: a slash command is
# short enough to sit on the line, it carries no path to go stale when shipshape
# updates, and it's the path that runs the user's guide.
banner="Claude Code $acknowledged → $current · $entry · /claude-code-version to review and clear"

context="Claude Code moved from $acknowledged to $current. The banner announcing it repeats every session until the version is acknowledged.

shipshape's \`claude-code-version\` skill handles it: it walks what changed,
carries out the version-change instructions the user wrote, and records the
version, which is what clears the banner. Invoke it once the user has taken the
update in — they ask what changed, they ask you to deal with it, or they say
thanks and move on. Don't invoke it unprompted while they haven't seen the
banner, and don't record the version any other way: the instructions run at
acknowledgement, so acknowledging around the skill silently drops them."

jq -nc --arg banner "$banner" --arg context "$context" \
  '{systemMessage: $banner, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}}'
