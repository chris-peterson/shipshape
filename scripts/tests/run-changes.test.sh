#!/usr/bin/env bash
# Hermetic tests for run-changes.sh.
#
# Builds throwaway git repos, snapshots them, changes them the ways a run and a
# concurrent session would, and checks the report lists only the run's changes.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/run-changes.sh"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
export CLAUDE_PLUGIN_DATA="$ROOT/data"
export CLAUDE_CODE_SESSION_ID=S1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

pass=0; fail=0
check() {  # $1 label  $2 actual  $3 expected
  if [ "$2" = "$3" ]; then echo "  ok: $1"; pass=$((pass + 1))
  else printf '  FAIL: %s\n    got:  %s\n    want: %s\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}
has() {  # $1 label  $2 haystack  $3 needle line
  if printf '%s\n' "$2" | grep -qxF -- "$3"; then echo "  ok: $1"; pass=$((pass + 1))
  else printf '  FAIL: %s\n    missing: %s\n    in:\n%s\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
lacks() {  # $1 label  $2 haystack  $3 substring
  if printf '%s\n' "$2" | grep -qF -- "$3"; then printf '  FAIL: %s\n    unexpected: %s\n' "$1" "$3"; fail=$((fail + 1))
  else echo "  ok: $1"; pass=$((pass + 1)); fi
}
mkrepo() {  # $1 dir
  mkdir -p "$1"
  git -C "$1" init -q
  printf 'a\n' > "$1/a.txt"; printf 'b\n' > "$1/b.txt"; printf 'c\n' > "$1/c.txt"
  git -C "$1" add -A; git -C "$1" commit -qm init
  git -C "$1" rev-parse --show-toplevel
}

A=$(mkrepo "$ROOT/a")
B=$(mkrepo "$ROOT/b")

# Another session's work, present before the run starts.
printf 'other\n' >> "$A/a.txt"
printf 'other\n' > "$A/theirs.txt"

bash "$SCRIPT" start "$A" "$ROOT/not-a-repo" 2>/dev/null
check "start exits 0" "$?" "0"

# The run's own writes.
printf 'run\n' >> "$A/b.txt"
printf 'new\n' > "$A/new.txt"
rm "$A/c.txt"

# A repo the run snapshots later, right before writing to it, then commits.
bash "$SCRIPT" start "$B"
bash "$SCRIPT" start "$A"   # a repeat start keeps the first snapshot
printf 'run\n' >> "$B/a.txt"
git -C "$B" commit -qam "run commit"
sha=$(git -C "$B" rev-parse --short=7 HEAD)

# The run also touches a file another session had already changed.
printf 'more\n' >> "$A/a.txt"

out=$(bash "$SCRIPT" report)
check "report exits 0" "$?" "0"

has "the run's edit is listed"            "$out" "$A|b.txt|modified|clean"
has "the run's new file is listed"        "$out" "$A|new.txt|untracked|clean"
has "the run's delete is listed"          "$out" "$A|c.txt|deleted|clean"
has "a file already dirty is marked"      "$out" "$A|a.txt|modified|dirty"
has "a commit during the run is listed"   "$out" "$B|a.txt|committed $sha|clean"
has "a non-repo dir is reported"          "$out" "$ROOT/not-a-repo|-|not-a-repo|-"
lacks "another session's file stays out"  "$out" "theirs.txt"
has "totals count repos and paths"        "$out" "#totals repos=2 changed=5 not_a_repo=1"

check "report forgets the run" "$([ -f "$CLAUDE_PLUGIN_DATA/run-changes/S1.tsv" ] || echo gone)" "gone"

# A file dirty at the snapshot and clean after, with HEAD unmoved, was restored.
printf 'x\n' >> "$B/b.txt"
bash "$SCRIPT" start "$B"
git -C "$B" checkout -q -- b.txt
out=$(bash "$SCRIPT" report)
has "a restored file is listed" "$out" "$B|b.txt|restored|dirty"

# Nothing changed: totals only.
bash "$SCRIPT" start "$B"
out=$(bash "$SCRIPT" report)
check "an unchanged repo reports nothing" "$out" "#totals repos=1 changed=0 not_a_repo=0"

# Sessions don't see each other's runs.
bash "$SCRIPT" start "$A"
CLAUDE_CODE_SESSION_ID=S2 bash "$SCRIPT" report >/dev/null 2>&1
check "another session has no run to report" "$?" "1"
bash "$SCRIPT" report >/dev/null

# Refusals are loud.
bash "$SCRIPT" report >/dev/null 2>&1
check "report without start exits 1" "$?" "1"
env -u CLAUDE_CODE_SESSION_ID bash "$SCRIPT" start "$A" >/dev/null 2>&1
check "an unset session id exits 1" "$?" "1"
env -u CLAUDE_PLUGIN_DATA bash "$SCRIPT" start "$A" >/dev/null 2>&1
check "an unset data dir exits 1" "$?" "1"
bash "$SCRIPT" start >/dev/null 2>&1
check "start with no dirs is a usage error" "$?" "2"
bash "$SCRIPT" frobnicate >/dev/null 2>&1
check "a bad subcommand is a usage error" "$?" "2"

echo
echo "run-changes: pass=$pass fail=$fail"
[ "$fail" = 0 ]
