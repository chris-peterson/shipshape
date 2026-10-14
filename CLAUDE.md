Agent instructions live in [AGENTS.md](./AGENTS.md).

@AGENTS.md

## Claude Code

- The auto-update `SessionStart` hook prints nothing on its own. To watch it
  fire, launch with `claude --debug` and look for the `Hooks:
  SessionStart:startup [... enforce-autoupdate.sh] (plugin shipshape@<marketplace>)
  finished with status <code> (<ms>)` line, logged on every session start. It is
  idempotent: once every marketplace is auto-updating, it exits 0 and changes
  nothing.
- Mount the working tree as a plugin to exercise the skill: `claude --plugin-dir .`
  With the Bash sandbox on, that session's shell can't write into the checkout
  (Claude Code runs a `--plugin-dir` folder's code outside the sandbox), so
  `just generate`, `just docs`, and `git commit` fail there. Run them from a
  session that doesn't mount the tree; Edit and Write still work.
