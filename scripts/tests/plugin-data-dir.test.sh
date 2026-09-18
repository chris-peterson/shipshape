#!/usr/bin/env bash
# Hermetic tests for plugin-data-dir.sh.
#
# Builds a throwaway install manifest and a pair of lanes, then drives the
# resolution through the cases that decide which one a session writes to: an
# installed plugin mounted with --plugin-dir, a plugin only ever mounted that
# way, one installed from two marketplaces, and a manifest that is missing or
# does not parse. Every case that cannot name one lane leaves the session in its
# own, because writing into a lane resolved from a guess is what loses a prior
# run's decisions.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin-data-dir.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
eq() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want '$2', got '$1')"; fi; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export CLAUDE_PLUGINS_DIR="$ROOT/plugins"
mkdir -p "$CLAUDE_PLUGINS_DIR"
MANIFEST="$CLAUDE_PLUGINS_DIR/installed_plugins.json"
LANES="$ROOT/data"; mkdir -p "$LANES"

manifest() { printf '%s\n' "$1" > "$MANIFEST"; }
resolve() { bash "$SCRIPT" "$1" 2>/dev/null; }
stderr() { bash "$SCRIPT" "$1" 2>&1 >/dev/null; }

echo "== an installed plugin mounted with --plugin-dir"
manifest '{ "version": 2, "plugins": { "shipshape@mp": [{ "scope": "user" }] } }'
eq "$(resolve "$LANES/shipshape-inline")" "$LANES/shipshape-mp" \
   "an inline lane resolves to the installed one"
eq "$(resolve "$LANES/shipshape-mp")" "$LANES/shipshape-mp" \
   "the installed lane resolves to itself"

echo "== a marketplace name carrying the separator"
manifest '{ "version": 2, "plugins": { "shipshape@getty-claude-marketplace": [{ "scope": "user" }] } }'
eq "$(resolve "$LANES/shipshape-inline")" "$LANES/shipshape-getty-claude-marketplace" \
   "a hyphenated marketplace survives the join"

echo "== a name that is a prefix of another plugin's"
manifest '{ "version": 2, "plugins": { "mate-extra@mp": [{ "scope": "user" }] } }'
eq "$(resolve "$LANES/mate-inline")" "$LANES/mate-inline" \
   "a longer plugin name does not claim the lane"

echo "== nothing to resolve to"
manifest '{ "version": 2, "plugins": {} }'
eq "$(resolve "$LANES/shipshape-inline")" "$LANES/shipshape-inline" \
   "an uninstalled plugin keeps its own lane"

echo "== more than one candidate"
manifest '{ "version": 2, "plugins": { "shipshape@mp1": [{}], "shipshape@mp2": [{}] } }'
eq "$(resolve "$LANES/shipshape-inline")" "$LANES/shipshape-inline" \
   "two marketplaces leave the session in its own lane"
case "$(stderr "$LANES/shipshape-inline")" in
  *"installed from 2 marketplaces"*) ok "and the ambiguity is surfaced" ;;
  *) bad "and the ambiguity is surfaced" ;;
esac

echo "== an unreadable manifest is not an empty one"
manifest 'not json at all'
eq "$(resolve "$LANES/shipshape-inline")" "$LANES/shipshape-inline" \
   "a manifest that does not parse keeps the inline lane"
case "$(stderr "$LANES/shipshape-inline")" in
  *"is not readable"*) ok "and the unreadable manifest is surfaced" ;;
  *) bad "and the unreadable manifest is surfaced" ;;
esac
unlink "$MANIFEST"
eq "$(resolve "$LANES/shipshape-inline")" "$LANES/shipshape-inline" \
   "a missing manifest keeps the inline lane"

echo "== missing inputs"
OUT=$(CLAUDE_PLUGIN_DATA= bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" '1' "no directory and no CLAUDE_PLUGIN_DATA exits non-zero"
case "$OUT" in *"CLAUDE_PLUGIN_DATA is unset"*) ok "and names the reason" ;; *) bad "and names the reason" ;; esac
eq "$(CLAUDE_PLUGIN_DATA="$LANES/shipshape-inline" bash "$SCRIPT" 2>/dev/null)" "$LANES/shipshape-inline" \
   "the directory falls back to CLAUDE_PLUGIN_DATA"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
