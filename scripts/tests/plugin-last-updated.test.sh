#!/usr/bin/env bash
# Hermetic tests for plugin-last-updated.sh.
#
# Builds a throwaway install manifest (CLAUDE_PLUGINS_DIR) and pins the clock
# (SHIPSHAPE_NOW), so every age is exact. The records follow the shape Claude
# Code writes to installed_plugins.json: one per scope, each with
# `installedAt` and `lastUpdated` in ISO 8601 with milliseconds.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin-last-updated.sh"

pass=0; fail=0
ok()   { echo "  ok: $1"; pass=$((pass + 1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail + 1)); }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1', want '$2')"; fi; }
has()  { case "$OUT" in *"$1"*) ok "$2" ;; *) bad "$2 (missing '$1')" ;; esac; }
hasnt(){ case "$OUT" in *"$1"*) bad "$2 (found '$1')" ;; *) ok "$2" ;; esac; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export CLAUDE_PLUGINS_DIR="$ROOT/plugins"
mkdir -p "$CLAUDE_PLUGINS_DIR"
MANIFEST="$CLAUDE_PLUGINS_DIR/installed_plugins.json"

# 2026-01-31T00:00:00Z
export SHIPSHAPE_NOW=1769817600

rec() { # scope lastUpdated
  printf '{"scope":"%s","installPath":"/x","version":"1.0.0","installedAt":"2025-01-01T00:00:00.000Z","lastUpdated":"%s"}' "$1" "$2"
}

cat > "$MANIFEST" <<JSON
{ "version": 2, "plugins": {
  "fresh@mp":    [$(rec user 2026-01-30T23:30:00.000Z)],
  "hours@mp":    [$(rec user 2026-01-30T19:00:00.000Z)],
  "days@mp":     [$(rec user 2026-01-26T00:00:00.000Z)],
  "weeks@mp":    [$(rec user 2026-01-03T00:00:00.000Z)],
  "months@mp":   [$(rec user 2025-10-01T00:00:00.000Z)],
  "years@mp":    [$(rec user 2024-01-01T00:00:00.000Z)],
  "future@mp":   [$(rec user 2026-02-05T00:00:00.000Z)],
  "nofrac@mp":   [$(rec user 2026-01-30T00:00:00Z)],
  "garbled@mp":  [$(rec user yesterday)],
  "shared@mp":   [$(rec user 2025-12-01T00:00:00.000Z), $(rec project 2026-01-30T23:00:00.000Z)],
  "teamonly@mp": [$(rec project 2026-01-20T00:00:00.000Z), $(rec local 2026-01-29T00:00:00.000Z)],
  "empty@mp":    []
} }
JSON

echo "== ages"
OUT=$(bash "$SCRIPT"); rc=$?
eq "$rc" 0 "exits 0 when it can read the manifest"
has "fresh@mp|2026-01-30T23:30:00.000Z|just now" "under an hour reads just now"
has "hours@mp|2026-01-30T19:00:00.000Z|5h ago"   "under a day reads in hours"
has "days@mp|2026-01-26T00:00:00.000Z|5d ago"    "under two weeks reads in days"
has "weeks@mp|2026-01-03T00:00:00.000Z|4w ago"   "under two months reads in weeks"
has "months@mp|2025-10-01T00:00:00.000Z|4mo ago" "under a year reads in months"
has "years@mp|2024-01-01T00:00:00.000Z|2y ago"   "a year or more reads in years"
has "future@mp|2026-02-05T00:00:00.000Z|just now" "a time ahead of the clock reads just now"
has "nofrac@mp|2026-01-30T00:00:00Z|1d ago"      "a time without milliseconds parses"
has "garbled@mp|-|unknown"                       "an unparseable time reads unknown"
hasnt "empty@mp"                                 "a key with no records prints nothing"

echo "== which record speaks for a key"
has   "shared@mp|2025-12-01T00:00:00.000Z|2mo ago" "the user-scope record wins over a newer project install"
has   "teamonly@mp|2026-01-29T00:00:00.000Z|2d ago" "without a user record, the most recent one wins"
eq "$(printf '%s\n' "$OUT" | grep -c '^shared@mp|')" 1 "one row per key"

echo "== an empty manifest"
echo '{ "version": 2, "plugins": {} }' > "$MANIFEST"
OUT=$(bash "$SCRIPT"); rc=$?
eq "$rc" 0 "exits 0 with no plugins"
eq "$OUT" "" "prints nothing"

echo "== unreadable inputs"
echo 'not json' > "$MANIFEST"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "an unparseable manifest exits 1"
has "does not parse" "  and says so"

echo '{ "version": 2 }' > "$MANIFEST"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "a manifest with no plugins object exits 1"

rm "$MANIFEST"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "a missing manifest exits 1"
has "no install manifest" "  and says so"

echo '{ "version": 2, "plugins": {} }' > "$MANIFEST"
OUT=$(SHIPSHAPE_NOW=soon bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "a clock override that isn't epoch seconds exits 1"

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
