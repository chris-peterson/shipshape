#!/usr/bin/env bash
# Hermetic tests for plugin-unmanaged.sh.
#
# Stubs `claude plugin list --json` with a fixture (CLAUDE_CLI), and builds a
# throwaway registry (CLAUDE_PLUGINS_DIR) and settings file
# (CLAUDE_SETTINGS_FILE). The `@synced` rows follow the form Claude Code's
# changelog gives for claude.ai-synced plugins (2.1.239, 2.1.243); no real one
# was available to copy.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin-unmanaged.sh"

pass=0; fail=0
ok()   { echo "  ok: $1"; pass=$((pass + 1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail + 1)); }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1', want '$2')"; fi; }
has()  { case "$OUT" in *"$1"*) ok "$2" ;; *) bad "$2 (missing '$1')" ;; esac; }
hasnt(){ case "$OUT" in *"$1"*) bad "$2 (found '$1')" ;; *) ok "$2" ;; esac; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export CLAUDE_PLUGINS_DIR="$ROOT/plugins"
export CLAUDE_SETTINGS_FILE="$ROOT/settings.json"
export CLAUDE_CLI="$ROOT/claude"
mkdir -p "$CLAUDE_PLUGINS_DIR"

cat > "$CLAUDE_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{ "mp1": {}, "mp2": {} }
JSON

cat > "$ROOT/list.json" <<'JSON'
[
  { "id": "alpha@mp1",       "scope": "user",    "enabled": true },
  { "id": "beta@mp2",        "scope": "project", "enabled": false },
  { "id": "helper@synced",   "scope": "user",    "enabled": true },
  { "id": "relic@removed-mp","scope": "user",    "enabled": false }
]
JSON

cat > "$CLAUDE_SETTINGS_FILE" <<'JSON'
{ "enabledPlugins": { "alpha@mp1": true, "helper@synced": true, "gamma@mp2": true } }
JSON

cat > "$CLAUDE_CLI" <<SH
#!/usr/bin/env bash
[ "\$*" = "plugin list --json" ] || { echo "unexpected args: \$*" >&2; exit 64; }
cat "$ROOT/list.json"
SH
chmod +x "$CLAUDE_CLI"

echo "== rows whose origin is not a registered marketplace"
OUT=$(bash "$SCRIPT"); rc=$?
eq "$rc" 0 "exits 0 when it can classify"
has   "helper@synced|installed|user|enabled"     "a synced install is listed with its scope and state"
has   "relic@removed-mp|installed|user|disabled" "a removed marketplace's install is listed too"
has   "helper@synced|desired|-|true"             "a synced key in enabledPlugins is listed"
hasnt "alpha@mp1"                                "a registered marketplace's plugin is not listed"
hasnt "beta@mp2"                                 "project scope from a registered marketplace is not listed"
hasnt "gamma@mp2"                                "a desired plugin from a registered marketplace is not listed"

echo "== nothing unmanaged"
cp "$ROOT/list.json" "$ROOT/list.full.json"
echo '[{ "id": "alpha@mp1", "scope": "user", "enabled": true }]' > "$ROOT/list.json"
echo '{ "enabledPlugins": { "alpha@mp1": true } }' > "$CLAUDE_SETTINGS_FILE"
OUT=$(bash "$SCRIPT"); rc=$?
eq "$rc" 0 "exits 0 with nothing to list"
eq "$OUT" "" "prints nothing"

echo "== a settings file with no enabledPlugins"
echo '{}' > "$CLAUDE_SETTINGS_FILE"
OUT=$(bash "$SCRIPT"); rc=$?
eq "$rc" 0 "an absent desired set is an empty one"

echo "== a missing settings file"
rm "$CLAUDE_SETTINGS_FILE"
OUT=$(bash "$SCRIPT"); rc=$?
eq "$rc" 0 "a missing settings file is an empty desired set"

echo "== unreadable inputs are not empty ones"
cp "$ROOT/list.full.json" "$ROOT/list.json"
echo 'not json' > "$CLAUDE_SETTINGS_FILE"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "an unparseable settings file exits 1"
has "settings" "  and says which input"
echo '{}' > "$CLAUDE_SETTINGS_FILE"

echo 'not json' > "$ROOT/list.json"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "unparseable plugin list output exits 1"
hasnt "|installed|" "  and lists nothing"
cp "$ROOT/list.full.json" "$ROOT/list.json"

mv "$CLAUDE_CLI" "$CLAUDE_CLI.off"
printf '#!/usr/bin/env bash\necho boom >&2\nexit 3\n' > "$CLAUDE_CLI"; chmod +x "$CLAUDE_CLI"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "a failing claude plugin list exits 1"
mv "$CLAUDE_CLI.off" "$CLAUDE_CLI"

mv "$CLAUDE_PLUGINS_DIR/known_marketplaces.json" "$ROOT/registry.off"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "a missing marketplace registry exits 1"
hasnt "|installed|" "  rather than calling every plugin unmanaged"
echo 'not json' > "$CLAUDE_PLUGINS_DIR/known_marketplaces.json"
OUT=$(bash "$SCRIPT" 2>&1); rc=$?
eq "$rc" 1 "an unparseable marketplace registry exits 1"
mv "$ROOT/registry.off" "$CLAUDE_PLUGINS_DIR/known_marketplaces.json"

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
