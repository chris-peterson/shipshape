#!/usr/bin/env bash
# Report whether a plugin cache version dir is in use by a live session.
#
# Each version dir under ~/.claude/plugins/cache/<mp>/<plugin>/<version>/ carries
# an .in_use/ directory of lease files — {"pid":<n>,"procStart":"<ts>"} — dropped
# by every running session that loaded that version at startup. The dir is IN USE
# if any lease names a running process whose start time still matches the lease's
# procStart.
#
# Matching procStart, not the PID alone, is the point: the OS recycles PIDs, so a
# dead session's PID handed to an unrelated process makes `ps -p <pid>` succeed
# for a process that never held the lease. Comparing start times rejects that
# reuse and lets stale caches actually be pruned.
#
# Usage:  plugin-cache-in-use.sh <version-dir>
# Exit:   0 = in use  (a live lease holds it — do NOT prune)
#         1 = not in use  (safe to prune)
#
# Conservative by design: whenever liveness can't be disproven, the answer is IN
# USE — never prune on doubt. That covers a missing procStart, a procStart no
# `date` dialect on this box can parse, and jq being absent entirely (which is
# surfaced on stderr, not swallowed).

# covers: PRUNE-07
set -euo pipefail

dir="${1:?usage: plugin-cache-in-use.sh <version-dir>}"

# Leases are JSON; without jq we can't read them at all. Fail conservative —
# report in use so nothing is pruned — and say why (never silently prune).
if ! command -v jq >/dev/null 2>&1; then
  echo "plugin-cache-in-use: jq not on PATH; treating '$dir' as in use" >&2
  exit 0
fi

leases="$dir/.in_use"
[ -d "$leases" ] || exit 1   # no lease dir at all -> not in use

# Epoch of a "Www Mmm DD HH:MM:SS YYYY" timestamp. $2 = timezone (default local).
# Tries GNU `date -d` first, then BSD `date -j -f`; empty output + nonzero if
# neither parses it.
_epoch() {
  local ts="$1" tz="${2:-}"
  if [ -n "$tz" ]; then
    TZ="$tz" date -d "$ts" +%s 2>/dev/null && return 0
    TZ="$tz" date -j -f "%a %b %e %T %Y" "$ts" +%s 2>/dev/null && return 0
  else
    date -d "$ts" +%s 2>/dev/null && return 0
    date -j -f "%a %b %e %T %Y" "$ts" +%s 2>/dev/null && return 0
  fi
  return 1
}

shopt -s nullglob
for lease in "$leases"/*; do
  [ -f "$lease" ] || continue
  pid=$(jq -r '.pid // empty' "$lease" 2>/dev/null || true)
  start=$(jq -r '.procStart // empty' "$lease" 2>/dev/null || true)
  [ -n "$pid" ] || continue

  # PID must name a running process, else this lease is dead.
  lstart=$(ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//' || true)
  [ -n "$lstart" ] || continue

  # No procStart recorded -> can't disprove liveness -> conservative: in use.
  [ -n "$start" ] || exit 0

  e_proc=$(_epoch "$lstart" || true)
  [ -n "$e_proc" ] || exit 0   # can't parse the process's own start -> conservative

  # procStart's timezone is undocumented (observed as UTC while `ps` prints
  # local), so try both zones. If NEITHER parses, procStart is present but
  # unreadable -> can't disprove liveness -> conservative: in use.
  e_loc=$(_epoch "$start" || true)
  e_utc=$(_epoch "$start" UTC || true)
  if [ -z "$e_loc" ] && [ -z "$e_utc" ]; then exit 0; fi

  # A ≤2s gap in either zone absorbs rounding and means the live process is the
  # one that wrote the lease.
  for e in "$e_loc" "$e_utc"; do
    [ -n "$e" ] || continue
    d=$(( e_proc - e ))
    [ "$d" -lt 0 ] && d=$(( 0 - d )) || true
    if [ "$d" -le 2 ]; then exit 0; fi
  done
  # procStart parsed cleanly but matched no zone -> PID recycled -> lease is dead.
done

exit 1
