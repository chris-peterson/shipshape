#!/usr/bin/env bash
# Hermetic tests for pin-plugin.
#
# SHIPSHAPE_PINS and SHIPSHAPE_MANIFEST point at throwaway files, PLUGIN_MAINT_LOCK
# at a throwaway lock, and CLAUDE_CODE_SESSION_ID gives the run a stable identity.
# Nothing here touches ~/.claude.
#
# The session id is also what a real between-sessions pin does *not* have, so the
# lock cases below clear it deliberately rather than inheriting it.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/pin-plugin"
WORK=$(mktemp -d /tmp/pin-test.XXXXXX)
# The two JSON files live in separate directories so a test can make one
# unwritable without the other. Writes are atomic (temp file + rename), and a
# rename needs write permission on the *directory*, not on the target file.
mkdir -p "$WORK/pins" "$WORK/manifest"
export SHIPSHAPE_PINS="$WORK/pins/pins.json"
export SHIPSHAPE_MANIFEST="$WORK/manifest/installed_plugins.json"
export PLUGIN_MAINT_LOCK="$WORK/maint.lock"
export CLAUDE_CODE_SESSION_ID=test-session

pass=0; fail=0
run() {  # $1 expected-exit  $2 label  $3.. command
  local want="$1" label="$2"; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then echo "  ok: $label"; pass=$((pass + 1))
  else echo "  FAIL: $label (exit $got, want $want)"; fail=$((fail + 1)); fi
}
check() {  # $1 label  $2 actual  $3 expected
  if [ "$2" = "$3" ]; then echo "  ok: $1"; pass=$((pass + 1))
  else echo "  FAIL: $1 (got '$2', want '$3')"; fail=$((fail + 1)); fi
}
path_of() { jq -r --arg k "$1" '.plugins[$k][0].installPath' "$SHIPSHAPE_MANIFEST"; }
version_of() { jq -r --arg k "$1" '.plugins[$k][0].version' "$SHIPSHAPE_MANIFEST"; }
pin_count() { jq -r '.pins | length' "$SHIPSHAPE_PINS" 2>/dev/null || echo 0; }

# A checkout is "real" when it has .claude-plugin/plugin.json declaring the plugin
# it is a checkout *of* — pin refuses a checkout of some other plugin, so the
# declared name matters, not the directory name.
mkcheckout() {  # $1 = dir under $WORK, $2 = plugin name it declares
  mkdir -p "$WORK/$1/.claude-plugin"
  echo '{"name":"'"$2"'"}' > "$WORK/$1/.claude-plugin/plugin.json"
  echo "$WORK/$1"
}

reset_manifest() {
  mkdir -p "$WORK/cache/mp/anchor/1.0.0" "$WORK/cache/mp/beacon/2.0.0" "$WORK/cache/other/dup/1.0.0"
  cat > "$SHIPSHAPE_MANIFEST" <<JSON
{"version":1,"plugins":{
  "anchor@mp":  [{"scope":"user","installPath":"$WORK/cache/mp/anchor/1.0.0","version":"1.0.0"}],
  "beacon@mp":  [{"scope":"user","installPath":"$WORK/cache/mp/beacon/2.0.0","version":"2.0.0"}],
  "twoscope@mp":[{"scope":"user","installPath":"$WORK/cache/mp/anchor/1.0.0","version":"1.0.0"},
                 {"scope":"project","installPath":"$WORK/cache/mp/anchor/1.0.0","version":"1.0.0"}],
  "dup@mp":     [{"scope":"user","installPath":"$WORK/cache/mp/anchor/1.0.0","version":"1.0.0"}],
  "dup@other":  [{"scope":"user","installPath":"$WORK/cache/other/dup/1.0.0","version":"1.0.0"}]
}}
JSON
  rm -f "$SHIPSHAPE_PINS" "$PLUGIN_MAINT_LOCK"
}

CHECKOUT=$(mkcheckout anchor-checkout anchor)
ELSEWHERE=$(mkcheckout anchor-elsewhere anchor)
DUP_CHECKOUT=$(mkcheckout dup-checkout dup)
BEACON_CHECKOUT=$(mkcheckout beacon-checkout beacon)
reset_manifest

echo "== pin =="
run 0 "pin by bare name with an explicit checkout" bash "$SCRIPT" pin anchor "$CHECKOUT"
check "installPath repointed at the checkout" "$(path_of anchor@mp)" "$CHECKOUT"
check "one pin recorded"                      "$(pin_count)" "1"
check "origin installPath recorded"           "$(jq -r '.pins["anchor@mp"].origin.installPath' "$SHIPSHAPE_PINS")" "$WORK/cache/mp/anchor/1.0.0"
check "origin version recorded"               "$(jq -r '.pins["anchor@mp"].origin.version' "$SHIPSHAPE_PINS")" "1.0.0"
check "manifest version held at the origin's" "$(version_of anchor@mp)" "1.0.0"
check "lock released after pin"               "$([ -f "$PLUGIN_MAINT_LOCK" ] || echo gone)" "gone"

run 0 "re-pin to the same checkout is idempotent" bash "$SCRIPT" pin anchor "$CHECKOUT"
check "still one pin"                         "$(pin_count)" "1"
run 1 "pin to a different checkout while pinned fails" bash "$SCRIPT" pin anchor "$ELSEWHERE"
check "checkout unchanged after refusal"      "$(path_of anchor@mp)" "$CHECKOUT"

echo "== is-pinned / list =="
run 0 "is-pinned: pinned plugin"     bash "$SCRIPT" is-pinned anchor
run 0 "is-pinned: qualified key"     bash "$SCRIPT" is-pinned anchor@mp
run 1 "is-pinned: unpinned plugin"   bash "$SCRIPT" is-pinned beacon
check "list names the pinned plugin" "$(bash "$SCRIPT" list | head -1)" "anchor@mp"

# An ambiguous name is a usage error, not exit 1 — which here means "not pinned"
# and would have a caller act on a confident no.
bash "$SCRIPT" pin dup@mp "$DUP_CHECKOUT" >/dev/null 2>&1
bash "$SCRIPT" pin dup@other "$DUP_CHECKOUT" >/dev/null 2>&1
run 2 "is-pinned: bare name matching two pins" bash "$SCRIPT" is-pinned dup
run 0 "is-pinned: either qualified key"        bash "$SCRIPT" is-pinned dup@other
bash "$SCRIPT" unpin dup@mp >/dev/null 2>&1
bash "$SCRIPT" unpin dup@other >/dev/null 2>&1

echo "== validation fails loudly, without half-applying =="
run 1 "pin to a nonexistent path"           bash "$SCRIPT" pin beacon "$WORK/nope"
run 1 "pin to a dir that is not a checkout" bash "$SCRIPT" pin beacon "$WORK"
check "beacon not repointed by failed pins" "$(path_of beacon@mp)" "$WORK/cache/mp/beacon/2.0.0"
check "no pin recorded for beacon"          "$(jq -r '.pins["beacon@mp"] // "none"' "$SHIPSHAPE_PINS")" "none"
run 1 "pin an unknown plugin"               bash "$SCRIPT" pin nosuch "$CHECKOUT"
run 1 "pin an ambiguous bare name"          bash "$SCRIPT" pin dup "$DUP_CHECKOUT"
run 0 "pin the same name qualified"         bash "$SCRIPT" pin dup@other "$DUP_CHECKOUT"
run 1 "pin a multi-record (multi-scope) plugin" bash "$SCRIPT" pin twoscope "$CHECKOUT"
check "twoscope not repointed"              "$(path_of twoscope@mp)" "$WORK/cache/mp/anchor/1.0.0"
run 2 "usage error on a bad subcommand"     bash "$SCRIPT" frobnicate
run 2 "usage error on pin with no args"     bash "$SCRIPT" pin

# The checkout is loaded under the pinned plugin's install record, so a checkout of
# a different plugin would replace the pinned plugin with that one.
run 1 "pin a plugin at another plugin's checkout" bash "$SCRIPT" pin beacon "$CHECKOUT"
check "beacon not repointed at anchor's checkout" "$(path_of beacon@mp)" "$WORK/cache/mp/beacon/2.0.0"
run 0 "pin a plugin at its own checkout"          bash "$SCRIPT" pin beacon "$BEACON_CHECKOUT"
run 0 "unpin beacon again"                        bash "$SCRIPT" unpin beacon

echo "== reconcile re-asserts a pin an update clobbered =="
# Simulate `claude plugin update`, which moves installPath *and* version together.
# Restoring only the path would leave version naming a release the origin dir isn't,
# and prune classifies the origin dir stale on the strength of that mismatch —
# deleting the dir unpin restores to.
mkdir -p "$WORK/cache/mp/anchor/1.1.0"
jq --arg p "$WORK/cache/mp/anchor/1.1.0" \
   '.plugins["anchor@mp"][0].installPath = $p | .plugins["anchor@mp"][0].version = "1.1.0"' \
   "$SHIPSHAPE_MANIFEST" > "$WORK/m.tmp" && mv "$WORK/m.tmp" "$SHIPSHAPE_MANIFEST"
check "clobbered by the simulated update" "$(path_of anchor@mp)" "$WORK/cache/mp/anchor/1.1.0"
run 0 "reconcile" bash "$SCRIPT" reconcile
check "reconcile restored the checkout"   "$(path_of anchor@mp)" "$CHECKOUT"
check "reconcile restored the origin version" "$(version_of anchor@mp)" "1.0.0"
run 0 "reconcile again is a no-op" bash "$SCRIPT" reconcile
check "still pointing at the checkout"    "$(path_of anchor@mp)" "$CHECKOUT"

# A bumped version alone is drift too: the path can be right while the version
# names a release the origin dir isn't.
jq '.plugins["anchor@mp"][0].version = "1.2.0"' "$SHIPSHAPE_MANIFEST" > "$WORK/m.tmp" && mv "$WORK/m.tmp" "$SHIPSHAPE_MANIFEST"
run 0 "reconcile after a version-only bump" bash "$SCRIPT" reconcile
check "origin version restored again"       "$(version_of anchor@mp)" "1.0.0"

echo "== unpin restores the recorded origin =="
run 0 "unpin by bare name" bash "$SCRIPT" unpin anchor
check "installPath restored to origin" "$(path_of anchor@mp)" "$WORK/cache/mp/anchor/1.0.0"
check "pin entry dropped"              "$(jq -r '.pins["anchor@mp"] // "none"' "$SHIPSHAPE_PINS")" "none"
run 1 "unpin an unpinned plugin fails" bash "$SCRIPT" unpin anchor

echo "== unpin refuses when the recorded origin is gone =="
reset_manifest
bash "$SCRIPT" pin anchor "$CHECKOUT" >/dev/null 2>&1
rm -rf "$WORK/cache/mp/anchor/1.0.0"
run 1 "unpin with a missing origin dir" bash "$SCRIPT" unpin anchor
check "pin kept so the user can recover" "$(pin_count)" "1"
check "still pointing at the checkout"   "$(path_of anchor@mp)" "$CHECKOUT"

echo "== a failure between the two writes leaves the self-correcting leftover =="
# pin repoints first and records second. Fail the record: the plugin has moved to
# the checkout with no pin backing it — which the next update repoints back. The
# order this rules out is the reverse (a recorded pin held out of update and
# prune while the plugin still loads from the cache), which nothing corrects.
reset_manifest
chmod a-w "$WORK/pins"
run 1 "pin fails when the pins file cannot be written" bash "$SCRIPT" pin anchor "$CHECKOUT"
chmod u+w "$WORK/pins"
check "no pin recorded"                        "$(pin_count)" "0"
check "plugin moved: the update path corrects it" "$(path_of anchor@mp)" "$CHECKOUT"
check "reconcile has no pin to re-assert"      "$(bash "$SCRIPT" reconcile)" "No pinned plugins."

# unpin drops the record first and restores second, so the same failure is a
# clean no-op rather than an unpin that reconcile silently re-pins.
reset_manifest
bash "$SCRIPT" pin anchor "$CHECKOUT" >/dev/null 2>&1
chmod a-w "$WORK/pins"
run 1 "unpin fails when the pins file cannot be written" bash "$SCRIPT" unpin anchor
chmod u+w "$WORK/pins"
check "pin still recorded (nothing happened)" "$(pin_count)" "1"
check "still pointing at the checkout"        "$(path_of anchor@mp)" "$CHECKOUT"

echo "== a corrupt pins file fails loudly instead of reading as \"nothing pinned\" =="
# The dangerous answer is "no pins": the maintenance run would then update the
# pinned plugin, prune the origin dir unpin restores to, and uninstall it as an extra.
reset_manifest
bash "$SCRIPT" pin anchor "$CHECKOUT" >/dev/null 2>&1
echo 'not json at all' > "$SHIPSHAPE_PINS"
run 1 "list refuses a corrupt pins file"      bash "$SCRIPT" list
run 1 "reconcile refuses a corrupt pins file" bash "$SCRIPT" reconcile
run 1 "is-pinned refuses a corrupt pins file" bash "$SCRIPT" is-pinned anchor
run 1 "pin refuses a corrupt pins file"       bash "$SCRIPT" pin beacon "$BEACON_CHECKOUT"
check "manifest untouched by the refusals"    "$(path_of beacon@mp)" "$WORK/cache/mp/beacon/2.0.0"
echo '{"version":1,"pins":"not-an-object"}' > "$SHIPSHAPE_PINS"
run 1 "a pins file of the wrong shape is refused too" bash "$SCRIPT" list

echo "== unpin will not invent an install record =="
# The manifest key can go while the pin record survives — reconcile warns about
# exactly this state and leaves the pin recorded. jq's assignment would *create*
# the key, writing a scope-less record for a plugin that is not installed.
reset_manifest
bash "$SCRIPT" pin anchor "$CHECKOUT" >/dev/null 2>&1
jq 'del(.plugins["anchor@mp"])' "$SHIPSHAPE_MANIFEST" > "$WORK/m.tmp" && mv "$WORK/m.tmp" "$SHIPSHAPE_MANIFEST"
run 1 "unpin a plugin that is gone from the manifest" bash "$SCRIPT" unpin anchor
check "no install record invented"  "$(jq -r '.plugins["anchor@mp"] // "none"' "$SHIPSHAPE_MANIFEST")" "none"
check "pin kept so the user can recover" "$(pin_count)" "1"
run 0 "reconcile warns and leaves it recorded" bash "$SCRIPT" reconcile
check "still recorded after reconcile" "$(pin_count)" "1"

echo "== a second scope appearing under a pin is refused, not guessed =="
# pin refuses a multi-record plugin outright; unpin and reconcile rewrite record
# [0], which for two scopes is a coin flip that can clobber the team-shared one.
reset_manifest
bash "$SCRIPT" pin anchor "$CHECKOUT" >/dev/null 2>&1
jq --arg p "$WORK/cache/mp/anchor/1.0.0" \
   '.plugins["anchor@mp"] = [{"scope":"project","installPath":$p,"version":"1.0.0"}] + .plugins["anchor@mp"]' \
   "$SHIPSHAPE_MANIFEST" > "$WORK/m.tmp" && mv "$WORK/m.tmp" "$SHIPSHAPE_MANIFEST"
run 1 "unpin refuses a now-multi-scope plugin" bash "$SCRIPT" unpin anchor
check "project-scope record untouched" "$(jq -r '.plugins["anchor@mp"][0].installPath' "$SHIPSHAPE_MANIFEST")" "$WORK/cache/mp/anchor/1.0.0"
check "pinned record untouched"        "$(jq -r '.plugins["anchor@mp"][1].installPath' "$SHIPSHAPE_MANIFEST")" "$CHECKOUT"
run 0 "reconcile warns and skips it"   bash "$SCRIPT" reconcile
check "project-scope record still untouched" "$(jq -r '.plugins["anchor@mp"][0].installPath' "$SHIPSHAPE_MANIFEST")" "$WORK/cache/mp/anchor/1.0.0"

echo "== another session's lock blocks a pin =="
reset_manifest
env CLAUDE_CODE_SESSION_ID=someone-else bash "$(dirname "$SCRIPT")/plugin-maintenance-lock.sh" acquire >/dev/null 2>&1
run 3 "pin bails while another session reconciles" bash "$SCRIPT" pin anchor "$CHECKOUT"
check "manifest untouched while blocked" "$(path_of anchor@mp)" "$WORK/cache/mp/anchor/1.0.0"
run 0 "--no-lock proceeds for a caller holding the lock" bash "$SCRIPT" pin anchor "$CHECKOUT" --no-lock
check "pin applied under --no-lock" "$(path_of anchor@mp)" "$CHECKOUT"
check "other session's lock still held" "$(jq -r .session "$PLUGIN_MAINT_LOCK")" "someone-else"

echo "== the lock is released with no session id, as a real pin runs =="
# Between sessions there is no CLAUDE_CODE_SESSION_ID, and the lock's pid fallback
# is the pid of each *lock* process — one per acquire and release here. Leaking the
# lock blocks every later maintenance run for the full stale window.
reset_manifest
run 0 "pin with no session id"     env -u CLAUDE_CODE_SESSION_ID bash "$SCRIPT" pin anchor "$CHECKOUT"
check "lock released after pin"    "$([ -f "$PLUGIN_MAINT_LOCK" ] || echo gone)" "gone"
run 0 "unpin with no session id"   env -u CLAUDE_CODE_SESSION_ID bash "$SCRIPT" unpin anchor
check "lock released after unpin"  "$([ -f "$PLUGIN_MAINT_LOCK" ] || echo gone)" "gone"
run 0 "reconcile with no session id" env -u CLAUDE_CODE_SESSION_ID bash "$SCRIPT" reconcile
check "lock released after reconcile" "$([ -f "$PLUGIN_MAINT_LOCK" ] || echo gone)" "gone"

rm -rf "$WORK"
echo
echo "pin-plugin: pass=$pass fail=$fail"
[ "$fail" = 0 ]
