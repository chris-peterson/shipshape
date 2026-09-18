#!/usr/bin/env bash
# Answer which repos a version-change guide should analyze in depth, and record
# the user's decisions so the question is asked once rather than every upgrade.
#
# A plugin the user MAINTAINS is theirs to patch when a Claude Code release
# invalidates a hook schema, a settings key, or a frontmatter field. A plugin
# they merely USE is its own maintainer's errand. Only the first set is worth an
# in-depth pass, and nothing on disk distinguishes them: both are installed, and
# both have a source repo. So the set is declared, once, and this script keeps
# the declaration reconciled against what is actually installed.
#
# The declaration lives at $CLAUDE_PLUGIN_DATA/version-scan-targets.json:
#
#   { "version": 1,
#     "targets": {
#       "anchor@your-custom-marketplace": { "action": "issue", "src": "/…/anchor" },
#       "frontend-design@claude-plugins-official": { "action": "skip" },
#       "my-rules": { "action": "edit", "src": "/…/my-rules" } } }
#
# A key holding `@` is an installed plugin, matched against the install
# manifest's own keys so drift is exact. A bare key is a repo the user added by
# hand — their plugin build tool, their rules repo — which reads the same CLI
# and the same schemas but ships as no plugin, so no manifest names it. Bare
# keys are never reported as gone.
#
# `action` is what happens to a finding in that target, not merely whether to
# look. A repo the user owns outright is fixed in place; one they file against
# gets an issue; one they only want to hear about gets a line in the report.
# That distinction has to live here rather than in the user's prose, because the
# run has to know it per target:
#
#   skip       not examined, and not reported
#   summarize  examined; findings summarized in the report (the default)
#   issue      examined; findings offered for filing
#   edit       examined; fixes landed as direct edits for the user to review
#
# Usage:  version-scan-targets.sh --drift
#         version-scan-targets.sh --set <key> <action> [<src>]
#         version-scan-targets.sh --forget <key>
#
# --drift prints the reconciliation as JSON and changes nothing:
#
#   { "new": [{key,source}…],              installed, no decision recorded;
#                                          `source` is the repo the plugin ships
#                                          from, which is what the question is
#                                          grouped by
#     "gone": [<key>…],                     decided, no longer installed
#     "unreadable": [{key,src}…],           examined, src is not a directory
#     "targets": [{key,action,src}…],       the examined set, ready to use
#     "skip": [<key>…],                     decided `skip`
#     "synced": {skills,plugins,unreadable}, the account-sync lane (see below)
#     "settled": <true|false> }             nothing to ask about
#
# `unreadable` is its own bucket rather than folded into `targets` or dropped: a
# recorded checkout that has moved is a question for the user, and examining
# nothing while reporting a pass is the one outcome that must not happen. It
# keeps `settled` false until the user answers.
#
# `synced` is the same principle one lane over. Skills and plugins enabled on
# the user's claude.ai account are written by Claude Code into
# ~/.claude/skills/synced/<bucket>/ and ~/.claude/plugins/synced/<bucket>/, and
# they carry no install-manifest row — so the manifest alone reads them as
# absent rather than as unexamined, and a pass over the manifest reports full
# coverage while never having seen them. Only what is observable goes in the
# bucket: a synced skills manifest names its skills, so those are named, while a
# synced plugin bucket's rows carry fields this script does not read, so those
# are counted. A bucket file that exists but does not parse is listed in
# `synced.unreadable`, never counted as empty.
#
# Exit:   0 = answered
#         1 = jq missing, no install manifest, or CLAUDE_PLUGIN_DATA unset
#         2 = a mode was called with arguments it cannot honor
#
# Env:    CLAUDE_PLUGIN_DATA  where the declaration is written (required)
#         CLAUDE_PLUGINS_DIR  override ~/.claude/plugins (tests)
#         CLAUDE_SKILLS_DIR   override ~/.claude/skills (tests)

# covers: VERSION-27, VERSION-28, VERSION-34, VERSION-35, VERSION-42, VERSION-44,
#         VERSION-45
set -euo pipefail

plugins="${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}"
skills="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
manifest="$plugins/installed_plugins.json"
data="${CLAUDE_PLUGIN_DATA:-}"

if ! command -v jq >/dev/null 2>&1; then
  echo "version-scan-targets: jq not on PATH; cannot read the install manifest" >&2
  exit 1
fi
if [ -z "$data" ]; then
  echo "version-scan-targets: CLAUDE_PLUGIN_DATA is unset; nowhere to read or write the declaration" >&2
  exit 1
fi
if [ ! -f "$manifest" ]; then
  echo "version-scan-targets: no install manifest at $manifest" >&2
  exit 1
fi

# Resolve a --plugin-dir session's `<plugin>-inline` lane back to the installed
# plugin's, so the declaration a prior run recorded is the one reconciled here.
if ! data="$("${BASH:-bash}" "$(dirname "${BASH_SOURCE[0]}")/plugin-data-dir.sh" "$data")"; then
  exit 1
fi

decl="$data/version-scan-targets.json"

# An unreadable declaration is not an empty one. Rewriting it from scratch would
# discard every decision the user has already made, so stop and say so.
read_decl() {
  if [ ! -f "$decl" ]; then
    echo '{"version":1,"targets":{}}'
    return 0
  fi
  if ! jq -e 'type == "object" and (.targets | type == "object")' "$decl" >/dev/null 2>&1; then
    echo "version-scan-targets: $decl is not readable as a declaration; leaving it untouched" >&2
    return 1
  fi
  cat "$decl"
}

write_decl() {
  mkdir -p "$data"
  tmp=$(mktemp "$decl.XXXXXX")
  cat > "$tmp"
  mv "$tmp" "$decl"
}

# Each outstanding plugin's source repo, as `<key>\t<url>`.
#
# The source is what predicts the user's answer, and the marketplace is not: a
# shared marketplace carries plugins from many owners, and one owner's plugins
# are spread across several marketplaces. So the question is grouped by source,
# which means resolving it here rather than leaving the skill to re-derive it.
#
# A marketplace's installLocation is a directory when its source is a git repo
# and a file when it is a plain marketplace.json URL; both have to be read.
plugin_sources() {
  registry="$plugins/known_marketplaces.json"
  [ -f "$registry" ] || return 0
  jq -r 'to_entries[] | [.key, (.value.installLocation // "")] | @tsv' "$registry" \
  | while IFS=$'\t' read -r name loc; do
      [ -n "$loc" ] || continue
      mf="$loc"
      [ -d "$loc" ] && mf="$loc/.claude-plugin/marketplace.json"
      [ -f "$mf" ] || continue
      # One marketplace that does not parse costs its plugins their source, not
      # the whole reconciliation: they still reach `new` from the install
      # manifest, ungrouped, and the gap is named rather than dropped with the
      # stderr. The `if` also keeps the loop's exit status off the last jq,
      # which pipefail would otherwise carry into the caller's assignment.
      if ! jq -r --arg m "$name" '
        (.plugins // [])[]
        | [(.name + "@" + $m),
           (.source | if type == "string" then . else (.url // .repo // "") end)]
        | @tsv' "$mf" 2>/dev/null
      then
        echo "version-scan-targets: $mf is not readable; $name's plugins are offered without a source" >&2
      fi
    done
}

# Where an outstanding plugin's source repo is checked out, as
# `<key>\t<path>` — one line per candidate, none when nothing matches.
#
# Claude Code records every directory a session has run in under `.projects` in
# ~/.claude.json, which is an index of the user's checkouts for the price of one
# file read. Candidates come from there by repo basename, then each one's
# `origin` decides it: a basename can collide across owners (three different
# `ai-tools` repos on one machine), and the remote is what tells them apart.
#
# Asking the user for a source root is the fallback, not the first move — they
# should be confirming a resolved list, not typing a path shipshape could have
# found. A repo they have never opened a session in is simply absent, which is
# what makes the fallback necessary rather than optional.
resolve_sources() {
  index="$HOME/.claude.json"
  [ -f "$index" ] || return 0
  projects=$(jq -r '(.projects // {}) | keys[]' "$index" 2>/dev/null) || return 0

  norm() {
    printf '%s' "$1" \
      | sed -e 's#^git@#https://#' -e 's#^\(https://[^/:]*\):#\1/#' \
            -e 's#\.git$##' -e 's#/$##'
  }

  while IFS=$'\t' read -r key source; do
    [ -n "$source" ] || continue
    case "$source" in ./*|'') continue ;; esac
    base=${source##*/}; base=${base%.git}
    want=$(norm "$source")
    printf '%s\n' "$projects" | while IFS= read -r dir; do
      [ "${dir##*/}" = "$base" ] || continue
      url=$(git -C "$dir" remote get-url origin 2>/dev/null) || continue
      [ "$(norm "$url")" = "$want" ] || continue
      printf '%s\t%s\n' "$key" "$dir"
    done
  done
}

# What the account-sync lane holds, one observation per line: `skill\t<name>`,
# `rows\t<count>`, or `bad\t<path>`.
#
# A synced skills manifest names its skills, so they are named. A synced plugin
# bucket's rows carry fields this script has never read, so they are counted and
# not named — counting needs only `rows`, which is on the file itself. A bucket
# that exists and does not parse is `bad`, because reading it as empty is how a
# lane nobody examined comes to look like a lane with nothing in it.
synced_rows() {
  for m in "$skills"/synced/*/manifest.json; do
    [ -f "$m" ] || continue
    if jq -e '(.skills // []) | type == "array"' "$m" >/dev/null 2>&1; then
      jq -r '(.skills // [])[] | "skill\t" + (.name // .skillId // empty)' "$m"
    else
      printf 'bad\t%s\n' "$m"
    fi
  done
  for b in "$plugins"/synced/*/.marketplaces.json; do
    [ -f "$b" ] || continue
    if n=$(jq '(.rows // []) | length' "$b" 2>/dev/null); then
      printf 'rows\t%s\n' "$n"
    else
      printf 'bad\t%s\n' "$b"
    fi
  done
}

synced_lane() {
  synced_rows \
    | jq -R 'split("\t") | {kind: .[0], value: (.[1] // "")}' \
    | jq -sc '
        {skills: [.[] | select(.kind == "skill") | .value | select(. != "")],
         plugins: ([.[] | select(.kind == "rows") | (.value | tonumber)] | add // 0),
         unreadable: [.[] | select(.kind == "bad") | .value]}'
}

case "${1:---drift}" in
  --resolve)
    installed=$(jq -c '(.plugins // {}) | keys' "$manifest")
    decl_json=$(read_decl) || exit 1
    sources=$(plugin_sources | jq -R 'split("\t") | {key: .[0], source: (.[1] // "")}' | jq -sc 'INDEX(.key) | map_values(.source)')
    outstanding=$(printf '%s' "$decl_json" | jq -r --argjson installed "$installed" --argjson sources "$sources" '
      (($installed - (.targets | keys))[]) as $k | [$k, ($sources[$k] // "")] | @tsv')
    printf '%s\n' "$outstanding" | resolve_sources \
      | jq -R 'split("\t") | {key: .[0], path: .[1]}' \
      | jq -sc 'group_by(.key) | map({key: .[0].key, paths: [.[].path] | unique})'
    ;;

  --drift)
    installed=$(jq -c '(.plugins // {}) | keys' "$manifest")
    decl_json=$(read_decl) || exit 1
    sources=$(plugin_sources | jq -R 'split("\t") | {key: .[0], source: (.[1] // "")}' | jq -sc 'INDEX(.key) | map_values(.source)')

    base=$(printf '%s' "$decl_json" | jq --argjson installed "$installed" --argjson sources "$sources" '
      .targets as $t
      | [($installed - ($t | keys))[] | {key: ., source: ($sources[.] // "")}] as $new
      | [$t | to_entries[] | select(.key | contains("@")) | .key] as $plugin_keys
      | [$t | to_entries[]
          | select(.value.action != "skip")
          | {key: .key, action: .value.action, src: (.value.src // "")}] as $examined
      | [$t | to_entries[] | select(.value.action == "skip") | .key] as $skip
      | {new: $new, gone: ($plugin_keys - $installed), targets: $examined,
         skip: $skip}
    ')

    # Whether a recorded src is still a directory is the one fact jq cannot
    # answer, so bash answers exactly that — the set of readable paths — and jq
    # partitions the rows against it. The filter is an `if` rather than a `&&`
    # because a loop body ending in a test leaves that test as the loop's exit
    # status, which pipefail then carries into this assignment: a declaration
    # whose last row has a moved checkout would take the reconciliation down
    # in silence, which is what the unreadable bucket exists to prevent.
    readable=$(printf '%s' "$base" \
      | jq -r '.targets[].src | select(. != "")' \
      | while IFS= read -r s; do if [ -d "$s" ]; then printf '%s\n' "$s"; fi; done \
      | jq -R . | jq -sc .)

    printf '%s' "$base" | jq --argjson readable "$readable" --argjson synced "$(synced_lane)" '
      ($readable | map({(.): true}) | add // {}) as $ok
      | .targets as $rows
      | .targets = [$rows[] | select($ok[.src])]
      | .unreadable = [$rows[] | select($ok[.src] | not) | {key, src}]
      | .synced = $synced
      | .settled = ((.new | length) == 0 and (.gone | length) == 0
                    and (.unreadable | length) == 0)
    '
    ;;

  --set)
    key="${2:-}"; action="${3:-}"; src="${4:-}"
    if [ -z "$key" ] || [ -z "$action" ]; then
      echo "version-scan-targets: --set needs <key> and skip|summarize|issue|edit" >&2
      exit 2
    fi
    case "$action" in
      summarize|issue|edit)
        if [ -z "$src" ]; then
          echo "version-scan-targets: --set $key $action needs a source path" >&2
          exit 2
        fi
        if [ ! -d "$src" ]; then
          echo "version-scan-targets: $src is not a directory; $key not recorded" >&2
          exit 2
        fi
        src=$(cd "$src" && pwd)
        entry=$(jq -n --arg a "$action" --arg s "$src" '{action:$a, src:$s}')
        ;;
      skip)
        if [ -n "$src" ]; then
          echo "version-scan-targets: --set $key skip takes no source path; a target nobody examines has no use for one" >&2
          exit 2
        fi
        entry='{"action":"skip"}'
        ;;
      *)
        echo "version-scan-targets: unknown action '$action'; use skip, summarize, issue or edit" >&2
        exit 2
        ;;
    esac
    read_decl | jq --arg k "$key" --argjson e "$entry" '.targets[$k] = $e' | write_decl
    echo "version-scan-targets: $key -> $action${src:+ ($src)}"
    ;;

  --forget)
    key="${2:-}"
    if [ -z "$key" ]; then
      echo "version-scan-targets: --forget needs <key>" >&2
      exit 2
    fi
    read_decl | jq --arg k "$key" 'del(.targets[$k])' | write_decl
    echo "version-scan-targets: forgot $key"
    ;;

  *)
    echo "version-scan-targets: unknown mode '$1'" >&2
    exit 2
    ;;
esac
