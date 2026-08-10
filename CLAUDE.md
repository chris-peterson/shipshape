Agent instructions live in [AGENTS.md](./AGENTS.md).

@AGENTS.md

## Claude Code

- The `SessionStart` hook prints nothing on its own. To watch it fire, launch
  with `claude --debug` and look for the `[DEBUG] Hook SessionStart` line. It is
  idempotent — once every marketplace is auto-updating, there's no line to see.
- Mount the working tree as a plugin to exercise the skill: `claude --plugin-dir .`
