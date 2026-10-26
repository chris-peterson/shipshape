# Sourced by the suites that run a script with PATH set to a fixture dir, so
# only the tools a case names are reachable. A tool this machine doesn't have is
# left out, the way it would be missing from a real PATH.

wrap_tools() {  # $1 dir  $2.. tool names
  local dir="$1" t p; shift
  for t; do
    p=$(type -P "$t") || continue
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$p" > "$dir/$t"
    chmod +x "$dir/$t"
  done
}
