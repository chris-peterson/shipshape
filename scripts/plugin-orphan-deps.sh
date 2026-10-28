#!/usr/bin/env bash
# List the auto-installed dependencies no installed plugin needs any more — the
# ones `claude plugin prune` would remove — so the reconcile can uninstall them
# with --keep-data instead.
#
# A plugin pulled in through another plugin's `dependencies` is written to
# enabledPlugins like any other, so it stays in the desired set after the plugin
# that needed it is gone, and the diff never reads it as an extra. `prune`
# removes it, but deletes its data dir with it and has no flag to keep one.
# Claude Code decides which dependencies are still needed; this script reads
# that verdict from `prune --dry-run` and checks each key against the install
# manifest's `"auto": true`, so a change in the CLI's wording stops the step
# rather than naming a plugin the user installed themselves.
#
#   <key>|<version>
#
# Keys whose origin is not a registered marketplace are left out (RECON-16).
#
# Usage:  plugin-orphan-deps.sh
# Exit:   0 = listed (with or without rows)
#         1 = jq missing, an input unreadable, or `prune --dry-run` printed
#             something this script doesn't recognize — nothing listed
#
# Env:    CLAUDE_PLUGINS_DIR  override ~/.claude/plugins (tests)
#         CLAUDE_CLI          override the `claude` binary (tests)

# covers: RECON-18
set -euo pipefail
. "${BASH_SOURCE[0]%/*}/platform.sh"

plugins="${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}"
claude="${CLAUDE_CLI:-claude}"
registry="$plugins/known_marketplaces.json"
manifest="$plugins/installed_plugins.json"

die() { echo "plugin-orphan-deps: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq not on PATH; cannot list orphaned dependencies"

[ -f "$registry" ] || die "no marketplace registry at $registry"
marketplaces=$(jq -ce 'keys' "$registry" 2>/dev/null) \
  || die "marketplace registry at $registry does not parse"
[ -f "$manifest" ] || die "no install manifest at $manifest"
auto_keys=$(jq -ce '[.plugins | to_entries[] | select(any(.value[]; .auto == true)) | .key]' "$manifest" 2>/dev/null) \
  || die "install manifest at $manifest does not parse"

dry=$("$claude" plugin prune --dry-run) || die "\`claude plugin prune --dry-run\` failed"

header_re='^([0-9]+) auto-installed plugins? no longer needed at user scope:$'
entry_re='^  ([^ ]+@[^ ]+) \((.*)\)$'

rows=()
expected=""
while IFS= read -r line; do
  line="${line%$'\r'}"
  if [ -z "$line" ]; then
    continue
  elif [[ $line == "Nothing to prune"* ]]; then
    expected=0
  elif [[ $line =~ $header_re ]]; then
    expected="${BASH_REMATCH[1]}"
  elif [[ $line =~ $entry_re ]]; then
    rows+=("${BASH_REMATCH[1]}|${BASH_REMATCH[2]}")
  elif [[ $line == "(dry run"* ]]; then
    continue
  else
    die "unrecognized \`prune --dry-run\` line: $line"
  fi
done <<<"$dry"

[ -n "$expected" ] || die "\`prune --dry-run\` printed no summary line"
[ "${#rows[@]}" -eq "$expected" ] \
  || die "\`prune --dry-run\` announced $expected plugin(s) but listed ${#rows[@]}"

for row in ${rows[@]+"${rows[@]}"}; do
  key="${row%%|*}"
  jq -e --arg k "$key" 'index($k) != null' <<<"$auto_keys" >/dev/null \
    || die "$key is not marked auto-installed in $manifest; not listing any"
done

for row in ${rows[@]+"${rows[@]}"}; do
  key="${row%%|*}"
  jq -e --arg o "${key##*@}" 'index($o) != null' <<<"$marketplaces" >/dev/null \
    && printf '%s\n' "$row"
done
exit 0
