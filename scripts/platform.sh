# Sourced by every script that reads jq output or compares paths, so git-bash on
# Windows sees the same bytes macOS and Linux do. Bash builtins only: a caller
# may run it with an empty PATH to exercise its own missing-jq branch.

# A jq that fetch-jq.sh downloaded, used only where the system has none.
# covers: JSON-06
if ! type -P jq >/dev/null && [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
  jq_dir="$CLAUDE_PLUGIN_DATA/bin"
  # PATH splits on ':', so a C:\... data dir goes on it in POSIX form.
  case "${OSTYPE:-}:$jq_dir" in
    msys*:[A-Za-z]:*|cygwin*:[A-Za-z]:*) jq_dir="$(cygpath -u "$jq_dir")" ;;
  esac
  if [ -x "$jq_dir/jq" ] || [ -x "$jq_dir/jq.exe" ]; then PATH="$jq_dir:$PATH"; fi
  unset jq_dir
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
