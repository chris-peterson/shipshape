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

## Local docs preview

```bash
just docs
```

Runs `docsify serve docs --open`.

## License

MIT — see [LICENSE](LICENSE).
