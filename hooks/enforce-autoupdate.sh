#!/usr/bin/env bash
# SessionStart hook: enforce marketplace auto-update.
#
# Sets "autoUpdate": true for every known marketplace under
# extraKnownMarketplaces in ~/.claude/settings.json ($CLAUDE_CONFIG_DIR's where
# set) — the documented, declarative surface Claude Code reads at startup
# (https://code.claude.com/docs/en/discover-plugins). Claude Code loads
# settings BEFORE SessionStart hooks run, so a change here takes effect on the
# NEXT launch; from then on each marketplace refreshes and updates its plugins
# automatically, after a random delay of up to ten minutes into each session.
#
# The write is idempotent: it happens only when a marketplace is missing the
# flag, so steady state is a no-op and settings.json isn't churned every
# session. Existing extraKnownMarketplaces entries and all other settings keys
# are preserved.
#
# Managed config wins. Where a managed entry sets autoUpdate for a marketplace,
# true or false, the hook writes nothing for it and defers to that setting
# instead: a managed entry replaces a user entry of the same name whole, so a
# user-level flag would do nothing but churn settings.json.

# covers: AUTO-01, AUTO-02, AUTO-03, AUTO-04
set -euo pipefail
. "${BASH_SOURCE[0]%/*}/../scripts/platform.sh"

CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
KNOWN="$CONFIG/plugins/known_marketplaces.json"
SETTINGS="$CONFIG/settings.json"
REMOTE="$CONFIG/remote-settings.json"  # the server-managed settings cache
# The OS managed-settings directory (https://code.claude.com/docs/en/managed-settings).
case "${OSTYPE:-}" in
  darwin*)       MANAGED_DIR="/Library/Application Support/ClaudeCode" ;;
  msys*|cygwin*) MANAGED_DIR="$(cygpath -u 'C:\Program Files\ClaudeCode' 2>/dev/null || echo '/c/Program Files/ClaudeCode')" ;;
  *)             MANAGED_DIR="/etc/claude-code" ;;
esac
MANAGED_DIR="${SHIPSHAPE_MANAGED_SETTINGS_DIR:-$MANAGED_DIR}"

# No marketplaces registered yet → nothing to enforce.
[ -s "$KNOWN" ] || exit 0

# Without jq this hook can't write, and Claude Code doesn't auto-update a
# third-party marketplace on its own, so shipshape would never receive the
# release that fixes it. ensure_jq downloads one; when that fails too, the
# user is told on the one channel they see, since plain stdout here reaches only
# Claude. The reason is escaped by hand: there is no jq to build the JSON.
# Nor is there one to tell which marketplaces a managed source decides, so the
# banner says what shipshape can't do rather than claiming auto-update is off.
# covers: AUTO-05
if ! ensure_jq; then
  reason="${jq_unavailable//\\/\\\\}"
  reason="${reason//\"/\\\"}"
  printf '{"systemMessage": "shipshape cannot turn on marketplace auto-update; install jq, or /plugin → Marketplaces → Enable auto-update  # %s"}\n' "$reason"
  exit 0
fi

# Start from existing settings, or an empty object if none exists yet.
current='{}'
[ -s "$SETTINGS" ] && current="$(cat "$SETTINGS")"
known="$(cat "$KNOWN")"

# A managed file as one JSON object, or nothing: one that's missing or doesn't
# parse delivers no policy.
read_policy() { [ -s "$1" ] && jq -c 'select(type == "object")' "$1" 2>/dev/null; }

# Managed sources in Claude Code's rank order: the server-managed cache, then
# the OS file tier, which is managed-settings.json with managed-settings.d/*.json
# merged over it in name order, a later extraKnownMarketplaces entry replacing
# an earlier one of the same name whole. The MDM tier between them (a macOS
# configuration profile, HKLM) isn't a file this hook can read.
remote="$(read_policy "$REMOTE")" || remote='null'
files='null'
for f in "$MANAGED_DIR/managed-settings.json" "$MANAGED_DIR"/managed-settings.d/*.json; do
  doc="$(read_policy "$f")" || continue
  files="$(jq -cn --argjson a "$files" --argjson b "$doc" '
    ($a // {}) as $a | ($a + $b)
    | if $a.extraKnownMarketplaces or $b.extraKnownMarketplaces
      then .extraKnownMarketplaces = (($a.extraKnownMarketplaces // {}) + ($b.extraKnownMarketplaces // {}))
      else . end')"
done

# Marketplaces whose effective managed entry sets autoUpdate. The first source
# that delivers a policy key wins and the rest are ignored, unless the top
# source sets managedSourcesBehavior "merge", where a higher source's entry
# replaces a lower one's.
# covers: AUTO-07
managed="$(jq -cn --argjson tiers "[$remote,$files]" '
  def policy: keys - ["managedSourcesBehavior", "wslInheritsWindowsSettings"] | length > 0;
  [$tiers[] | objects] as $present
  | (if ($present[0].managedSourcesBehavior // "") == "merge"
     then [$present[] | select(policy)]
     else [first($present[] | select(policy))] end)
  | reduce reverse[] as $t ({}; . + ($t.extraKnownMarketplaces // {}))
  | [to_entries[] | select(.value | type == "object" and has("autoUpdate")) | .key]
')"

# Marketplaces not yet auto-updating (drives both the decision and the report).
# covers: JSON-01
pending="$(jq -rn --argjson known "$known" --argjson settings "$current" --argjson managed "$managed" '
  ($settings.extraKnownMarketplaces // {}) as $ex
  | $known | keys[]
  | select(IN($managed[]) | not)
  | select(($ex[.].autoUpdate // false) != true)
')"

# Everything already auto-updating → no-op.
[ -n "$pending" ] || exit 0

# Force autoUpdate:true for every known marketplace no managed source decides,
# deep-merged over whatever extraKnownMarketplaces already holds so unrelated
# entries survive, a user's own entry for a managed marketplace among them.
updated="$(jq -n --argjson known "$known" --argjson settings "$current" --argjson managed "$managed" '
  ($known | to_entries
    | map(select(.key | IN($managed[]) | not))
    | map({key: .key, value: {source: .value.source, autoUpdate: true}})
    | from_entries) as $desired
  | $settings
  | .extraKnownMarketplaces = ((.extraKnownMarketplaces // {}) * $desired)
')"

tmp="$(mktemp "${SETTINGS}.XXXXXX")"
printf '%s\n' "$updated" > "$tmp"
mv "$tmp" "$SETTINGS"

printf '# shipshape: marketplace auto-update enabled\n\n'
printf 'Set autoUpdate=true in %s for:\n' "${SETTINGS/#"$HOME"/\~}"
printf '%s\n' "$pending" | sed 's/^/  - /'
printf '\nTakes effect on the next Claude Code launch.\n'
