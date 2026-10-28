#!/usr/bin/env bash
# Hermetic tests for plugin-orphan-deps.sh.
#
# Stubs `claude plugin prune --dry-run` with a fixture (CLAUDE_CLI), and builds
# a throwaway registry and install manifest (CLAUDE_PLUGINS_DIR). The fixture
# text is what Claude Code 2.1.312 printed for a plugin installed as another's
# dependency, before and after that plugin was uninstalled.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin-orphan-deps.sh"

pass=0; fail=0
ok()   { echo "  ok: $1"; pass=$((pass + 1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail + 1)); }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1', want '$2')"; fi; }
has()  { case "$OUT" in *"$1"*) ok "$2" ;; *) bad "$2 (missing '$1')" ;; esac; }
hasnt(){ case "$OUT" in *"$1"*) bad "$2 (found '$1')" ;; *) ok "$2" ;; esac; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export CLAUDE_PLUGINS_DIR="$ROOT/plugins"
export CLAUDE_CLI="$ROOT/claude"
mkdir -p "$CLAUDE_PLUGINS_DIR"

cat > "$CLAUDE_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{ "mp1": {}, "mp2": {} }
JSON

cat > "$CLAUDE_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{
  "version": 2,
  "plugins": {
    "alpha@mp1":   [ { "scope": "user", "version": "1.0.0" } ],
    "dep-b@mp1":   [ { "scope": "user", "version": "1.0.0", "auto": true } ],
    "dep-c@mp2":   [ { "scope": "user", "version": "2.1.0", "auto": true } ],
    "dep-s@synced":[ { "scope": "user", "version": "0.3.0", "auto": true } ]
  }
}
JSON

cat > "$CLAUDE_CLI" <<SH
#!/usr/bin/env bash
[ "\$*" = "plugin prune --dry-run" ] || { echo "unexpected args: \$*" >&2; exit 64; }
echo "Pinned plugins: (a wrapper's banner, on stderr)" >&2
cat "$ROOT/dry.txt"
SH
chmod +x "$CLAUDE_CLI"

echo "== nothing auto-installed"
echo 'Nothing to prune (no auto-installed plugins at user scope).' > "$ROOT/dry.txt"
OUT=$(bash "$SCRIPT"); rc=$?
eq "$rc" 0 "exits 0"
eq "$OUT" "" "prints nothing"

echo "== auto-installed, all still needed"
echo 'Nothing to prune (1 auto-installed plugin at user scope, all still needed).' > "$ROOT/dry.txt"
OUT=$(bash "$SCRIPT"); rc=$?
eq "$rc" 0 "exits 0"
eq "$OUT" "" "prints nothing"

echo "== one orphan"
cat > "$ROOT/dry.txt" <<'TXT'
1 auto-installed plugin no longer needed at user scope:
  dep-b@mp1 (1.0.0)
(dry run — nothing removed)
TXT
OUT=$(bash "$SCRIPT"); rc=$?
eq "$rc" 0 "exits 0"
eq "$OUT" "dep-b@mp1|1.0.0" "lists the key and version"

echo "== several orphans, one from an unregistered origin"
cat > "$ROOT/dry.txt" <<'TXT'
3 auto-installed plugins no longer needed at user scope:
  dep-b@mp1 (1.0.0)
  dep-c@mp2 (2.1.0)
  dep-s@synced (0.3.0)
(dry run — nothing removed)
TXT
OUT=$(bash "$SCRIPT"); rc=$?
eq "$rc" 0 "exits 0"
has   "dep-b@mp1|1.0.0" "lists the first"
has   "dep-c@mp2|2.1.0" "lists the second"
hasnt "dep-s@synced"    "leaves out an origin that isn't a registered marketplace"

echo "== CRLF output"
printf '1 auto-installed plugin no longer needed at user scope:\r\n  dep-b@mp1 (1.0.0)\r\n(dry run — nothing removed)\r\n' > "$ROOT/dry.txt"
OUT=$(bash "$SCRIPT"); rc=$?
eq "$rc" 0 "exits 0"
eq "$OUT" "dep-b@mp1|1.0.0" "strips the carriage returns"

echo "== doubt lists nothing"
cat > "$ROOT/dry.txt" <<'TXT'
1 auto-installed plugin no longer needed at user scope:
  alpha@mp1 (1.0.0)
(dry run — nothing removed)
TXT
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "a key the manifest doesn't mark auto exits 1"
has "alpha@mp1 is not marked auto-installed" "  and names it"

cat > "$ROOT/dry.txt" <<'TXT'
1 auto-installed plugin no longer needed at user scope:
  dep-b@mp1 (1.0.0)
  dep-c@mp2 (2.1.0)
(dry run — nothing removed)
TXT
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "a count that disagrees with the list exits 1"
hasnt "dep-b@mp1|" "  and lists nothing"

cat > "$ROOT/dry.txt" <<'TXT'
Would remove these dependencies:
  dep-b@mp1 (1.0.0)
TXT
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "wording it doesn't recognize exits 1"
has "unrecognized" "  and says so"

: > "$ROOT/dry.txt"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "empty output exits 1"

mv "$CLAUDE_CLI" "$CLAUDE_CLI.off"
printf '#!/usr/bin/env bash\necho "error: unknown command prune" >&2\nexit 1\n' > "$CLAUDE_CLI"; chmod +x "$CLAUDE_CLI"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "a Claude Code without prune exits 1"
has "prune --dry-run\` failed" "  and names the command"
mv "$CLAUDE_CLI.off" "$CLAUDE_CLI"

echo "== unreadable inputs"
echo 'Nothing to prune (no auto-installed plugins at user scope).' > "$ROOT/dry.txt"
mv "$CLAUDE_PLUGINS_DIR/installed_plugins.json" "$ROOT/manifest.off"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "a missing install manifest exits 1"
echo 'not json' > "$CLAUDE_PLUGINS_DIR/installed_plugins.json"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "an unparseable install manifest exits 1"
mv "$ROOT/manifest.off" "$CLAUDE_PLUGINS_DIR/installed_plugins.json"

mv "$CLAUDE_PLUGINS_DIR/known_marketplaces.json" "$ROOT/registry.off"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "a missing marketplace registry exits 1"
mv "$ROOT/registry.off" "$CLAUDE_PLUGINS_DIR/known_marketplaces.json"

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
