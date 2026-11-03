#!/usr/bin/env bash
# What a /maintain-harness run changed in the repos it wrote to.
#
# A run's closing report lists every path it changed, so the user can tell when
# they're done. `git status` alone can't say which of a repo's changes are the
# run's: the user's other sessions work in the same checkouts. So the run
# snapshots each repo before its first write there, and the report lists only
# what differs from that snapshot.
#
# A snapshot records HEAD and, for every dirty path, its porcelain status and
# content hash. A path counts as changed when it is dirty now with a different
# status or content, when a commit made during the run touched it, or when it
# was dirty at the snapshot and is clean now with HEAD unmoved (restored).
#
# Usage:  run-changes.sh start <dir>...   snapshot each repo not yet snapshotted this run
#         run-changes.sh report           print what changed since each snapshot, then forget the run
#
# Report: <repo>|<path>|<state>|<before>   one line per changed path, sorted
#           state:  modified | added | deleted | renamed | untracked | committed <sha> | restored
#           before: clean, or dirty when the path already had uncommitted changes at the snapshot
#         <dir>|-|not-a-repo|-              a dir passed to start that is not a git work tree
#         #totals repos=<n> changed=<n> not_a_repo=<n>
#
# Exit:   0 = ok
#         1 = can't track: git missing, CLAUDE_PLUGIN_DATA or CLAUDE_CODE_SESSION_ID
#             unset, or report with no start in this session
#         2 = usage error

# covers: REPORT-12, REPORT-13
set -euo pipefail
. "${BASH_SOURCE[0]%/*}/platform.sh"

die() { printf 'run-changes: %s\n' "$1" >&2; exit "${2:-1}"; }

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
  start|report) ;;
  *) die "usage: run-changes.sh start <dir>... | report" 2 ;;
esac

type -P git >/dev/null || die "git is not on PATH; the run's changes can't be listed"
[ -n "${CLAUDE_PLUGIN_DATA:-}" ] || die "CLAUDE_PLUGIN_DATA is unset; the run's changes can't be listed"
[ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || die "CLAUDE_CODE_SESSION_ID is unset; start and report can't find the same run"

dir="$CLAUDE_PLUGIN_DATA/run-changes"
snap="$dir/$CLAUDE_CODE_SESSION_ID.tsv"

# Lines for one repo:  repo <top> <head>  then  path <top> <path> <xy> <hash>
snapshot_of() {
  local top="$1" head entry xy p h _orig
  head=$(git -C "$top" rev-parse -q --verify HEAD 2>/dev/null || echo -)
  printf 'repo\t%s\t%s\n' "$top" "$head"
  while IFS= read -r -d '' entry; do
    xy=${entry:0:2}; p=${entry:3}
    case "$xy" in R*|C*) IFS= read -r -d '' _orig || true ;; esac
    if [ -f "$top/$p" ]; then
      h=$(git -C "$top" hash-object -- "$p" 2>/dev/null || echo '?')
    else
      h=-
    fi
    printf 'path\t%s\t%s\t%s\t%s\n' "$top" "$p" "$xy" "$h"
  done < <(git -C "$top" status --porcelain=v1 -z --untracked-files=all)
}

if [ "$cmd" = start ]; then
  [ $# -gt 0 ] || die "usage: run-changes.sh start <dir>..." 2
  mkdir -p "$dir"
  # A run that crashed before its report leaves its snapshot behind.
  find "$dir" -name '*.tsv' -mtime +7 -exec rm -f {} + 2>/dev/null || true
  touch "$snap"
  for d in "$@"; do
    if ! top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null); then
      printf 'run-changes: %s is not a git work tree; its changes cannot be listed\n' "$d" >&2
      awk -F'\t' -v d="$d" '$1=="skip" && $2==d {f=1} END {exit !f}' "$snap" \
        || printf 'skip\t%s\n' "$d" >> "$snap"
      continue
    fi
    awk -F'\t' -v t="$top" '$1=="repo" && $2==t {f=1} END {exit !f}' "$snap" && continue
    snapshot_of "$top" >> "$snap"
  done
  exit 0
fi

[ -f "$snap" ] || die "no run started in this session; nothing to report"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
: > "$work/out"
repos=0; skipped=0

while IFS=$'\t' read -r kind top oldhead; do
  case "$kind" in
    skip) printf '%s|-|not-a-repo|-\n' "$top" >> "$work/out"; skipped=$((skipped + 1)); continue ;;
    repo) ;;
    *) continue ;;
  esac
  repos=$((repos + 1))
  awk -F'\t' -v t="$top" '$1=="path" && $2==t {print $3"\t"$4"\t"$5}' "$snap" > "$work/old"
  snapshot_of "$top" > "$work/now"
  newhead=$(awk -F'\t' '$1=="repo" {print $3; exit}' "$work/now")
  awk -F'\t' '$1=="path" {print $3"\t"$4"\t"$5}' "$work/now" > "$work/cur"
  : > "$work/com"
  if [ "$oldhead" != "$newhead" ] && [ "$newhead" != - ]; then
    if [ "$oldhead" = - ]; then
      git -C "$top" ls-tree -r --name-only "$newhead" > "$work/com"
    else
      git -C "$top" diff --name-only "$oldhead" "$newhead" > "$work/com"
    fi
  fi
  awk -F'\t' -v repo="$top" -v sha="${newhead:0:7}" '
    function state(x) {
      if (x == "??") return "untracked"
      if (x ~ /D/) return "deleted"
      if (x ~ /R/) return "renamed"
      if (x ~ /A/) return "added"
      return "modified"
    }
    FILENAME == ARGV[1] { old[$1] = $2 "\t" $3; next }
    FILENAME == ARGV[2] { com[$1] = 1; next }
    { cur[$1] = $2 "\t" $3; xy[$1] = $2 }
    END {
      for (p in cur) if (!(p in old) || old[p] != cur[p]) out[p] = state(xy[p])
      for (p in com) if (!(p in out) && !(p in cur)) out[p] = "committed " sha
      for (p in old) if (!(p in cur) && !(p in com)) out[p] = "restored"
      for (p in out) print repo "|" p "|" out[p] "|" ((p in old) ? "dirty" : "clean")
    }
  ' "$work/old" "$work/com" "$work/cur" >> "$work/out"
done < "$snap"

sort "$work/out"
changed=$(awk -F'|' '$3 != "not-a-repo"' "$work/out" | wc -l | tr -d ' ')
printf '#totals repos=%s changed=%s not_a_repo=%s\n' "$repos" "$changed" "$skipped"
rm -f "$snap"
