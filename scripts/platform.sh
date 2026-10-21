# Sourced by every script that reads jq output or compares paths, so git-bash on
# Windows sees the same bytes macOS and Linux do. Bash builtins only: a caller
# may run it with an empty PATH to exercise its own missing-jq branch.

# A jq that fetch-jq.sh downloaded, used only where the system has none.
# covers: JSON-06
if ! type -P jq >/dev/null && [ -n "${CLAUDE_PLUGIN_DATA:-}" ] \
   && { [ -x "$CLAUDE_PLUGIN_DATA/bin/jq" ] || [ -x "$CLAUDE_PLUGIN_DATA/bin/jq.exe" ]; }; then
  PATH="$CLAUDE_PLUGIN_DATA/bin:$PATH"
fi

case "${OSTYPE:-}" in
  msys*|cygwin*)
    # A native jq.exe ends lines with CRLF, and $(...) keeps every \r but the
    # last. Defined only over a real jq, so `command -v jq` still finds none.
    if type -P jq >/dev/null; then jq() { command jq -b "$@"; }; fi
    # Claude Code records Windows paths (C:\Users\...) where find reports
    # /c/Users/..., so a path read from a manifest is converted before compare.
    posix_paths() { cygpath -u -f -; }
    ;;
  *)
    posix_paths() { local p; while IFS= read -r p; do printf '%s\n' "$p"; done; }
    ;;
esac
