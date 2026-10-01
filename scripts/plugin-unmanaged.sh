#!/usr/bin/env bash
# List the installed and desired plugins whose origin is not a registered
# marketplace — the ones the reconcile leaves alone.
#
# A `<plugin>@<origin>` key names a marketplace everywhere except where Claude
# Code puts something else there: `<name>@synced` is a plugin turned on in
# claude.ai and governed there, which nothing local installed and no local
# marketplace can update or reinstall. Diffed like the rest, it reads as an
# extra to uninstall, or, enabled in settings, as a missing install that cannot
# succeed. The rule is the registry, not the word `synced`, so it matches
# PRUNE-16's for the cache and covers an origin Claude Code adds later.
#
#   <key>|installed|<scope>|<enabled|disabled>
#   <key>|desired|-|<true|false>
#
# Usage:  plugin-unmanaged.sh
# Exit:   0 = classified (with or without rows)
#         1 = jq missing, or an input unreadable — nothing classified. An
#             unreadable registry would make every plugin unmanaged, and an
#             unreadable list or settings file would hide rows, so each one
#             stops the reconcile rather than reading as empty.
#
# Env:    CLAUDE_PLUGINS_DIR    override ~/.claude/plugins (tests)
#         CLAUDE_SETTINGS_FILE  override ~/.claude/settings.json (tests)
#         CLAUDE_CLI            override the `claude` binary (tests)

# covers: RECON-16
set -euo pipefail

plugins="${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}"
settings="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
claude="${CLAUDE_CLI:-claude}"
registry="$plugins/known_marketplaces.json"

die() { echo "plugin-unmanaged: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq not on PATH; cannot classify plugins"

[ -f "$registry" ] || die "no marketplace registry at $registry"
marketplaces=$(jq -ce 'keys' "$registry" 2>/dev/null) \
  || die "marketplace registry at $registry does not parse"

list=$("$claude" plugin list --json) || die "\`claude plugin list --json\` failed"
printf '%s' "$list" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || die "\`claude plugin list --json\` did not print a JSON array"

desired='{}'
if [ -f "$settings" ]; then
  desired=$(jq -ce '.enabledPlugins // {}' "$settings" 2>/dev/null) \
    || die "settings file at $settings does not parse"
fi

printf '%s' "$list" | jq -r --argjson mps "$marketplaces" --argjson desired "$desired" '
  def unmanaged: (split("@") | last) as $o | ($mps | index($o)) == null;
  (.[] | select(.id | unmanaged)
       | "\(.id)|installed|\(.scope)|\(if .enabled then "enabled" else "disabled" end)"),
  ($desired | to_entries[] | select(.key | unmanaged)
       | "\(.key)|desired|-|\(.value)")'
