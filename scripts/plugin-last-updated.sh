#!/usr/bin/env bash
# Print when each installed plugin was last updated, as an age the report can
# show beside its result.
#
# With marketplace auto-update on, a plugin is usually updated before the run
# reaches it, so the update pass reads ✅ current nearly everywhere. The age is
# what tells a plugin that moved an hour ago from one that hasn't moved in
# months. It comes from the install manifest's `lastUpdated`, which Claude Code
# writes when an install or update lands a version, and leaves alone when an
# update finds nothing newer.
#
# A key can carry one record per scope. The user-scope record is the one
# `claude plugin update` writes, so its time is the key's; a key with no
# user-scope record takes its most recent one. Another scope's record is often
# a fresh install of the same version, and reading it would call an old version
# new.
#
#   <key>|<lastUpdated>|<age>
#
# <age> is `just now` under an hour, then `<n>h ago`, `<n>d ago` under two
# weeks, `<n>w ago` under two months, `<n>mo ago` under a year, and `<n>y ago`.
# A record whose time is missing or doesn't parse prints `-` and `unknown`,
# and a time ahead of the clock reads `just now`.
#
# Usage:  plugin-last-updated.sh
# Exit:   0 = printed (with or without rows)
#         1 = jq missing, or the install manifest missing or unparseable
#
# Env:    CLAUDE_PLUGINS_DIR   override ~/.claude/plugins (tests)
#         SHIPSHAPE_NOW        the current time, in epoch seconds (tests)

# covers: REPORT-14
set -euo pipefail
. "${BASH_SOURCE[0]%/*}/platform.sh"

plugins="${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}"
manifest="$plugins/installed_plugins.json"

die() { echo "plugin-last-updated: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq not on PATH; cannot read the install manifest"
[ -f "$manifest" ] || die "no install manifest at $manifest"

case "${SHIPSHAPE_NOW:-}" in
  '') now='now' ;;
  *[!0-9]*) die "SHIPSHAPE_NOW is not epoch seconds: $SHIPSHAPE_NOW" ;;
  *) now="$SHIPSHAPE_NOW" ;;
esac

jq -re "$now as \$now"' |
  def epoch: try ((split(".")[0] | rtrimstr("Z")) + "Z" | fromdateiso8601) catch null;
  def age($s):
    if $s == null then "unknown"
    elif $s < 3600 then "just now"
    elif $s < 86400 then "\($s / 3600 | floor)h ago"
    elif $s < 14 * 86400 then "\($s / 86400 | floor)d ago"
    elif $s < 61 * 86400 then "\($s / (7 * 86400) | floor)w ago"
    elif $s < 365 * 86400 then "\($s / (30 * 86400) | floor)mo ago"
    else "\($s / (365 * 86400) | floor)y ago" end;
  (.plugins | objects) // error("no .plugins object")
  | to_entries[]
  | .key as $k
  | [.value[]? | objects | . + {t: ((.lastUpdated | strings | epoch) // null)}]
  | (map(select(.scope == "user")) | first)
      // (map(select(.t != null)) | max_by(.t))
      // first
  | select(. != null)
  | (if .t == null then null else ([$now - .t, 0] | max) end) as $s
  | "\($k)|\(if .t == null then "-" else .lastUpdated end)|\(age($s))"
' "$manifest" 2>/dev/null || {
  # -e exits 4 when the manifest holds no plugins at all; that's an empty
  # answer, not a failure.
  rc=$?
  [ "$rc" -eq 4 ] && exit 0
  die "install manifest at $manifest does not parse"
}
