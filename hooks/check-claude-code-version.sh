#!/usr/bin/env bash
# SessionStart hook: announce a Claude Code version change, and hand the
# handling to the skill that runs the instructions you wrote for it.
#
#   check-claude-code-version.sh              the hook — announce while a version is unacknowledged, when opted in
#   check-claude-code-version.sh --ack [ver]  acknowledge: record `ver` (default: the running version)
#   check-claude-code-version.sh --status     report both versions, the guide's upgrade section and the declaration, as JSON
#
# Claude Code updates itself in the background, and the new version takes effect
# at the next launch. Two things go unnoticed when it does: the change itself,
# which turns a new behavior into a mystery until you think to check
# `claude --version` against the changelog; and the staleness it leaves in your
# AI artifacts, whose hook schemas, settings keys, and skill frontmatter were
# written against the version before it. Both key off the same comparison, so
# they're one hook: one `claude --version`, one marker, one emit.
#
# The marker holds the version the user has *acknowledged*, not the one last
# seen, so a version change survives the session it appears in — a session
# opened to do something else can't swallow it. A first run has nothing to
# compare against and writes the marker silently, which makes installing
# shipshape the acknowledgement of whatever version you're already on.
#
# The two halves land on the two channels a SessionStart hook has. The banner
# goes out as `systemMessage`, the only hook output Claude Code shows the user,
# and it names `/maintain-harness` so the person reading it has something to
# act on. `additionalContext` carries the same handoff for Claude: what moved,
# and the skill to run once the user has taken the update in.
#
# The guide the user wrote is dispatched by that skill, not emitted here. A hook
# cannot invoke a slash command, so handing over the document's text was once
# the only way to make it run — but an opted-in hook fires at every session start
# while a version is unacknowledged, and a one-time upgrade errand then ran again in
# every window that opened before someone dismissed the banner. Acknowledgement
# is the moment the errand belongs to, and the skill owns that moment: it reads
# the guide's upgrade section, carries it out, then records the version.
# scripts/harness-guide.sh owns the guide itself.
#
# State and document both live under $CLAUDE_PLUGIN_DATA, the directory Claude
# Code guarantees survives plugin updates
# (https://code.claude.com/docs/en/plugins-reference#persistent-data-directory).
# A version cache would not: an update moves shipshape to a new version dir, and
# /maintain-harness plugins prunes the old one.
#
# The banner is opt-in: set SHIPSHAPE_VERSION_NOTICE to a truthy value (1, on,
# true, yes, in any case) in the `env` block of ~/.claude/settings.json. It's for
# people who re-tune their harness on every Claude Code release; for everyone
# else a banner at every session start is noise. Without it, the hook still
# records a first-run baseline, so /maintain-harness claude-code has a version
# to walk from when someone runs it.

set -euo pipefail

CHANGELOG="https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md"
SELF="${BASH_SOURCE[0]}"
BASH="${BASH:-bash}"
VERSION_RE='^[0-9][0-9A-Za-z.+-]*$'

mode=hook
ack_version=""
case "${1:-}" in
  "")        ;;
  --ack)     mode=ack; ack_version="${2:-}" ;;
  --status)  mode=status ;;
  *)         printf 'usage: %s [--ack [version] | --status]\n' "$SELF" >&2; exit 2 ;;
esac

# A hook reports and stands down: erroring every session start is noise, and the
# same convention covers a missing jq in enforce-autoupdate.sh. The other modes
# have a caller waiting on an answer, so a missing prerequisite is theirs to
# see — nothing was recorded and nothing can be reported.
# covers: VERSION-13, VERSION-14
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

# covers: VERSION-42
# A --plugin-dir session is handed its own `<plugin>-inline` data dir, which
# would read as a machine that has never run shipshape. plugin-data-dir.sh
# resolves it back to the installed plugin's lane; it needs the jq checked for
# above, so it runs here rather than at the top.
if ! CLAUDE_PLUGIN_DATA="$("$BASH" "${SELF%/*}/../scripts/plugin-data-dir.sh" "$CLAUDE_PLUGIN_DATA")"; then
  bail
fi

marker="$CLAUDE_PLUGIN_DATA/acknowledged-version"
GUIDE_SCRIPT="${SELF%/*}/../scripts/harness-guide.sh"

record() {  # $1 version — written via a temp file so a concurrent reader never sees a torn marker
  mkdir -p "$CLAUDE_PLUGIN_DATA"
  local tmp; tmp="$(mktemp "${marker}.XXXXXX")"
  printf '%s\n' "$1" > "$tmp"
  mv "$tmp" "$marker"
}

# stderr is dropped rather than folded in: a node warning or an update notice
# printed ahead of the version would otherwise be parsed *as* the version, and a
# warning that varies per run (a PID) would announce a change every session.
# covers: VERSION-01, VERSION-12
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

# covers: VERSION-08
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

notice_on() {
  case "$(printf '%s' "${SHIPSHAPE_VERSION_NOTICE:-}" | tr '[:upper:]' '[:lower:]')" in
    1|on|true|yes) return 0 ;;
    *)             return 1 ;;
  esac
}

# With a valid marker on disk there is nothing left for an un-opted hook to do,
# and exiting here skips the `claude --version` that every other path pays for.
# A missing or mangled marker falls through to be rewritten (VERSION-10).
# covers: VERSION-11
if [ "$mode" = hook ] && ! notice_on && [ -n "$acknowledged" ]; then
  exit 0
fi

current="$(read_version)" || bail

# GitHub slugifies the changelog's `## 2.1.227` heading by dropping the dots.
entry="$CHANGELOG#${current//./}"

# covers: VERSION-09, VERSION-10
if [ "$mode" = status ]; then
  # A query never writes: an unacknowledged version stays unacknowledged, so
  # asking what's pending can't be what dismisses it.
  # The guide's own reader answers for it, so "filled" has one definition.
  # covers: VERSION-06
  guide="$("$BASH" "$GUIDE_SCRIPT" --status)"

  # Whether the deep-scan set has ever been declared is what separates a first
  # run from a configured one, and `--status` is the one command the skill runs
  # on every path. Reported anywhere else, the mode is picked from `filled` —
  # which is false on a finished configuration too, since an empty guide is the
  # ordinary outcome of one.
  #
  # An unreadable declaration is not an absent one: reported as unconfigured, it
  # sends the skill into a first run that asks for every decision the user has
  # already made. It answers null, and says why on stderr.
  # covers: VERSION-39
  decl_path="$CLAUDE_PLUGIN_DATA/version-scan-targets.json"
  declaration='{"configured": null, "examined": null, "skipped": null}'
  if [ ! -f "$decl_path" ]; then
    declaration='{"configured": false, "examined": 0, "skipped": 0}'
  elif jq -e 'type == "object" and (.targets | type == "object")' "$decl_path" >/dev/null 2>&1; then
    declaration="$(jq -c '(.targets | to_entries) as $t
      | {configured: ($t | length > 0),
         examined: ([$t[] | select(.value.action != "skip")] | length),
         skipped:  ([$t[] | select(.value.action == "skip")] | length)}' "$decl_path")"
  else
    printf 'shipshape: %s is not readable as a declaration; reporting its state as unknown.\n' "$decl_path" >&2
  fi

  jq -n --arg ack "$acknowledged" --arg cur "$current" --arg entry "$entry" \
        --argjson guide "$guide" \
        --arg decl "$decl_path" --argjson declaration "$declaration" \
    '{acknowledged: (if $ack == "" then null else $ack end),
      current: $cur,
      pending: ($ack != "" and $ack != $cur),
      changelog: $entry,
      guide: {path: $guide.path, filled: $guide.upgrade.filled},
      declaration: ({path: $decl} + $declaration)}'
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
# covers: VERSION-02, VERSION-03, VERSION-07
# `<source>: <resolution>  # <reasoning>`. Session banners stack, one line per
# plugin with something to say, so the command to type sits where the eye lands
# and the rest goes after the marker. The changelog entry moves to the context:
# the skill named here is what walks the reader through it anyway.
banner="Claude Code: /maintain-harness  # $acknowledged → $current"

# covers: VERSION-04, VERSION-05, HARNESS-07
context="Claude Code moved from $acknowledged to $current — $entry. The banner announcing it repeats every session until the version is acknowledged.

shipshape's \`/maintain-harness\` handles it: it walks what changed, carries
out the version-change instructions the user wrote, records the version, which
is what clears the banner, and then updates their plugins. Only the user can
start it. When they ask what changed or ask you to deal with the update, tell
them to type \`/maintain-harness\`, or \`/maintain-harness claude-code\` for the
upgrade alone. Don't record the version any other way: the instructions run at
acknowledgement, so acknowledging around the skill silently drops them."

jq -nc --arg banner "$banner" --arg context "$context" \
  '{systemMessage: $banner, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}}'
