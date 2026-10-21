#!/usr/bin/env bash
# Marketplace auto-update gets enabled on a machine with no jq. CI runs this on
# a runner for each platform fetch-jq.sh pins.
#
# enforce-autoupdate.test.sh hands the hook a jq it already has. This runs the
# hook the way a first SessionStart does: no jq on PATH and an empty data dir,
# so it has to download the real release binary and use it. The hook enabling
# auto-update is the evidence the pin matched, the binary ran, and platform.sh
# found it. It needs the network, so it isn't named *.test.sh and `just test`
# leaves it out.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASH_BIN="$(type -P bash)"

pass=0; fail=0
check() {  # $1 label  $2 actual  $3 expected
  if [ "$2" = "$3" ]; then echo "  ok: $1"; pass=$((pass + 1))
  else echo "  FAIL: $1 (got '$2', want '$3')"; fail=$((fail + 1)); fi
}

FIXTURES=$(mktemp -d /tmp/autoupdate-without-jq.XXXXXX)
trap 'rm -rf "$FIXTURES"' EXIT
TOOLS="$FIXTURES/tools" DATA="$FIXTURES/data" HOME_DIR="$FIXTURES/home"
mkdir -p "$TOOLS" "$DATA" "$HOME_DIR/.claude/plugins"
# Everything the hook and the download need except jq.
for t in cat mktemp mv sed uname curl sha256sum shasum mkdir chmod rm; do
  p=$(type -P "$t") || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$p" > "$TOOLS/$t"
  chmod +x "$TOOLS/$t"
done
printf '{"mp1":{"source":"s1"}}\n' > "$HOME_DIR/.claude/plugins/known_marketplaces.json"

hook() { env HOME="$HOME_DIR" PATH="$TOOLS" CLAUDE_PLUGIN_DATA="$DATA" "$BASH_BIN" "$ROOT/hooks/enforce-autoupdate.sh" 2>&1; }

echo "== first session start on $(uname -s) $(uname -m), with no jq"
out=$(hook); rc=$?
printf '%s\n' "$out" | sed 's/^/  | /'
check "the hook exits 0" "$rc" "0"
case "$out" in
  *"auto-update enabled"*"mp1"*) check "the hook enables the marketplace" ok ok ;;
  *) check "the hook enables the marketplace" "$out" "a report naming mp1" ;;
esac
check "settings.json records it" \
      "$(grep -c '"autoUpdate": true' "$HOME_DIR/.claude/settings.json" 2>/dev/null)" "1"

echo "== the next session start"
out=$(hook); rc=$?
check "the hook exits 0" "$rc" "0"
check "and has nothing left to do" "$out" ""

echo
echo "autoupdate-without-jq: pass=$pass fail=$fail"
[ "$fail" = 0 ]
