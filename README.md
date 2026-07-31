# shipshape

📖 **[Read the docs →](https://chris-peterson.github.io/shipshape/)**

Keep your Claude Code plugins up to date. shipshape is a Claude Code plugin that
maintains your *other* Claude Code plugins — a `/plugin-maintenance` skill that
reconciles and prunes, plus `SessionStart` hooks that enforce marketplace
auto-update and surface your re-training instructions when Claude Code changes
version. See the docs for usage.

## Source of record

`plugin.yml` and `hooks/hooks.yml` are canonical. `scripts/shipyard` projects
them into the plugin manifest, the hook registration, and the docs site, so edit
those two rather than their output and run `just generate`. `just check` prints
the pending projection without writing it, which is how you see whether a
committed artifact has drifted from its source.

## Testing the hooks

The `SessionStart` hooks produce no terminal output on their own. To see one
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

Takes effect on the next Claude Code launch.
```

The hook is idempotent — once every marketplace is auto-updating, it exits as
a no-op and the line above won't appear.

`claude-code-version-callbacks.sh` is quiet in the same way: it prints only on
its first run, or when the recorded version differs from `claude --version` and
the callback document has been written. To force it during development, roll the
recorded version back and start a session:

```bash
echo 0.0.0 > "$(ls -d ~/.claude/plugins/data/shipshape-*)/state/claude-code-version"
```

Both hooks are covered by hermetic tests that redirect `$HOME` and
`$CLAUDE_PLUGIN_DATA` into a fixture tree, so a test run never touches your real
settings or plugin data:

```bash
just test
```

## Local docs preview

```bash
just docs
```

Runs `docsify serve docs --open`.

## License

MIT — see [LICENSE](LICENSE).
