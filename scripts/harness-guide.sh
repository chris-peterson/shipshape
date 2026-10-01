#!/usr/bin/env bash
# Read and seed the user's harness maintenance guide: the instructions they want
# carried out after each half of /maintain-harness.
#
# Usage:  harness-guide.sh --path              print the guide's path
#         harness-guide.sh --status            report {path, present, upgrade, plugins, stray} as JSON
#         harness-guide.sh --section <name>    print one section's content: upgrade | plugins
#         harness-guide.sh --seed              write the template if absent, and print the path
#         harness-guide.sh --installers        list the CLI installers installed plugins ship, as /<plugin>:<name>
#
# Exit:   0 = done
#         1 = CLAUDE_PLUGIN_DATA is unset or can't be resolved, jq is missing,
#             or there is no install manifest (--installers)
#         2 = usage
#
# One file, two sections, because the default run does both halves in a row and
# a step in one half often depends on the other: a CLI installer only re-pins
# correctly after /reload-plugins. Each half carries out only its own section,
# since they fire on different events: an upgrade once per Claude Code version,
# plugins after any run that changed one. A `###` subheading (one per plugin,
# say) stays inside its section. Text outside the two sections is never carried
# out, and is reported on stderr rather than dropped without a word.
#
# Nothing here creates the guide on a read except a migration: an absent guide
# is what tells the skill to walk the user through writing one. --seed is that
# write, and the seed holds only comments under its two headings, so both
# sections read as unfilled.
#
# The guide lives in $CLAUDE_PLUGIN_DATA, which survives plugin updates; a
# version cache is what the plugins half prunes.
#
# Env:    CLAUDE_PLUGIN_DATA  shipshape's data dir
#         CLAUDE_PLUGINS_DIR  override ~/.claude/plugins (tests)

# covers: GUIDE-01, GUIDE-02, GUIDE-03, GUIDE-04, GUIDE-05, GUIDE-06, GUIDE-12
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
BASH="${BASH:-bash}"
PLUGINS_DIR="${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}"

UPGRADE_HEADING="## After a Claude Code upgrade"
PLUGINS_HEADING="## After plugins change"

mode=""; section=""
case "${1:-}" in
  --path)       mode=path ;;
  --status)     mode=status ;;
  --seed)       mode=seed ;;
  --installers) mode=installers ;;
  --section)
    mode=section; section="${2:-}"
    case "$section" in upgrade|plugins) ;; *) mode="" ;; esac ;;
esac
if [ -z "$mode" ]; then
  printf 'usage: %s --path | --status | --section upgrade|plugins | --seed | --installers\n' "$SELF" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'shipshape: jq is required and was not found.\n' >&2
  exit 1
fi

# An installer is a command a plugin ships to install its own CLI wrapper, which
# stays pinned to the version path it ran from. The current installPath is the
# one to read: a stale version cache still holds the old installers.
# covers: GUIDE-12
if [ "$mode" = installers ]; then
  manifest="$PLUGINS_DIR/installed_plugins.json"
  if [ ! -r "$manifest" ]; then
    printf 'shipshape: no install manifest at %s.\n' "$manifest" >&2
    exit 1
  fi
  jq -r '.plugins | to_entries[] | (.key | split("@")[0]) as $p
         | .value[] | select(.installPath) | "\($p)\t\(.installPath)"' "$manifest" \
    | sort -u | while IFS=$'\t' read -r plugin root; do
        for cmd in "$root"/commands/install-*.md; do
          [ -f "$cmd" ] && printf '/%s:%s\n' "$plugin" "$(basename "$cmd" .md)"
        done
        [ -f "$root/skills/install-cli/SKILL.md" ] && printf '/%s:install-cli\n' "$plugin"
        true
      done | sort -u
  exit 0
fi

if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
  printf 'shipshape: CLAUDE_PLUGIN_DATA is unset; cannot find the harness maintenance guide.\n' >&2
  exit 1
fi

# A --plugin-dir session is handed its own `<plugin>-inline` data dir; the guide
# the user wrote lives in the installed plugin's lane.
data="$("$BASH" "${SELF%/*}/plugin-data-dir.sh" "$CLAUDE_PLUGIN_DATA")"
guide="$data/harness-maintenance-guide.md"

if [ "$mode" = path ]; then
  printf '%s\n' "$guide"
  exit 0
fi

content() {  # $1 file — its lines with comments and leading blanks removed
  "$BASH" "${SELF%/*}/guide-content.sh" "$1"
}

template() {  # $1 upgrade body, $2 plugins body — each an example comment when empty
  local upgrade_example='<!-- e.g.  Re-train my AI artifacts against this version: /my-retrain-command -->'
  local plugins_example="<!-- e.g.  After an update, refresh each plugin's CLI:
         1. /reload-plugins
         2. /my-plugin:install-my-plugin -->"
  cat <<TEMPLATE
<!-- shipshape: what /maintain-harness carries out after each of its halves. -->
<!-- Write instructions under the heading for when they should run, naming the
     commands you want run:

       After a Claude Code upgrade: once, when you acknowledge a new version.
       After plugins change: at the end of a run that updated, installed, or
       uninstalled a plugin.

     A ### subheading inside a section (one per plugin, say) stays part of it,
     and text outside the two sections is never run. A command only you can
     type is listed for you to run, in the order written. Comments are dropped,
     so nothing fires while a section holds only comments. -->

$UPGRADE_HEADING

${1:-$upgrade_example}

$PLUGINS_HEADING

${2:-$plugins_example}
TEMPLATE
}

# The version-change guide shipped first, at its own path; the post-maintenance
# guide came after. Whenever the guide is absent and either is still on disk,
# its content moves under the matching heading, with any `##` of its own demoted
# so it can't open a section. A step naming /plugin-maintenance is dropped: the
# plugins heading is what runs plugin maintenance now.
# Each old file is then removed, so nothing reads it again.
# covers: GUIDE-06
legacy() {  # $1 file — its content, ready to sit under a heading
  [ -r "$1" ] || return 0
  content "$1" | sed -E -e '/\/plugin-maintenance([^-[:alnum:]]|$)/d' -e 's/^##/###/'
}
migrate() {
  local legacy_upgrade="$data/on-claude-code-version-change.md"
  local legacy_plugins="$data/after-plugin-maintenance.md"
  [ -e "$guide" ] && return 0
  [ -e "$legacy_upgrade" ] || [ -e "$legacy_plugins" ] || return 0
  local up pl
  up="$(legacy "$legacy_upgrade")"
  pl="$(legacy "$legacy_plugins")"
  if [ -n "$up$pl" ]; then
    template "$up" "$pl" > "$guide"
    printf 'shipshape: moved your guide steps into %s.\n' "$guide" >&2
  fi
  local f
  for f in "$legacy_upgrade" "$legacy_plugins"; do
    rm -f "$f"
  done
}
migrate

# covers: GUIDE-02
if [ "$mode" = seed ]; then
  if [ ! -e "$guide" ]; then
    mkdir -p "$data"
    template "" "" > "$guide"
  fi
  printf '%s\n' "$guide"
  exit 0
fi

# Read once: every answer below is cut from this one pass over the file.
text=""
[ -e "$guide" ] && text="$(content "$guide")"

# Cuts the content into its two sections. `want` is upgrade or plugins (that
# section's lines), stray (text in neither: before the first heading, or under a
# `##` heading that isn't one of the two), or flags (three 0/1 words: upgrade,
# plugins, and stray each hold anything).
# covers: GUIDE-03
split() {  # $1 want
  printf '%s\n' "$text" | awk -v want="$1" -v up="$UPGRADE_HEADING" -v pl="$PLUGINS_HEADING" '
    function norm(s) { sub(/[[:space:]]+$/, "", s); return tolower(s) }
    /^##[[:space:]]/ {
      h = norm($0)
      if (h == tolower(up)) cur = "upgrade"
      else if (h == tolower(pl)) cur = "plugins"
      else { cur = "stray"; has["stray"] = 1; if (want == "stray") print $0 }
      next
    }
    {
      c = (cur == "" ? "stray" : cur)
      if ($0 != "") has[c] = 1
      if (c != want) next
      if (!started && $0 == "") next
      started = 1; buf = buf $0 "\n"
      if ($0 != "") { printf "%s", buf; buf = "" }
    }
    END { if (want == "flags") print has["upgrade"] + 0, has["plugins"] + 0, has["stray"] + 0 }
  '
}

warn_stray() {  # $1 stray text
  [ -z "$1" ] && return 0
  printf 'shipshape: %s has text outside its two sections, which is never carried out: %s\n' \
    "$guide" "$(printf '%s' "$1" | head -n 1)" >&2
}

if [ "$mode" = section ]; then
  [ -n "$text" ] || exit 0
  warn_stray "$(split stray)"
  split "$section"
  exit 0
fi

present=false; upgrade=0; plugins=0; stray=0
if [ -e "$guide" ]; then
  present=true
  read -r upgrade plugins stray <<<"$(split flags)"
  [ "$stray" = 1 ] && warn_stray "$(split stray)"
fi
jq -nc --arg path "$guide" --argjson present "$present" \
  --argjson upgrade "$upgrade" --argjson plugins "$plugins" --argjson stray "$stray" \
  '{path: $path, present: $present, upgrade: {filled: ($upgrade == 1)},
    plugins: {filled: ($plugins == 1)}, stray: ($stray == 1)}'
