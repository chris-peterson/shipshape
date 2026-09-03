#!/usr/bin/env bash
# Answer which repos a version-change guide should analyze in depth, and record
# the user's decisions so the question is asked once rather than every upgrade.
#
# A plugin the user MAINTAINS is theirs to patch when a Claude Code release
# invalidates a hook schema, a settings key, or a frontmatter field. A plugin
# they merely USE is its own maintainer's errand. Only the first set is worth an
# in-depth pass, and nothing on disk distinguishes them: both are installed, and
# both have a source repo. So the set is declared, once, and this script keeps
# the declaration reconciled against what is actually installed.
#
# The declaration lives at $CLAUDE_PLUGIN_DATA/version-scan-targets.json:
#
#   { "version": 1,
#     "targets": {
#       "anchor@getty-claude-marketplace": { "action": "scan", "src": "/…/anchor" },
#       "frontend-design@claude-plugins-official": { "action": "skip" },
#       "shipyard": { "action": "scan", "src": "/…/shipyard" } } }
#
# A key holding `@` is an installed plugin, matched against the install
# manifest's own keys so drift is exact. A bare key is a repo the user added by
# hand — their plugin build tool, their rules repo — which reads the same CLI
# and the same schemas but ships as no plugin, so no manifest names it. Bare
# keys are never reported as gone.
#
# Usage:  version-scan-targets.sh --drift
#         version-scan-targets.sh --set <key> scan <src>
#         version-scan-targets.sh --set <key> skip
#         version-scan-targets.sh --forget <key>
#
# --drift prints the reconciliation as JSON and changes nothing:
#
#   { "new": [<key>…],                      installed, no decision recorded
#     "gone": [<key>…],                     decided, no longer installed
#     "unreadable": [{key,src}…],           decided `scan`, src is not a directory
#     "scan": [{key,src}…],                 the deep-scan set, ready to use
#     "skip": [<key>…],                     decided `skip`
#     "settled": <true|false> }             nothing to ask about
#
# `unreadable` is its own bucket rather than folded into `scan` or dropped: a
# recorded checkout that has moved is a question for the user, and scanning
# nothing while reporting a scan is the one outcome that must not happen. It
# keeps `settled` false until the user answers.
#
# Exit:   0 = answered
#         1 = jq missing, no install manifest, or CLAUDE_PLUGIN_DATA unset
#         2 = --set or --forget was called with arguments it cannot honor
#
# Env:    CLAUDE_PLUGIN_DATA  where the declaration is written (required)
#         CLAUDE_PLUGINS_DIR  override ~/.claude/plugins (tests)

# covers: VERSION-27, VERSION-28
set -euo pipefail

plugins="${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}"
manifest="$plugins/installed_plugins.json"
data="${CLAUDE_PLUGIN_DATA:-}"

if ! command -v jq >/dev/null 2>&1; then
  echo "version-scan-targets: jq not on PATH; cannot read the install manifest" >&2
  exit 1
fi
if [ -z "$data" ]; then
  echo "version-scan-targets: CLAUDE_PLUGIN_DATA is unset; nowhere to read or write the declaration" >&2
  exit 1
fi
if [ ! -f "$manifest" ]; then
  echo "version-scan-targets: no install manifest at $manifest" >&2
  exit 1
fi

decl="$data/version-scan-targets.json"

# An unreadable declaration is not an empty one. Rewriting it from scratch would
# discard every decision the user has already made, so stop and say so.
read_decl() {
  if [ ! -f "$decl" ]; then
    echo '{"version":1,"targets":{}}'
    return 0
  fi
  if ! jq -e 'type == "object" and (.targets | type == "object")' "$decl" >/dev/null 2>&1; then
    echo "version-scan-targets: $decl is not readable as a declaration; leaving it untouched" >&2
    return 1
  fi
  cat "$decl"
}

write_decl() {
  mkdir -p "$data"
  tmp=$(mktemp "$decl.XXXXXX")
  cat > "$tmp"
  mv "$tmp" "$decl"
}

case "${1:---drift}" in
  --drift)
    installed=$(jq -c '(.plugins // {}) | keys' "$manifest")
    decl_json=$(read_decl) || exit 1

    base=$(printf '%s' "$decl_json" | jq --argjson installed "$installed" '
      .targets as $t
      | ($installed - ($t | keys)) as $new
      | [$t | to_entries[] | select(.key | contains("@")) | .key] as $plugin_keys
      | [$t | to_entries[]
          | select(.value.action == "scan")
          | {key: .key, src: (.value.src // "")}] as $scan_rows
      | [$t | to_entries[] | select(.value.action == "skip") | .key] as $skip
      | {new: $new, gone: ($plugin_keys - $installed), scan: $scan_rows, skip: $skip}
    ')

    # Whether a recorded src is still a directory is a filesystem fact jq cannot
    # answer, so the split happens here and the two buckets are rebuilt from it.
    good='[]'
    unreadable='[]'
    while IFS=$'\t' read -r key src; do
      [ -n "$key" ] || continue
      row=$(jq -n --arg k "$key" --arg s "$src" '{key:$k, src:$s}')
      if [ -n "$src" ] && [ -d "$src" ]; then
        good=$(jq -n --argjson a "$good" --argjson r "$row" '$a + [$r]')
      else
        unreadable=$(jq -n --argjson a "$unreadable" --argjson r "$row" '$a + [$r]')
      fi
    done < <(printf '%s' "$base" | jq -r '.scan[] | [.key, .src] | @tsv')

    printf '%s' "$base" | jq --argjson good "$good" --argjson unreadable "$unreadable" '
      .scan = $good
      | .unreadable = $unreadable
      | .settled = ((.new | length) == 0 and (.gone | length) == 0
                    and (.unreadable | length) == 0)
    '
    ;;

  --set)
    key="${2:-}"; action="${3:-}"; src="${4:-}"
    if [ -z "$key" ] || [ -z "$action" ]; then
      echo "version-scan-targets: --set needs <key> and scan|skip" >&2
      exit 2
    fi
    case "$action" in
      scan)
        if [ -z "$src" ]; then
          echo "version-scan-targets: --set $key scan needs a source path" >&2
          exit 2
        fi
        if [ ! -d "$src" ]; then
          echo "version-scan-targets: $src is not a directory; $key not recorded" >&2
          exit 2
        fi
        src=$(cd "$src" && pwd)
        entry=$(jq -n --arg s "$src" '{action:"scan", src:$s}')
        ;;
      skip)
        entry='{"action":"skip"}'
        ;;
      *)
        echo "version-scan-targets: unknown action '$action'; use scan or skip" >&2
        exit 2
        ;;
    esac
    read_decl | jq --arg k "$key" --argjson e "$entry" '.targets[$k] = $e' | write_decl
    echo "version-scan-targets: $key -> $action${src:+ ($src)}"
    ;;

  --forget)
    key="${2:-}"
    if [ -z "$key" ]; then
      echo "version-scan-targets: --forget needs <key>" >&2
      exit 2
    fi
    read_decl | jq --arg k "$key" 'del(.targets[$k])' | write_decl
    echo "version-scan-targets: forgot $key"
    ;;

  *)
    echo "version-scan-targets: unknown mode '$1'" >&2
    exit 2
    ;;
esac
