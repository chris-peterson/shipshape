#!/usr/bin/env bash
# Hermetic tests for scripts/offer-guard.sh: feeds Stop payloads on stdin and
# reads the decision it prints.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/offer-guard.sh"
BASH_BIN="$(command -v bash)"

pass=0; fail=0
check() {  # $1 label  $2 actual  $3 expected
  if [ "$2" = "$3" ]; then echo "  ok: $1"; pass=$((pass + 1))
  else echo "  FAIL: $1 (got '$2', want '$3')"; fail=$((fail + 1)); fi
}

payload() {  # $1 message  $2 stop_hook_active
  jq -n --arg m "$1" --argjson a "$2" \
    '{hook_event_name: "Stop", stop_hook_active: $a, last_assistant_message: $m}'
}
decide() {  # $1 message  [$2 stop_hook_active] → the decision field, or "allow"
  local out
  out=$(payload "$1" "${2:-false}" | "$BASH_BIN" "$SCRIPT")
  if [ -z "$out" ]; then echo allow; else printf '%s' "$out" | jq -r '.decision // "allow"'; fi
}

for msg in \
  "The other 79 are internal fixes. I can walk those if you want." \
  "Let me know if you want the full list." \
  "Want me to file these?" \
  "Would you like a per-release walk?" \
  "Happy to expand on any of them." \
  "That covers 8 entries; 79 more entries are harness-internal." \
  "Say the word and I'll draft the issue." \
  "The per-release walk is available on request."
do
  check "blocks: $msg" "$(decide "$msg")" "block"
done

for msg in \
  "Claude Code 2.1.282 is acknowledged. shipshape was the only repo with fixes." \
  "Checked 86 entries: 10 touch your artifacts, 52 harness-internal, 24 not applicable." \
  "The other 12 repos had no findings." \
  "The hook blocks \`let me know if\` in replies." \
  "Settings keys moved in 2.1.282."
do
  check "allows: $msg" "$(decide "$msg")" "allow"
done

fenced=$(printf 'The guard matches:\n```\nlet me know if you want me to\n```\nDone.')
check "allows a phrase inside a code fence" "$(decide "$fenced")" "allow"

check "a rewrite that still matches is let through" \
  "$(decide "I can walk those if you want." true)" "allow"
check "and the phrase is surfaced to the user" \
  "$(payload "I can walk those if you want." true | "$BASH_BIN" "$SCRIPT" | jq -r '.systemMessage | contains("I can walk")')" "true"

reason=$(payload "Let me know if that helps." false | "$BASH_BIN" "$SCRIPT" | jq -r '.reason')
check "the block names the phrase it matched" "$(printf '%s' "$reason" | grep -c 'Let me know if')" "1"

check "an empty message is allowed" "$(decide "")" "allow"

out=$(payload "Let me know if that helps." false | PATH=/nonexistent "$BASH_BIN" "$SCRIPT" 2>/dev/null; echo "exit=$?")
check "missing jq exits 0 without a decision" "$out" "exit=0"
err=$(payload "x" false | PATH=/nonexistent "$BASH_BIN" "$SCRIPT" 2>&1 >/dev/null)
check "missing jq is reported" "$(printf '%s' "$err" | grep -c 'needs jq')" "1"

echo
echo "offer-guard: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
