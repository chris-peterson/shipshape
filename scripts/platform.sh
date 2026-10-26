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

# For a hook that needs jq: fetches one where the system has none, and sources
# this file again so the fetched jq is on PATH and wrapped like a system one. On
# failure, jq_unavailable holds fetch-jq.sh's reason.
ensure_jq() {
  type -P jq >/dev/null && return 0
  local err
  if ! err="$("$BASH" "${BASH_SOURCE[0]%/*}/fetch-jq.sh" 2>&1 >/dev/null)"; then
    jq_unavailable="${err##*$'\n'}"
    jq_unavailable="${jq_unavailable#fetch-jq: }"
    return 1
  fi
  . "${BASH_SOURCE[0]}"
}

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
