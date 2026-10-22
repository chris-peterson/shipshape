#!/usr/bin/env bash
# Hermetic tests for scripts/fetch-jq.sh.
#
# Each case runs with PATH set to a fixture dir of wrappers around the real
# tools the script needs, minus jq, plus a stub `uname` naming the platform. The
# download base points at a fixture dir over file://, so nothing touches the
# network, and the served "jq" is a shell script whose hash the case pins with
# SHIPSHAPE_JQ_SHA256 where it wants the check to pass.

set -uo pipefail
. "$(dirname "$0")/../platform.sh"

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/fetch-jq.sh"
PLATFORM="$(cd "$(dirname "$0")/.." && pwd)/platform.sh"
BASH_BIN="$(command -v bash)"

FIXTURES=$(mktemp -d /tmp/fetch-jq.XXXXXX)
trap 'rm -rf "$FIXTURES"' EXIT

pass=0; fail=0
check() {  # $1 label  $2 actual  $3 expected
  if [ "$2" = "$3" ]; then echo "  ok: $1"; pass=$((pass + 1))
  else echo "  FAIL: $1 (got '$2', want '$3')"; fail=$((fail + 1)); fi
}
contains() {  # $1 label  $2 haystack  $3 needle
  case "$2" in
    *"$3"*) echo "  ok: $1"; pass=$((pass + 1)) ;;
    *) echo "  FAIL: $1 ('$2' lacks '$3')"; fail=$((fail + 1)) ;;
  esac
}

if command -v sha256sum >/dev/null 2>&1; then HASHER=sha256sum; else HASHER=shasum; fi
hash_of() { local h; if [ "$HASHER" = shasum ]; then h=$(shasum -a 256 "$1"); else h=$(sha256sum "$1"); fi; printf '%s' "${h%% *}"; }

# curl under git-bash is a native build, which reads file:///C:/... and not /c/...
file_url() {
  case "${OSTYPE:-}" in
    msys*|cygwin*) printf 'file:///%s' "$(cygpath -m "$1")" ;;
    *)             printf 'file://%s' "$1" ;;
  esac
}

# Fresh fixture. $1 $2 = what the stub `uname` reports for -s and -m.
# Sets TOOLS (the PATH), SERVE (the download base dir), DATA (CLAUDE_PLUGIN_DATA).
setup() {
  TOOLS=$(mktemp -d "$FIXTURES/tools.XXXXXX")
  SERVE=$(mktemp -d "$FIXTURES/serve.XXXXXX")
  DATA=$(mktemp -d "$FIXTURES/data.XXXXXX")
  local t
  for t in curl "$HASHER" mkdir mktemp rm chmod mv cat; do
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$t")" > "$TOOLS/$t"
    chmod +x "$TOOLS/$t"
  done
  printf '#!/bin/sh\ncase "$1" in -s) echo "%s" ;; -m) echo "%s" ;; esac\n' "$1" "$2" > "$TOOLS/uname"
  chmod +x "$TOOLS/uname"
}
serve() {  # $1 asset name  $2 file body
  printf '%s' "$2" > "$SERVE/$1"
}
fetch() {  # run the script in the fixture; sets OUT, ERR, RC. Extra args pass through as env.
  local err; err=$(mktemp "$FIXTURES/err.XXXXXX")
  OUT=$(env PATH="$TOOLS" CLAUDE_PLUGIN_DATA="$DATA" SHIPSHAPE_JQ_URL="$(file_url "$SERVE")" "$@" "$BASH_BIN" "$SCRIPT" 2>"$err"); RC=$?
  ERR=$(cat "$err"); rm -f "$err"
}
leftovers() { find "$DATA" -name '.jq.*' | wc -l | tr -d ' '; }

STUB_JQ='#!/bin/sh
echo jq-1.8.2
'

# --- jq already on PATH: printed, nothing downloaded. ---
setup Linux x86_64
printf '#!/bin/sh\n' > "$TOOLS/jq"; chmod +x "$TOOLS/jq"
fetch
check    "a jq on PATH exits 0"                    "$RC"  "0"
check    "a jq on PATH is the one printed"         "$OUT" "$TOOLS/jq"
check    "a jq on PATH downloads nothing"          "$([ -e "$DATA/bin" ] || echo absent)" "absent"

# --- Download succeeds and matches the pin: installed and printed. ---
setup Linux x86_64
serve jq-linux-amd64 "$STUB_JQ"
fetch SHIPSHAPE_JQ_SHA256="$(hash_of "$SERVE/jq-linux-amd64")"
check    "a pinned download exits 0"               "$RC"  "0"
check    "a pinned download prints its path"       "$OUT" "$DATA/bin/jq"
check    "the installed jq is executable"          "$([ -x "$DATA/bin/jq" ] && echo yes)" "yes"
check    "no temp file is left behind"             "$(leftovers)" "0"

# --- platform.sh puts the fetched jq on PATH where the system has none. ---
check    "platform.sh finds the fetched jq"        "$(env PATH="$TOOLS" CLAUDE_PLUGIN_DATA="$DATA" "$BASH_BIN" -c '. "$1"; type -P jq' _ "$PLATFORM")" "$DATA/bin/jq"
check    "platform.sh leaves PATH alone without a data dir" \
         "$(env -u CLAUDE_PLUGIN_DATA PATH="$TOOLS" "$BASH_BIN" -c '. "$1"; type -P jq || echo none' _ "$PLATFORM")" "none"
printf '#!/bin/sh\n' > "$TOOLS/jq"; chmod +x "$TOOLS/jq"
check    "platform.sh prefers a system jq to the fetched one" \
         "$(env PATH="$TOOLS" CLAUDE_PLUGIN_DATA="$DATA" "$BASH_BIN" -c '. "$1"; type -P jq' _ "$PLATFORM")" "$TOOLS/jq"

# --- Windows names the asset and the binary .exe. ---
setup MINGW64_NT-10.0 x86_64
serve jq-windows-amd64.exe "$STUB_JQ"
fetch SHIPSHAPE_JQ_SHA256="$(hash_of "$SERVE/jq-windows-amd64.exe")"
check    "a Windows download exits 0"              "$RC"  "0"
check    "a Windows download installs jq.exe"      "$OUT" "$DATA/bin/jq.exe"

# --- A data dir Claude Code names in Windows form still passes the hash check
# and lands on PATH. sha256sum and shasum escape a backslash in a file name by
# prefixing the hash with one; git-bash has no other way to make that name. ---
setup Linux x86_64
serve jq-linux-amd64 "$STUB_JQ"
case "${OSTYPE:-}" in
  msys*|cygwin*)
    WINDATA=$(cygpath -w "$DATA")
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v cygpath)" > "$TOOLS/cygpath"
    chmod +x "$TOOLS/cygpath"
    OUT=$(env PATH="$TOOLS" CLAUDE_PLUGIN_DATA="$WINDATA" SHIPSHAPE_JQ_URL="$(file_url "$SERVE")" \
          SHIPSHAPE_JQ_SHA256="$(hash_of "$SERVE/jq-linux-amd64")" "$BASH_BIN" "$SCRIPT" 2>&1); RC=$?
    check "a Windows-form data dir passes the hash check" "$RC" "0"
    check "platform.sh puts a Windows-form data dir on PATH" \
          "$(env PATH="$TOOLS" CLAUDE_PLUGIN_DATA="$WINDATA" "$BASH_BIN" -c '. "$1"; type -P jq >/dev/null && echo found' _ "$PLATFORM")" "found"
    ;;
  *)
    DATA=$(mktemp -d "$FIXTURES/data\\dir.XXXXXX")
    fetch SHIPSHAPE_JQ_SHA256="$(hash_of "$SERVE/jq-linux-amd64")"
    check "a backslash in the data dir passes the hash check" "$RC" "0"
    ;;
esac

# --- The real pin rejects a binary it doesn't name. ---
setup Darwin arm64
serve jq-macos-arm64 "$STUB_JQ"
fetch
check    "a hash mismatch exits 1"                 "$RC"  "1"
contains "a hash mismatch says so"                 "$ERR" "not the pinned"
check    "a hash mismatch installs nothing"        "$([ -e "$DATA/bin/jq" ] || echo absent)" "absent"
check    "a hash mismatch leaves no temp file"     "$(leftovers)" "0"

# --- A binary that doesn't run here is not installed. ---
setup Linux aarch64
serve jq-linux-arm64 '#!/bin/sh
exit 1
'
fetch SHIPSHAPE_JQ_SHA256="$(hash_of "$SERVE/jq-linux-arm64")"
check    "a binary that won't run exits 1"         "$RC"  "1"
contains "a binary that won't run says so"         "$ERR" "does not run here"
check    "a binary that won't run is not installed" "$([ -e "$DATA/bin/jq" ] || echo absent)" "absent"

# --- Download fails: reported, nothing installed. ---
setup Linux x86_64
fetch
check    "a failed download exits 1"               "$RC"  "1"
contains "a failed download names the URL"         "$ERR" "could not download"
check    "a failed download installs nothing"      "$([ -e "$DATA/bin/jq" ] || echo absent)" "absent"
check    "a failed download leaves no temp file"   "$(leftovers)" "0"

# --- No binary pinned for the platform. ---
setup FreeBSD amd64
fetch
check    "an unpinned OS exits 1"                  "$RC"  "1"
contains "an unpinned OS is named"                 "$ERR" "FreeBSD"
setup Linux riscv64
fetch
check    "an unpinned arch exits 1"                "$RC"  "1"
contains "an unpinned arch is named"               "$ERR" "riscv64"

# --- No data dir: nowhere to install. ---
setup Linux x86_64
OUT=$(env -u CLAUDE_PLUGIN_DATA PATH="$TOOLS" "$BASH_BIN" "$SCRIPT" 2>&1); RC=$?
check    "an unset data dir exits 1"               "$RC"  "1"
contains "an unset data dir says so"               "$OUT" "CLAUDE_PLUGIN_DATA is unset"

# --- No curl: reported before anything is written. ---
setup Linux x86_64
rm "$TOOLS/curl"
fetch
check    "a missing curl exits 1"                  "$RC"  "1"
contains "a missing curl says so"                  "$ERR" "curl is not on PATH"

echo
echo "fetch-jq: pass=$pass fail=$fail"
[ "$fail" = 0 ]
