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
