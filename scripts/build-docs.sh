#!/usr/bin/env bash
# Render docs/ artifacts that aren't hand-maintained. Used by `just docs` and
# the GitHub Pages deploy workflow so the two never drift.
#
# Renders the suite: block to docs/suite.json for the live session preview.
set -euo pipefail

cd "$(dirname "$0")/.."

python3 scripts/gen-suite-json.py
