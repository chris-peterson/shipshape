#!/usr/bin/env bash
# jq for the skill's own reads. A Bash tool call doesn't source platform.sh, so
# a bare `jq` there misses the one fetch-jq.sh left in $CLAUDE_PLUGIN_DATA/bin
# on a machine with no system jq.
#
# Usage:  CLAUDE_PLUGIN_DATA=<dir> jq.sh <jq args...>
set -euo pipefail
. "${BASH_SOURCE[0]%/*}/platform.sh"
jq "$@"
