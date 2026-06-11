# shipshape

📖 **[Read the docs →](https://chris-peterson.github.io/shipshape/)**

Keep all your AI plugins up to date. shipshape is a Claude Code plugin that
maintains your *other* Claude Code plugins — a `/plugin-maintenance` skill that
reconciles and prunes, plus a `SessionStart` hook that enforces marketplace
auto-update. See the docs for usage.

## Repo layout

```text
.claude-plugin/plugin.json            plugin manifest
hooks/hooks.json                      SessionStart hook registration
hooks/enforce-autoupdate.sh           arms marketplace auto-update at load
skills/plugin-maintenance/SKILL.md    the maintenance skill
docs/                                 docsify site (deployed to Pages)
```

## Testing the hook

The `SessionStart` hook produces no terminal output on its own. To see it
fire, launch with `--debug` and look for its `[DEBUG] Hook SessionStart`
line:

```bash
claude --debug
```

```text
2026-06-11T21:43:35.505Z [DEBUG] Hook SessionStart:startup (SessionStart) success:
# shipshape: marketplace auto-update enabled

Set autoUpdate=true in ~/.claude/settings.json for:
  - chris-peterson
  - claude-plugins-official
```

The hook is idempotent — once every marketplace is auto-updating, it exits as
a no-op and the line above won't appear.

## Local docs preview

```bash
just docs
```

Runs `docsify serve docs --open`.

## License

MIT — see [LICENSE](LICENSE).
