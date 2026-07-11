#!/usr/bin/env bash
# DOCUMENTATION: Enforce marketplace auto-update.
# SessionStart hook: enforce marketplace auto-update.
#
# Sets "autoUpdate": true for every known marketplace under
# extraKnownMarketplaces in ~/.claude/settings.json — the documented,
# declarative surface Claude Code reads at startup
# (https://code.claude.com/docs/en/discover-plugins). Claude Code loads
# settings BEFORE SessionStart hooks run, so a change here takes effect on the
# NEXT launch; from then on each marketplace refreshes and updates its plugins
# automatically at startup.
#
# The write is idempotent: it happens only when a marketplace is missing the
# flag, so steady state is a no-op and settings.json isn't churned every
# session. Existing extraKnownMarketplaces entries and all other settings keys
# are preserved.

set -euo pipefail

KNOWN="$HOME/.claude/plugins/known_marketplaces.json"
SETTINGS="$HOME/.claude/settings.json"

# No marketplaces registered yet → nothing to enforce.
[ -s "$KNOWN" ] || exit 0

if ! command -v jq >/dev/null 2>&1; then
  printf '# shipshape\n\nMarketplace auto-update needs `jq`, which is not on PATH. Install jq to enable enforcement.\n'
  exit 0
fi

# Start from existing settings, or an empty object if none exists yet.
current='{}'
[ -s "$SETTINGS" ] && current="$(cat "$SETTINGS")"
known="$(cat "$KNOWN")"

# Marketplaces not yet auto-updating (drives both the decision and the report).
pending="$(jq -rn --argjson known "$known" --argjson settings "$current" '
  ($settings.extraKnownMarketplaces // {}) as $ex
  | $known | keys[]
  | select(($ex[.].autoUpdate // false) != true)
')"

# Everything already auto-updating → no-op.
[ -n "$pending" ] || exit 0

# Force autoUpdate:true for every known marketplace, deep-merged over whatever
# extraKnownMarketplaces already holds so unrelated entries survive.
updated="$(jq -n --argjson known "$known" --argjson settings "$current" '
  ($known | to_entries
    | map({key: .key, value: {source: .value.source, autoUpdate: true}})
    | from_entries) as $desired
  | $settings
  | .extraKnownMarketplaces = ((.extraKnownMarketplaces // {}) * $desired)
')"

tmp="$(mktemp "${SETTINGS}.XXXXXX")"
printf '%s\n' "$updated" > "$tmp"
mv "$tmp" "$SETTINGS"

printf '# shipshape: marketplace auto-update enabled\n\n'
printf 'Set autoUpdate=true in ~/.claude/settings.json for:\n'
printf '%s\n' "$pending" | sed 's/^/  - /'
printf '\nTakes effect on the next Claude Code launch.\n'
