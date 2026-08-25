#!/usr/bin/env bash
# Enumerate the plugin cache and data directories and classify what can be pruned.
#
# Prints one pipe-delimited row per entry that is NOT part of a current install,
# plus a trailing `#totals` line. Entries backing a live install are omitted:
# this is the by-exception list the maintenance skill reports and feeds to
# plugin-cache-prune.sh.
#
#   <path>|<class>|<verdict>|<size>
#
#   path     relative to ~/.claude/plugins — `cache/<mp>/<plugin>/<version>`
#            or `data/<slug>`; the form plugin-cache-prune.sh accepts
#   class    stale | orphan | empty-plugin | orphan-data | unknown-origin
#   verdict  prunable | in-use | skipped   (cache)    empty | nonempty  (data)
#   size     human-readable, e.g. 3.1M
#
# Classification is against `installed_plugins.json`, whose rows each record an
# `installPath`. That set IS the set of version dirs backing a current install,
# so a dir is current because the manifest points at it — not because its
# version string was matched against `claude plugin list`. It gets the shared
# on-disk install right for free: a dir two marketplaces resolve to is one row's
# installPath, so it reads as current under both.
#
# An origin shipshape does not recognize is reported and never pruned. The top
# level of cache/ is a marketplace name everywhere except where Claude Code puts
# something else there: `synced` holds plugins turned on in claude.ai, which
# nothing local installed and nothing local can reinstall. Those have no manifest
# row, so classifying them by the manifest alone would call them orphans and
# delete a running plugin's code. Reporting rather than ignoring is deliberate:
# a marketplace the user removed leaves real orphans behind, and silence would
# lose them.
#
# Usage:  plugin-cache-scan.sh
# Exit:   0 = scanned (with or without findings)
#         1 = jq missing, or no install manifest — nothing classified
#
# Env:    CLAUDE_PLUGINS_DIR  override ~/.claude/plugins (tests)

# covers: PRUNE-01, PRUNE-02, PRUNE-03, PRUNE-04, PRUNE-05, PRUNE-12, PRUNE-16
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugins="${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}"
manifest="$plugins/installed_plugins.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "plugin-cache-scan: jq not on PATH; cannot read the install manifest" >&2
  exit 1
fi
if [ ! -f "$manifest" ]; then
  echo "plugin-cache-scan: no install manifest at $manifest" >&2
  exit 1
fi

# Every installPath the manifest records, newline-delimited. A row without one
# contributes nothing, which leaves its dirs classified by the key check below.
current_paths=$(jq -r '[.plugins // {} | .[][] | .installPath // empty] | .[]' "$manifest")

# `<plugin>@<marketplace>` keys, and the `<plugin>-<marketplace>` data slugs they
# imply. The slug is hyphen-joined and plugin names contain hyphens, so the slug
# set is built from the keys and membership-tested — splitting a slug back into
# its two halves is ambiguous.
keys=$(jq -r '.plugins // {} | keys[]' "$manifest")
slugs=$(printf '%s\n' "$keys" | sed 's/@/-/')

# The marketplaces this install knows about. An unreadable or absent registry
# leaves the set empty, which makes every origin unrecognized and every entry
# unprunable — the conservative direction, and it says so on stderr.
registry="$plugins/known_marketplaces.json"
if [ -f "$registry" ]; then
  marketplaces=$(jq -r 'keys[]' "$registry" 2>/dev/null || true)
else
  marketplaces=""
fi
if [ -z "$marketplaces" ]; then
  echo "plugin-cache-scan: no marketplaces readable from $registry; nothing will be reported as prunable" >&2
fi

has_line() {  # $1 = needle, $2 = haystack
  printf '%s\n' "$2" | grep -qxF -- "$1"
}

size_kb() { du -sk "$1" 2>/dev/null | awk '{print $1}' || echo 0; }

human() {  # $1 = KB
  awk -v k="${1:-0}" 'BEGIN {
    if (k < 1024)        printf "%dK\n", k
    else if (k < 1048576) printf "%.1fM\n", k/1024
    else                  printf "%.1fG\n", k/1048576
  }'
}

stale=0; stale_in_use=0; orphan=0; orphan_in_use=0; empty_plugin=0; orphan_data=0
unknown=0; prunable_kb=0

# Does a data slug end in `-<one of our marketplaces>`? The slug is hyphen-joined
# and plugin names carry hyphens, so the origin is tested as a suffix rather than
# split out.
from_known_marketplace() {  # $1 = slug
  local mp
  while IFS= read -r mp; do
    [ -n "$mp" ] || continue
    case "$1" in *"-$mp") return 0 ;; esac
  done <<< "$marketplaces"
  return 1
}

# --- cache: ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/ ---------
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  rel="cache/${dir#"$plugins/cache/"}"

  if has_line "$dir" "$current_paths"; then continue; fi   # backs a current install

  origin="$(basename "$(dirname "$(dirname "$dir")")")"

  # Not a marketplace we know: not ours to delete, whatever the manifest says.
  if ! has_line "$origin" "$marketplaces"; then
    unknown=$((unknown + 1))
    printf '%s|unknown-origin|skipped|%s\n' "$rel" "$(human "$(size_kb "$dir")")"
    continue
  fi

  # Installed elsewhere -> a version this plugin has moved off of. Not installed
  # at all -> nothing on disk claims it.
  plugin_key="$(basename "$(dirname "$dir")")@$origin"
  if has_line "$plugin_key" "$keys"; then class=stale; else class=orphan; fi

  if bash "$here/plugin-cache-in-use.sh" "$dir" >/dev/null 2>&1; then
    verdict=in-use
  else
    verdict=prunable
  fi

  kb=$(size_kb "$dir")
  case "$class:$verdict" in
    stale:in-use)   stale_in_use=$((stale_in_use + 1)) ;;
    stale:prunable) stale=$((stale + 1));  prunable_kb=$((prunable_kb + kb)) ;;
    orphan:in-use)  orphan_in_use=$((orphan_in_use + 1)) ;;
    orphan:prunable) orphan=$((orphan + 1)); prunable_kb=$((prunable_kb + kb)) ;;
  esac
  printf '%s|%s|%s|%s\n' "$rel" "$class" "$verdict" "$(human "$kb")"
done < <(find "$plugins/cache" -mindepth 3 -maxdepth 3 -type d 2>/dev/null | sort)

# --- cache: a `<marketplace>/<plugin>/` dir whose versions are all gone -------
# Pruning the last version of a plugin leaves its parent behind. Report only the
# genuinely empty ones: a dir still holding a stray file is something to look at
# by hand, not a leftover to reclaim, and reporting it every run is noise.
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then continue; fi
  if ! has_line "$(basename "$(dirname "$dir")")" "$marketplaces"; then continue; fi
  empty_plugin=$((empty_plugin + 1))
  printf 'cache/%s|empty-plugin|prunable|0K\n' "${dir#"$plugins/cache/"}"
done < <(find "$plugins/cache" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort)

# --- data: ~/.claude/plugins/data/<plugin>-<marketplace>/ --------------------
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  slug="$(basename "$dir")"

  # A `-inline` slug is the artifact of testing a plugin from a local directory.
  # It is not drift and it is not an orphan; it never appears in this report.
  case "$slug" in *-inline) continue ;; esac
  if has_line "$slug" "$slugs"; then continue; fi          # matches an installed plugin

  if ! from_known_marketplace "$slug"; then
    unknown=$((unknown + 1))
    printf 'data/%s|unknown-origin|skipped|%s\n' "$slug" "$(human "$(size_kb "$dir")")"
    continue
  fi

  kb=$(size_kb "$dir")
  if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then verdict=empty; else verdict=nonempty; fi
  if [ "$verdict" = empty ]; then prunable_kb=$((prunable_kb + kb)); fi
  orphan_data=$((orphan_data + 1))
  printf 'data/%s|orphan-data|%s|%s\n' "$slug" "$verdict" "$(human "$kb")"
done < <(find "$plugins/data" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

printf '#totals stale=%d stale_in_use=%d orphan=%d orphan_in_use=%d empty_plugin=%d orphan_data=%d unknown_origin=%d reclaimable=%s\n' \
  "$stale" "$stale_in_use" "$orphan" "$orphan_in_use" "$empty_plugin" "$orphan_data" "$unknown" "$(human "$prunable_kb")"
