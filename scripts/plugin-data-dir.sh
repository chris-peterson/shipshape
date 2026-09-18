#!/usr/bin/env bash
# Print the directory shipshape's version state lives in, given the one Claude
# Code handed the session.
#
# Claude Code names a plugin's persistent data directory `<plugin>-<marketplace>`,
# and `<plugin>-inline` when the plugin is mounted with --plugin-dir instead of
# installed. Same machine, same user, same Claude Code version — so a session
# started that way reads its own empty lane and concludes shipshape has never
# run here: the acknowledged-version pin resets, the version-change guide is
# gone, and the deep-scan declaration reads as unconfigured, which sends the
# skill into a first run for decisions already on disk. VERSION-43 sends the
# user into precisely such a session, so the state has to follow them into it.
#
# The install manifest is what resolves it, rather than a `<plugin>-*` glob over
# the sibling directories: `mate-*` matches a second plugin actually named
# `mate-extra`, and a data dir left behind by an uninstall outlives the install
# it belonged to. The manifest's keys are `<plugin>@<marketplace>`, which names
# the lane exactly.
#
# Usage:  plugin-data-dir.sh [<data-dir>]     (default: $CLAUDE_PLUGIN_DATA)
#
# Exit:   0 = a directory was printed
#         1 = nothing to resolve, or jq is missing
#
# Env:    CLAUDE_PLUGIN_DATA  the directory to resolve, when no argument is given
#         CLAUDE_PLUGINS_DIR  override ~/.claude/plugins (tests)

# covers: VERSION-44
set -euo pipefail

data="${1:-${CLAUDE_PLUGIN_DATA:-}}"
if [ -z "$data" ]; then
  echo "plugin-data-dir: no directory given and CLAUDE_PLUGIN_DATA is unset" >&2
  exit 1
fi

base=${data##*/}
case "$base" in
  *-inline) ;;
  *) printf '%s\n' "$data"; exit 0 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "plugin-data-dir: jq not on PATH; cannot read the install manifest" >&2
  exit 1
fi

plugins="${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}"
manifest="$plugins/installed_plugins.json"
name=${base%-inline}

# An unreadable manifest is not one naming no marketplace, so both leave the
# session in its own lane: re-answering a question is recoverable, and writing
# into a lane resolved from a guess is not.
if [ ! -f "$manifest" ]; then
  printf '%s\n' "$data"
  exit 0
fi
if ! markets=$(jq -r --arg n "$name" '
      (.plugins // {}) | keys[] | select(startswith($n + "@")) | ltrimstr($n + "@")
    ' "$manifest" 2>/dev/null); then
  echo "plugin-data-dir: $manifest is not readable; staying in $base" >&2
  printf '%s\n' "$data"
  exit 0
fi

count=$(printf '%s' "$markets" | grep -c . || true)
case "$count" in
  0) printf '%s\n' "$data" ;;
  1) printf '%s/%s-%s\n' "${data%/*}" "$name" "$markets" ;;
  *) echo "plugin-data-dir: $name is installed from $count marketplaces; staying in $base" >&2
     printf '%s\n' "$data" ;;
esac
