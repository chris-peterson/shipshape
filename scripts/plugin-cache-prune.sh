#!/usr/bin/env bash
# Delete the plugin cache and data directories it is handed, and nothing else.
#
# Takes paths in plugin-cache-scan.sh's form — `cache/<mp>/<plugin>/<version>`
# or `data/<slug>`, relative to ~/.claude/plugins — as arguments, or on stdin
# one per line. Prints a line per path and a `pruned=… skipped=… freed=…` total.
#
# Three refusals are structural, so a caller that hands over the wrong path
# cannot talk the script into the delete:
#
#   * Shape. A cache path must have four segments (a version dir) or three (a
#     plugin dir whose versions are all gone, cleared with rmdir, never rm -rf);
#     a data path must have two. That is what keeps `cache/<mp>/`, `cache/`, and
#     `data/` themselves out of reach: they are the wrong depth, so there is no
#     argument that removes one.
#   * Lease. Every cache dir is re-checked immediately before its own delete,
#     not once at scan time. Scanning and pruning are separate steps and a
#     session can start between them, loading a version the scan called free.
#   * Accumulated user state. A non-empty data dir needs --data-confirmed. The
#     script will not decide that state is disposable; the skill asks the user.
#
# A plugin dir left empty by this run is cleared afterwards without being asked
# for. Either way the removal goes through `rmdir`, which refuses a directory
# holding anything at all — a stray .DS_Store leaves the parent in place rather
# than putting an unrelated file in the blast radius.
#
# Usage:  plugin-cache-prune.sh [--data-confirmed] <path>...
#         plugin-cache-scan.sh | ... | plugin-cache-prune.sh
# Exit:   0 = every path handled (deleted, or skipped for a stated reason)
#         2 = at least one path was refused as malformed (nothing deleted there)
#
# Env:    CLAUDE_PLUGINS_DIR  override ~/.claude/plugins (tests)

# covers: PRUNE-06, PRUNE-09, PRUNE-10, PRUNE-11, PRUNE-13, PRUNE-14, PRUNE-15
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugins="${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}"

data_confirmed=0
paths=()
for arg in "$@"; do
  case "$arg" in
    --data-confirmed) data_confirmed=1 ;;
    -*) echo "usage: plugin-cache-prune.sh [--data-confirmed] <path>..." >&2; exit 2 ;;
    *) paths+=("$arg") ;;
  esac
done
if [ ${#paths[@]} -eq 0 ]; then
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac   # skip scan's #totals line
    paths+=("$line")
  done
fi
if [ ${#paths[@]} -eq 0 ]; then
  echo "usage: plugin-cache-prune.sh [--data-confirmed] <path>..." >&2
  exit 2
fi

size_kb() { du -sk "$1" 2>/dev/null | awk '{print $1}' || echo 0; }

human() {  # $1 = KB
  awk -v k="${1:-0}" 'BEGIN {
    if (k < 1024)         printf "%dK\n", k
    else if (k < 1048576) printf "%.1fM\n", k/1024
    else                  printf "%.1fG\n", k/1048576
  }'
}

refuse() { echo "plugin-cache-prune: refusing '$1' — $2" >&2; refused=$((refused + 1)); }

pruned=0; skipped=0; refused=0; freed_kb=0
touched_parents=()

for rel in "${paths[@]}"; do
  case "$rel" in
    */../*|../*|*/..) refuse "$rel" "path traversal"; continue ;;
  esac

  # Segment count is the guard on the parent directories: nothing at the wrong
  # depth is a deletable entry, whatever else it looks like.
  IFS='/' read -r -a seg <<< "$rel"
  case "${seg[0]:-}" in
    cache)
      case "${#seg[@]}" in
        4) kind=cache ;;
        3) kind=cache-plugin ;;
        *) refuse "$rel" "not a cache dir (want cache/<mp>/<plugin>[/<version>])"; continue ;;
      esac ;;
    data)
      [ "${#seg[@]}" -eq 2 ] || { refuse "$rel" "not a data dir (want data/<slug>)"; continue; }
      kind=data ;;
    *) refuse "$rel" "outside cache/ and data/"; continue ;;
  esac

  dir="$plugins/$rel"
  if [ ! -d "$dir" ]; then
    echo "absent  $rel"
    continue
  fi

  if [ "$kind" = cache-plugin ]; then
    if rmdir "$dir" 2>/dev/null; then
      pruned=$((pruned + 1))
      echo "pruned  $rel (empty plugin dir)"
    else
      skipped=$((skipped + 1))
      echo "skipped $rel (not empty)"
    fi
    continue
  fi

  if [ "$kind" = cache ]; then
    if bash "$here/plugin-cache-in-use.sh" "$dir" >/dev/null 2>&1; then
      echo "skipped $rel (in use)"
      skipped=$((skipped + 1))
      continue
    fi
    touched_parents+=("$(dirname "$dir")")
  else
    case "$rel" in
      *-inline) echo "skipped $rel (inline install artifact)"; skipped=$((skipped + 1)); continue ;;
    esac
    if [ -n "$(ls -A "$dir" 2>/dev/null)" ] && [ "$data_confirmed" -eq 0 ]; then
      echo "skipped $rel (non-empty data dir; needs --data-confirmed)"
      skipped=$((skipped + 1))
      continue
    fi
  fi

  kb=$(size_kb "$dir")
  rm -rf "$dir"
  freed_kb=$((freed_kb + kb))
  pruned=$((pruned + 1))
  echo "pruned  $rel ($(human "$kb"))"
done

# A plugin whose every version dir is gone leaves an empty `cache/<mp>/<plugin>/`
# behind. rmdir clears it and refuses everything else, including the marketplace
# dir above it, which always still holds its other plugins.
for parent in ${touched_parents+"${touched_parents[@]}"}; do
  if rmdir "$parent" 2>/dev/null; then
    echo "pruned  cache/${parent#"$plugins/cache/"} (empty plugin dir)"
  fi
done

printf 'pruned=%d skipped=%d freed=%s\n' "$pruned" "$skipped" "$(human "$freed_kb")"
[ "$refused" -eq 0 ] || exit 2
