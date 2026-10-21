#!/usr/bin/env bash
# Provide jq when the system has none: download jq's standalone release binary
# for this platform into $CLAUDE_PLUGIN_DATA/bin, where platform.sh puts it on
# PATH for every script that sources it.
#
# Without jq the auto-update hook can't enable marketplace auto-update, and
# Claude Code leaves third-party marketplaces off by default, so a missing jq
# stranded shipshape on whatever version was first installed, along with every
# release that would have said why.
#
# The binary is trusted by the SHA-256 pinned here, not by the sha256sum.txt
# published beside it: a checksum fetched from the same place as the file proves
# it arrived intact, not that it is the file shipshape reviewed. Bumping
# JQ_VERSION means re-pinning every hash from the release's asset digests.
#
# Usage:  fetch-jq.sh
#
# Exit:   0 = jq is available; its path is printed
#         1 = no jq, and none could be installed; the reason is on stderr
#
# Env:    CLAUDE_PLUGIN_DATA   where bin/ is created
#         SHIPSHAPE_JQ_URL     override the download base (tests)
#         SHIPSHAPE_JQ_SHA256  override the pinned hash (tests)

# covers: JSON-02, JSON-03, JSON-04, JSON-05
set -euo pipefail
. "${BASH_SOURCE[0]%/*}/platform.sh"

JQ_VERSION=1.8.2
BASE="${SHIPSHAPE_JQ_URL:-https://github.com/jqlang/jq/releases/download/jq-$JQ_VERSION}"

fail() { printf 'fetch-jq: %s\n' "$1" >&2; exit 1; }

if type -P jq >/dev/null; then
  type -P jq
  exit 0
fi

[ -n "${CLAUDE_PLUGIN_DATA:-}" ] || fail "CLAUDE_PLUGIN_DATA is unset; nowhere to put jq"

case "$(uname -s)" in
  Darwin)                os=macos ;;
  Linux)                 os=linux ;;
  MINGW*|MSYS*|CYGWIN*)  os=windows ;;
  *)                     fail "no jq binary is pinned for $(uname -s)" ;;
esac
case "$(uname -m)" in
  x86_64|amd64)   arch=amd64 ;;
  arm64|aarch64)  arch=arm64 ;;
  *)              fail "no jq binary is pinned for $os on $(uname -m)" ;;
esac

case "$os-$arch" in
  macos-arm64)    pin=2d75340ba57a4b4b4c8708a21c2dc8e958a48aaa8bba13b27f77f6e4c0eca07e ;;
  macos-amd64)    pin=e94b266e3c26690550006abe63152b782280f4e14374accdf04cbde844f00bc0 ;;
  linux-amd64)    pin=b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f ;;
  linux-arm64)    pin=8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309 ;;
  windows-amd64)  pin=a6fc67fedaf9128a3309a1e2ebb8b986aeccf70122ee46d2cb4849e423f0c627 ;;
  windows-arm64)  pin=083b5377392bc57cf27052b6d20a2d927770683bca844632901ff38b4b7b0ac7 ;;
esac
pin="${SHIPSHAPE_JQ_SHA256:-$pin}"

asset="jq-$os-$arch"
name=jq
if [ "$os" = windows ]; then asset="$asset.exe"; name=jq.exe; fi

command -v curl >/dev/null 2>&1 || fail "curl is not on PATH; cannot download jq"
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1"; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1"; }
else
  fail "neither sha256sum nor shasum is on PATH; cannot check a downloaded jq"
fi

bin="$CLAUDE_PLUGIN_DATA/bin"
mkdir -p "$bin"
# Both SessionStart hooks can get here at once on a first run. Each downloads to
# its own temp file and renames it into place, so neither sees a partial binary.
tmp="$(mktemp "$bin/.jq.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

# The hook that calls this holds up session start, so the wait is bounded.
curl -fsSL --connect-timeout 5 --max-time 30 -o "$tmp" "$BASE/$asset" \
  || fail "could not download $BASE/$asset"

got="$(sha256 "$tmp")"
got="${got%% *}"
[ "$got" = "$pin" ] || fail "$asset has SHA-256 $got, not the pinned $pin; not installed"

chmod +x "$tmp"
"$tmp" --version >/dev/null 2>&1 || fail "the downloaded $asset does not run here; not installed"

mv "$tmp" "$bin/$name"
printf '%s\n' "$bin/$name"
