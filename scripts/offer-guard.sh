#!/usr/bin/env bash
# Stop hook, declared in each shipshape skill's frontmatter: blocks a reply that
# offers more work instead of doing it ("let me know if…", "I can walk those…",
# "the other 79 are…"). Claude Code registers a skill's hooks when the skill is
# invoked and keeps them for the rest of the session.
#
# Prose guidance alone doesn't hold this line, so the check is a script:
# deterministic, and tested. Text inside code spans and fences is ignored, so a
# reply can quote a phrase without tripping it.
#
# Blocks once per stop. When Claude is already continuing from this block
# (stop_hook_active) and the rewrite still matches, the stop is allowed and the
# phrase is surfaced to the user, rather than looping on a false positive.

# covers: REPORT-08, REPORT-09
set -euo pipefail

PATTERNS="${BASH_SOURCE[0]%/*}/offer-phrases.txt"

if ! command -v jq >/dev/null 2>&1; then
  echo "shipshape: offer-guard needs jq, which is not on PATH; the reply was not checked." >&2
  exit 0
fi

input=$(cat)
message=$(printf '%s' "$input" | jq -r '.last_assistant_message // ""')
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')

prose=$(printf '%s\n' "$message" \
  | awk '/^[[:space:]]*```/ { fenced = !fenced; next } !fenced' \
  | sed -E 's/`[^`]*`//g')

match=$(printf '%s\n' "$prose" | grep -Eio -f "$PATTERNS" | head -1 || true)
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
