#!/usr/bin/env bash
# Stop hook, declared in each shipshape skill's frontmatter: blocks a reply that
# offers more work instead of doing it ("let me know if…", "I can walk those…",
# "79 more entries…"). Claude Code registers a skill's hooks when the skill is
# invoked and keeps them for the rest of the session.
#
# Prose guidance alone doesn't hold this line, so the check is a script:
# deterministic, and tested. Text inside code spans, fences, and double quotes
# is ignored, so a reply can quote a phrase without tripping it.
#
# Blocks once per stop. When Claude is already continuing from this block
# (stop_hook_active) and the rewrite still matches, the stop is allowed and the
# phrase is surfaced to the user, rather than looping on a false positive.

# covers: REPORT-08, REPORT-09
set -euo pipefail
. "${BASH_SOURCE[0]%/*}/platform.sh"

# Extended regexes, matched case-insensitively.
PATTERNS=(
  # Handing the next step back to the user.
  'let me know if'
  "if you('d| would)? (like|want|prefer)"
  '(do you )?want me to'
  'would you like'
  'say the word'
  # Offering work instead of doing it. "happy to" and "on request" need the
  # offer around them: on their own they turn up in ordinary sentences.
  'happy to (walk|go through|expand|dig|show|list|print|file|draft|run|do|share)'
  '(available|shown|shared|listed|walked|expanded) on request'
  'should i (also )?(walk|go|list|show|print|expand|file|draft|run|do)'
  'i can (also )?(walk|go through|expand|dig|show|list|print|file|draft|run|do)'
  # Counting what wasn't shown. A tally ("the other 34 are harness-internal")
  # reads the same whether or not those entries were walked, so only a count
  # past what the reply showed is matched.
  '[0-9]+ more (entries|items|changes|releases)'
  '(left out|omitted|not shown|skipped) (for brevity|here|above|below)'
)
grep_args=()
for pattern in "${PATTERNS[@]}"; do grep_args+=(-e "$pattern"); done

if ! command -v jq >/dev/null 2>&1; then
  echo "shipshape: offer-guard needs jq, which is not on PATH; the reply was not checked." >&2
  # Drain the payload so the writer never meets a closed pipe (SIGPIPE). A
  # builtin, since a PATH without jq may lack cat too.
  while IFS= read -r _; do :; done
  exit 0
fi

input=$(cat)
message=$(printf '%s' "$input" | jq -r '.last_assistant_message // ""')
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')

prose=$(printf '%s\n' "$message" \
  | awk '/^[[:space:]]*```/ { fenced = !fenced; next } !fenced' \
  | sed -E -e 's/`[^`]*`//g' -e 's/"[^"]*"//g' -e 's/“[^”]*”//g')

match=$(printf '%s\n' "$prose" | grep -Eio "${grep_args[@]}" | head -1 || true)
[ -n "$match" ] || exit 0

if [ "$active" = "true" ]; then
  jq -n --arg m "$match" \
    '{systemMessage: ("shipshape: this reply still offers more instead of doing it (\"" + $m + "\").")}'
  exit 0
fi

jq -n --arg m "$match" '{
  decision: "block",
  reason: ("shipshape: this reply offers more instead of doing it (\"" + $m + "\"). Rewrite it without the offer: do the work it offers, or drop the sentence. Every entry is walked, nothing is counted as left out, and a decision the user must make goes in one AskUserQuestion.")
}'
