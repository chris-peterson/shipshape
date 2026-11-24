#!/usr/bin/env bash
# Hermetic tests for issue-draft-link.sh.
#
# Builds throwaway checkouts whose origin is each remote shape git accepts, and
# drafts in the shape the skill writes: a `# ` title line, then the body.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/issue-draft-link.sh"

pass=0; fail=0
ok()   { echo "  ok: $1"; pass=$((pass + 1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail + 1)); }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1', want '$2')"; fi; }
has()  { case "$OUT" in *"$1"*) ok "$2" ;; *) bad "$2 (missing '$1')" ;; esac; }
hasnt(){ case "$OUT" in *"$1"*) bad "$2 (found '$1')" ;; *) ok "$2" ;; esac; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

repo() { # name origin-url
  git init -q "$ROOT/$1"
  [ -n "$2" ] && git -C "$ROOT/$1" remote add origin "$2"
  printf '%s' "$ROOT/$1"
}

D="$ROOT/drafts"; mkdir -p "$D"
printf '# Fix the hook matcher\n\nThe matcher misses `Stop`.\n\nSee hooks.json:12 & fix it?\n' > "$D/one.md"

echo "== GitHub"
GH=$(repo gh git@github.com:acme/widgets.git)
OUT=$(bash "$SCRIPT" "$GH" "$D/one.md"); rc=$?
eq "$rc" 0 "exits 0"
has "$D/one.md|full|https://github.com/acme/widgets/issues/new?title=Fix%20the%20hook%20matcher&body=" "links GitHub's new-issue form from an scp-style remote"
has "body=The%20matcher%20misses%20%60Stop%60.%0A%0ASee%20hooks.json%3A12%20%26%20fix%20it%3F" "encodes the body, & and ? included, with the leading blank dropped"
case "$OUT" in *%0A) bad "drops the trailing newline (link ends in %0A)" ;; *) ok "drops the trailing newline" ;; esac

for remote in https://github.com/acme/widgets.git https://tok@github.com/acme/widgets ssh://git@github.com:22/acme/widgets.git; do
  R=$(repo "r$RANDOM" "$remote")
  OUT=$(bash "$SCRIPT" "$R" "$D/one.md")
  has "|full|https://github.com/acme/widgets/issues/new?" "reads $remote"
done

echo "== GitLab"
GL=$(repo gl git@gitlab.example.com:team/sub/svc.git)
OUT=$(bash "$SCRIPT" "$GL" "$D/one.md")
has "|full|https://gitlab.example.com/team/sub/svc/-/issues/new?issue%5Btitle%5D=Fix%20the%20hook%20matcher&issue%5Bdescription%5D=The" "links GitLab's form, subgroups kept"

echo "== drafts the user edited"
printf '\n\n# Title only\n' > "$D/bare.md"
printf 'No heading here\n\nbody\n' > "$D/nohead.md"
printf '# Windows\r\n\r\nline\r\n' > "$D/crlf.md"
OUT=$(bash "$SCRIPT" "$GH" "$D/bare.md" "$D/nohead.md" "$D/crlf.md"); rc=$?
eq "$rc" 0 "exits 0 across mixed drafts"
has "$D/bare.md|full|https://github.com/acme/widgets/issues/new?title=Title%20only" "an empty body links the title alone"
hasnt "title=Title%20only&body" "  with no body parameter"
has "$D/nohead.md|no-title|-" "a draft whose first line isn't a heading says so"
has "$D/crlf.md|full|https://github.com/acme/widgets/issues/new?title=Windows&body=line" "CRLF drafts read clean"
eq "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" 3 "one line per draft"

echo "== a body too long for a link"
{ echo '# Long one'; echo; head -c 3000 /dev/zero | tr '\0' ' '; echo x; } > "$D/long.md"
OUT=$(bash "$SCRIPT" "$GH" "$D/long.md")
eq "$OUT" "$D/long.md|title-only|https://github.com/acme/widgets/issues/new?title=Long%20one" "past the cap, the title alone is prefilled"
OUT=$(SHIPSHAPE_LINK_MAX=20000 bash "$SCRIPT" "$GH" "$D/long.md")
has "|full|" "the cap is SHIPSHAPE_LINK_MAX"

echo "== no form to link"
BB=$(repo bb git@bitbucket.org:acme/widgets.git)
OUT=$(bash "$SCRIPT" "$BB" "$D/one.md" 2>&1); rc=$?
eq "$rc" 2 "a host that's neither forge exits 2"
has "neither GitHub nor GitLab" "  and says so"
NO=$(repo none "")
OUT=$(bash "$SCRIPT" "$NO" "$D/one.md" 2>&1); rc=$?
eq "$rc" 1 "a checkout with no origin exits 1"
has "no origin remote" "  and says so"
OUT=$(bash "$SCRIPT" "$GH" "$D/missing.md" 2>&1); rc=$?
eq "$rc" 1 "an unreadable draft exits 1"
OUT=$(bash "$SCRIPT" "$GH" 2>&1); rc=$?
eq "$rc" 1 "no drafts is a usage error"

echo "== without jq"
OUT=$(PATH=/nonexistent CLAUDE_PLUGIN_DATA='' /bin/bash "$SCRIPT" "$GH" "$D/one.md" 2>&1); rc=$?
eq "$rc" 1 "exits 1 with no jq"
has "jq not on PATH" "  and says so"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
