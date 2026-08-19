# shipshape

📖 **[Read the docs →](https://chris-peterson.github.io/shipshape/)**

Know what's changing in your Claude Code harness, and keep it current. shipshape
covers Claude Code itself (a `SessionStart` hook announces a version change, and
`/claude-code-version` walks what's new and runs the instructions you wrote for an
upgrade) and your *other* plugins (`/plugin-maintenance` reconciles and prunes
them, and a second hook arms marketplace auto-update). See the docs for usage.

Repo layout, the `just` targets, and the conventions this codebase holds itself
to are in [AGENTS.md](./AGENTS.md) — the same file the agents read. Requirements
are in [SPEC.md](./SPEC.md), their coverage in [STATUS.md](./STATUS.md).

## License

MIT — see [LICENSE](LICENSE).
