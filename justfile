default:
    @just --list

# run the shell script test suite
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for t in scripts/tests/*.test.sh; do echo "== $t =="; bash "$t"; done

# preview the docsify docs site locally
docs:
    bash scripts/build-docs.sh
    docsify serve docs --open

# regenerate .claude-plugin/plugin.json from plugin.yml (the canonical descriptor)
plugin-json:
    python3 scripts/gen-plugin-json.py

# verify plugin.json is in sync with plugin.yml (used by CI and the pre-commit hook)
plugin-json-check:
    python3 scripts/gen-plugin-json.py --check

# install the git pre-commit hook that keeps plugin.json in sync with plugin.yml
install-hooks:
    cp scripts/hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    @echo "installed .git/hooks/pre-commit"
