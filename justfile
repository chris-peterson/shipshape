# shipyard runs from its git ref, with no checkout and no install. CI is the
# writer for what lands; these recipes are for seeing the projection first.
shipyard := "uvx --from 'git+https://github.com/chris-peterson/shipyard@v2' shipyard"

# what this is, and every recipe there is
[private]
default:
    @echo ""
    @echo "  shipshape: a Claude Code plugin that keeps a user's harness current"
    @echo ""
    @echo "  New here?   just test               run every script suite"
    @echo "  Try it?     claude --plugin-dir .   mount this checkout as the plugin"
    @echo ""
    @just --list --unsorted --list-heading '' --list-prefix '    '
    @echo ""
    @echo "  Generated files are written by CI on push. Edit plugin.yml and the sources, never the output."
    @echo ""

# run the shell script test suite
[group('start here')]
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for t in scripts/tests/*.test.sh; do echo "== $t =="; bash "$t"; done

# preview the docsify docs site locally
[group('start here')]
docs:
    {{shipyard}} build-docs
    docsify serve docs --open

# project source into the generated artifacts (plugin.json, hooks.json, describe, docs)
[group('generated files')]
generate:
    {{shipyard}} generate

# regenerate the artifacts and list what the projection job would commit
[group('generated files')]
check-generated:
    {{shipyard}} generate
    git --no-pager diff --stat

# regenerate .claude-plugin/plugin.json from plugin.yml (the canonical descriptor)
[group('generated files')]
plugin-json:
    {{shipyard}} gen-plugin-json

# resync plugin.yml suite.describe from the skills/rules/hooks sources
[group('generated files')]
describe:
    {{shipyard}} gen-describe
