#!/usr/bin/env bash
# Print a prefilled "new issue" link for each drafted finding, so a run can hand
# findings to the forge without anchor and without a forge CLI.
#
# Where `/anchor:issue` isn't in the session, the run writes each finding for an
# `issue` target to its own markdown file and opens the folder for the user to
# edit or delete. What survives becomes a link that opens the forge's new-issue
# form already filled in. The user files it there, so shipshape itself writes
# nothing to a forge.
#
# A draft's first non-blank line is its title, as a `# ` heading, and the rest
# is its body. The forge and the repo come from the checkout's `origin` remote:
# a host naming github is GitHub (`issues/new?title=&body=`), and a host naming
# gitlab is GitLab (`-/issues/new?issue[title]=&issue[description]=`).
#
#   <draft>|full|<url>         title and body prefilled
#   <draft>|title-only|<url>   the body made the link too long; paste it from
#                              <draft>
#   <draft>|no-title|-         the draft has no `# ` title line
#
# GitHub refuses a new-issue URL somewhere past 6,500 characters (500, then
# 414), so a link longer than SHIPSHAPE_LINK_MAX prefills the title alone rather
# than opening a page that fails.
#
# Usage:  issue-draft-link.sh <checkout> <draft.md>...
# Exit:   0 = a line per draft
#         1 = usage, jq missing, a draft unreadable, or the checkout has no
#             origin remote
#         2 = origin's host is neither GitHub nor GitLab, so there is no form
#             to link to
#
# Env:    SHIPSHAPE_LINK_MAX   longest link to emit in full (default 6000)

# covers: VERSION-44
set -euo pipefail
. "${BASH_SOURCE[0]%/*}/platform.sh"

die() { echo "issue-draft-link: $*" >&2; exit "${2:-1}"; }

[ $# -ge 2 ] || die "usage: issue-draft-link.sh <checkout> <draft.md>..."
command -v jq >/dev/null 2>&1 || die "jq not on PATH; cannot encode the link"

checkout=$1; shift
max=${SHIPSHAPE_LINK_MAX:-6000}
case "$max" in ''|*[!0-9]*) die "SHIPSHAPE_LINK_MAX is not a number: $max" ;; esac

remote=$(git -C "$checkout" remote get-url origin 2>/dev/null) \
  || die "no origin remote in $checkout"
remote=${remote%$'\r'}

# git@host:path, ssh://[user@]host[:port]/path, http(s)://[user@]host/path
case "$remote" in
  *://*) rest=${remote#*://}; rest=${rest#*@}; host=${rest%%/*}; path=${rest#*/}; host=${host%%:*} ;;
  *@*:*) rest=${remote#*@}; host=${rest%%:*}; path=${rest#*:} ;;
  *) die "origin is not a URL shipshape can read: $remote" ;;
esac
path=${path%/}; path=${path%.git}
[ -n "$host" ] && [ -n "$path" ] && [ "$path" != "$rest" ] \
  || die "origin is not a URL shipshape can read: $remote"

lower=$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')
case "$lower" in
  *github*) form="https://$host/$path/issues/new"; t_key=title; b_key=body ;;
  *gitlab*) form="https://$host/$path/-/issues/new"; t_key='issue%5Btitle%5D'; b_key='issue%5Bdescription%5D' ;;
  *) die "origin's host $host is neither GitHub nor GitLab; no new-issue form to link" 2 ;;
esac

for draft in "$@"; do
  [ -r "$draft" ] || die "cannot read $draft"
  # Title: the first non-blank line, which must be a `# ` heading. Body: the
  # lines after it, leading blanks dropped. CRs go, since a Windows editor
  # writes them.
  title='' body='' seen=0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    if [ $seen -eq 0 ]; then
      [ -z "${line//[[:space:]]/}" ] && continue
      seen=1
      case "$line" in '# '*) title=${line#'# '} ;; *) break ;; esac
      continue
    fi
    if [ -z "$body" ] && [ -z "${line//[[:space:]]/}" ]; then continue; fi
    body+="$line"$'\n'
  done < "$draft"

  if [ -z "${title//[[:space:]]/}" ]; then
    printf '%s|no-title|-\n' "$draft"
    continue
  fi

  full=$(jq -rn --arg f "$form" --arg tk "$t_key" --arg bk "$b_key" \
    --arg t "$title" --arg b "${body%$'\n'}" \
    '"\($f)?\($tk)=\($t | @uri)" + (if $b == "" then "" else "&\($bk)=\($b | @uri)" end)')
  if [ "${#full}" -le "$max" ]; then
    printf '%s|full|%s\n' "$draft" "$full"
  else
    short=$(jq -rn --arg f "$form" --arg tk "$t_key" --arg t "$title" '"\($f)?\($tk)=\($t | @uri)"')
    printf '%s|title-only|%s\n' "$draft" "$short"
  fi
done
