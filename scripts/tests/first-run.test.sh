#!/usr/bin/env bash
# Hermetic tests for the state a first-time machine is in.
#
# The other two suites cover the version hook and the target declaration on
# their own. This one drives both against a single data dir in the order a real
# machine meets them — install, then an upgrade — because the built-in guide
# rests on a property neither suite can see alone: on a first-time machine the
# user's guide is unfilled AND the declaration is unsettled, and neither one
# being empty may make the other look finished.
#
# That is the regression this guards. An unfilled guide once meant an upgrade
# had nothing to carry out; making it mean that again, or making a fresh
# declaration report `settled`, would leave a first-time user with an upgrade
# that clears a banner and checks nothing.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/claude-code-version.sh"
TARGETS="$ROOT/scripts/version-scan-targets.sh"

pass=0; fail=0
check()    { if [ "$2" = "$3" ]; then echo "  ok: $1"; pass=$((pass+1)); else echo "  FAIL: $1 (got '$2', want '$3')"; fail=$((fail+1)); fi; }
contains() { case "$2" in *"$3"*) echo "  ok: $1"; pass=$((pass+1));; *) echo "  FAIL: $1 ('$2' lacks '$3')"; fail=$((fail+1));; esac; }

FIXTURES=$(mktemp -d /tmp/first-run.XXXXXX)
trap 'rm -rf "$FIXTURES"' EXIT

# A `claude` reporting a version the test controls, in the real command's shape.
BIN="$FIXTURES/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "--version" ] && echo "2.1.259 (Claude Code)"
STUB
chmod +x "$BIN/claude"
export PATH="$BIN:$PATH"

# Two plugins installed, which is what makes the declaration have questions.
export CLAUDE_PLUGINS_DIR="$FIXTURES/plugins"; mkdir -p "$CLAUDE_PLUGINS_DIR"
cat > "$CLAUDE_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{ "version": 2,
  "plugins": {
    "alpha@mp1": [{ "scope": "user", "installPath": "/x/alpha" }],
    "beta@mp2":  [{ "scope": "user", "installPath": "/x/beta" }] } }
JSON

export CLAUDE_PLUGIN_DATA="$FIXTURES/data"
MARKER="$CLAUDE_PLUGIN_DATA/acknowledged-version"
GUIDE="$CLAUDE_PLUGIN_DATA/on-claude-code-version-change.md"
DECL="$CLAUDE_PLUGIN_DATA/version-scan-targets.json"

drift()  { bash "$TARGETS" --drift 2>/dev/null; }
status() { bash "$HOOK" --status 2>/dev/null; }

echo "== install: the session that records the version nobody has to act on"
OUT=$(bash "$HOOK" 2>/dev/null); rc=$?
check "the hook exits 0" "$rc" '0'
check "and prints nothing — there is no upgrade yet" "$OUT" ''
check "it records the running version" "$(cat "$MARKER" 2>/dev/null)" '2.1.259'
if [ -f "$GUIDE" ]; then echo "  ok: it seeds an empty guide"; pass=$((pass+1)); else echo "  FAIL: it seeds an empty guide"; fail=$((fail+1)); fi
if [ -f "$DECL" ]; then echo "  FAIL: nothing writes a declaration unasked"; fail=$((fail+1)); else echo "  ok: nothing writes a declaration unasked"; pass=$((pass+1)); fi

echo "== the declaration reads a data dir the hook has already seeded"
check "every installed plugin is outstanding" "$(drift | jq -c '[.new[].key] | sort')" '["alpha@mp1","beta@mp2"]'
check "nothing is examined yet" "$(drift | jq -c '.targets')" '[]'
check "and it is not settled" "$(drift | jq -r '.settled')" 'false'

# The skill routes to onboarding on "nothing configured", which has to be
# distinguishable from "configured, and one plugin showed up since". Both leave
# `settled` false, so `settled` alone cannot be the signal — an empty targets
# AND skip pair is what says no decision was ever recorded.
echo "== nothing-configured is distinguishable from ordinary drift"
check "no decision of either kind is on record" "$(drift | jq -c '[.targets, .skip]')" '[[],[]]'
bash "$TARGETS" --set alpha@mp1 skip >/dev/null 2>&1
check "one answer makes it no longer a first run" "$(drift | jq -c '[(.targets|length) + (.skip|length) > 0, .settled]')" '[true,false]'
bash "$TARGETS" --forget alpha@mp1 >/dev/null 2>&1
check "and forgetting it returns to nothing configured" "$(drift | jq -c '[.targets, .skip]')" '[[],[]]'

echo "== the upgrade: Claude Code moves while the marker stays put"
echo '2.1.240' > "$MARKER"
OUT=$(bash "$HOOK" 2>/dev/null)
contains "the banner names the version left behind" "$OUT" '2.1.240'
contains "and the one now running" "$OUT" '2.1.259'
contains "it hands off to the skill rather than a raw command" "$OUT" 'claude-code-version'
check "the version stays pending" "$(status | jq -r '.pending')" 'true'
check "the marker is not advanced by announcing it" "$(cat "$MARKER")" '2.1.240'

echo "== first-time means both artifacts have work outstanding"
check "the user has written no guide" "$(status | jq -r '.guide.filled')" 'false'
check "reading it back yields nothing" "$(bash "$HOOK" --guide 2>/dev/null)" ''
check "and the declaration still has questions" "$(drift | jq -r '.settled')" 'false'
check "while the upgrade is still pending" "$(status | jq -r '.pending')" 'true'

echo "== neither artifact being empty finishes the other"
bash "$TARGETS" --set alpha@mp1 skip >/dev/null 2>&1
bash "$TARGETS" --set beta@mp2 summarize "$FIXTURES" >/dev/null 2>&1
check "answering every target settles the declaration" "$(drift | jq -r '.settled')" 'true'
check "but the guide is still unwritten" "$(status | jq -r '.guide.filled')" 'false'
check "and the upgrade is still pending" "$(status | jq -r '.pending')" 'true'

printf 'Re-train my artifacts.\n' >> "$GUIDE"
check "writing a guide fills it" "$(status | jq -r '.guide.filled')" 'true'
check "and leaves the declaration where it was" "$(drift | jq -r '.settled')" 'true'
bash "$TARGETS" --forget beta@mp2 >/dev/null 2>&1
check "dropping a decision re-opens the declaration" "$(drift | jq -r '.settled')" 'false'
check "without unwriting the guide" "$(status | jq -r '.guide.filled')" 'true'

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
