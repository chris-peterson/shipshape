#!/usr/bin/env bash
# Advisory lock for a plugin-maintenance reconcile.
#
# `claude plugin` mutates shared state — the install manifest, the per-marketplace
# git clones, the per-version caches — with no locking of its own. Two reconciles,
# or a reconcile racing another session's plugin operations, can interleave and
# leave that state in a mix neither intended. This is a cooperative lock: the
# skill acquires it before touching plugins and releases it at the end. It does
# not stop a caller that ignores it.
#
# Identity is the Claude Code session ($CLAUDE_CODE_SESSION_ID), so the lock is
# re-entrant within a session (each skill step runs in a fresh shell) and
# mutually exclusive across sessions. A lock older than the stale threshold is
# treated as abandoned — a crashed run that never released — and stolen.
#
# Outside a session there is no session id, and the `pid-$$` fallback is the PID
# of *this* process — which differs between the acquire call and the release call
# when a caller runs each as its own `bash`. Such a caller sets
# $PLUGIN_MAINT_OWNER once and exports it, so both calls present one identity and
# release recognizes the lock as its own.
#
# Usage:  plugin-maintenance-lock.sh acquire
#         plugin-maintenance-lock.sh release
# Exit:   0 = acquired, or released (or nothing to release)
#         3 = acquire failed: another live session holds the lock (bail)
#         2 = usage error
#
# Env:    PLUGIN_MAINT_LOCK   override the lockfile path (tests)
#         PLUGIN_MAINT_STALE  override the stale threshold in seconds (default 1800)
#         PLUGIN_MAINT_OWNER  lock identity for a caller with no session id

set -euo pipefail

cmd="${1:-}"
lock="${PLUGIN_MAINT_LOCK:-$HOME/.claude/plugins/.plugin-maintenance.lock}"
stale="${PLUGIN_MAINT_STALE:-1800}"
me="${PLUGIN_MAINT_OWNER:-${CLAUDE_CODE_SESSION_ID:-pid-$$}}"

# Read a string field from the lockfile JSON (jq if present, else a sed fallback).
field_of() {  # $1 = file, $2 = key
  [ -f "$1" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$2" '.[$k] // empty' "$1" 2>/dev/null || true
  else
    sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1"
  fi
}

# mtime of a file in epoch seconds (GNU stat -c, then BSD stat -f).
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

case "$cmd" in
  acquire)
    mkdir -p "$(dirname "$lock")"
    if [ -f "$lock" ]; then
      owner=$(field_of "$lock" session)
      if [ "$owner" = "$me" ]; then
        touch "$lock"; exit 0            # re-entrant: the lock is already ours
      fi
      age=$(( $(date +%s) - $(mtime_of "$lock") ))
      if [ "$age" -lt "$stale" ]; then
        started=$(field_of "$lock" started)
        echo "plugin-maintenance-lock: held by session ${owner:-unknown} since ${started:-?} (${age}s ago); another maintenance run is active — not acquiring" >&2
        exit 3
      fi
      echo "plugin-maintenance-lock: clearing stale lock from session ${owner:-unknown} (${age}s old)" >&2
    fi
    printf '{"session":"%s","started":"%s"}\n' "$me" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$lock"
    exit 0
    ;;
  release)
    [ -f "$lock" ] || exit 0
    [ "$(field_of "$lock" session)" = "$me" ] && rm -f "$lock" || true   # only release our own
    exit 0
    ;;
  *)
    echo "usage: plugin-maintenance-lock.sh acquire|release" >&2
    exit 2
    ;;
esac
