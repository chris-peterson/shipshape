#!/usr/bin/env bash
# Hermetic tests for plugin-cache-in-use.sh.
#
# Uses the test process's own PID ($$) as a guaranteed-live process, so the
# suite doesn't depend on real plugin caches or on any particular session being
# alive. Each case builds a throwaway lease dir and asserts the exit code:
# 0 = in use (don't prune), 1 = not in use (safe to prune).

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin-cache-in-use.sh"

pass=0; fail=0
run() {  # $1 expected-exit  $2 label  $3.. command
  local want="$1" label="$2"; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then
    echo "  ok: $label"; pass=$((pass + 1))
  else
    echo "  FAIL: $label (exit $got, want $want)"; fail=$((fail + 1))
  fi
}

# Build a throwaway version dir holding one lease with the given JSON body.
mklease() {  # $1 = json body -> prints the dir path
  local d; d=$(mktemp -d); mkdir "$d/.in_use"; printf '%s' "$1" > "$d/.in_use/lease"; echo "$d"
}

# This process's start time, as `ps` prints it (local zone) — a real live PID.
LSTART=$(ps -p $$ -o lstart= | sed 's/^ *//;s/ *$//')

d=$(mktemp -d);                                              run 1 "no .in_use dir"                              bash "$SCRIPT" "$d"; rm -rf "$d"
d=$(mklease "{\"pid\":$$,\"procStart\":\"$LSTART\"}");        run 0 "live pid + matching procStart (local zone)"  bash "$SCRIPT" "$d"; rm -rf "$d"
d=$(mklease "{\"pid\":$$,\"procStart\":\"Mon Jan 01 00:00:00 2020\"}"); run 1 "live pid + recycled (wrong procStart)" bash "$SCRIPT" "$d"; rm -rf "$d"
d=$(mklease "{\"pid\":999999,\"procStart\":\"$LSTART\"}");    run 1 "dead pid"                                     bash "$SCRIPT" "$d"; rm -rf "$d"
d=$(mklease "{\"pid\":$$}");                                  run 0 "live pid + missing procStart (conservative)" bash "$SCRIPT" "$d"; rm -rf "$d"
d=$(mklease "{\"pid\":$$,\"procStart\":\"not-a-timestamp\"}"); run 0 "live pid + unparseable procStart (conservative)" bash "$SCRIPT" "$d"; rm -rf "$d"

# An unreadable lease is not an absent lease. A torn write from a session that
# died mid-startup yields no pid, and reading that as "no lease here" prunes the
# dir it was in the middle of claiming.
d=$(mklease "{\"pid\":$$,\"procSta");                     run 0 "truncated lease (torn write) -> in use"      bash "$SCRIPT" "$d"; rm -rf "$d"
d=$(mklease "");                                          run 0 "empty lease file -> in use"                  bash "$SCRIPT" "$d"
ERR=$(bash "$SCRIPT" "$d" 2>&1 >/dev/null); rm -rf "$d"
case "$ERR" in
  *"yields no pid"*) echo "  ok: the unreadable lease is surfaced on stderr"; pass=$((pass + 1)) ;;
  *) echo "  FAIL: the unreadable lease is surfaced on stderr (got '$ERR')"; fail=$((fail + 1)) ;;
esac
d=$(mklease "not json at all");                           run 0 "non-JSON lease -> in use"                    bash "$SCRIPT" "$d"; rm -rf "$d"
d=$(mklease "{\"procStart\":\"$LSTART\"}");               run 0 "lease with no pid field -> in use"           bash "$SCRIPT" "$d"; rm -rf "$d"

# jq-missing must fail conservative (in use), not silently prune. An empty PATH
# makes jq unresolvable (dropping one dir isn't enough — jq is often in several);
# invoke bash by absolute path so the interpreter still loads. The guard fires
# before any external tool is needed.
BASH_BIN=$(command -v bash)
empty=$(mktemp -d)
d=$(mklease "{\"pid\":$$,\"procStart\":\"$LSTART\"}")
run 0 "jq missing -> conservative in use" env PATH="$empty" "$BASH_BIN" "$SCRIPT" "$d"
rm -rf "$d" "$empty"

echo
echo "plugin-cache-in-use: pass=$pass fail=$fail"
[ "$fail" = 0 ]
