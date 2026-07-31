# <img src="favicon.svg" alt="shipshape" width="64" height="64" style="vertical-align: middle"> shipshape

Keep your Claude Code plugins up to date.

shipshape is a Claude Code plugin for maintaining your *other* Claude Code
plugins. It does three things: a `/plugin-maintenance` skill that reconciles your
installed plugins and reaps the clutter Claude Code leaves behind, a load-time
hook that turns on marketplace auto-update so plugins stay current on their own,
and a load-time hook that hands Claude your re-training instructions the first
session after Claude Code itself changes version.

## In action

Out-of-date tooling drifts silently and `uninstall` leaves clutter behind. One
command brings the whole plugin dir back to a known-good state:

<div class="cw-session" data-cw-session="session"></div>

## Install

```bash
claude plugin marketplace add chris-peterson/claude-marketplace
claude plugin install shipshape@chris-peterson
```

## The `/plugin-maintenance` skill

Run it from inside Claude Code whenever you want to tidy up:

```text
/plugin-maintenance
```

It reconciles **installed** plugins against the **desired** set you've declared
in `~/.claude/settings.json` (`enabledPlugins`), then:

1. **Inventory** — list what's installed (`claude plugin list`) and read your
   desired set.
2. **Update** — `claude plugin update` every plugin in both sets, in parallel.
3. **Reconcile** — uninstall user-scope extras, offer to install what's
   missing, and skip plugins it shouldn't remove (team-shared project-scope
   ones, and a plugin whose two marketplace rows share one on-disk install).
4. **Scan & prune** — find orphan and stale-version caches and orphan data
   dirs, auto-delete the safe ones, and ask before removing anything that may
   hold user state.

It lists **every enabled plugin** — each gets a row with its version and result,
so you can confirm each plugin's disposition at a glance rather than re-running
`claude plugin list`. Only caches are reported by exception (stale-version dirs
are routine noise).

Two runs, two outcomes — a reconcile with work to do, and a settled machine
where there's nothing left but to keep auto-update armed:

<div class="cw-session" data-cw-session="examples"></div>

### What it cleans that nothing else does

`claude plugin uninstall` removes a plugin but leaves its cache and **data**
directories behind. Claude Code maintains per-version `.in_use` leases and
sweeps dead ones, but it doesn't reap orphaned data dirs or stale versions left
by updates. shipshape closes that gap — and it respects live `.in_use` leases,
so it never prunes a version another running session is still using.

> [!TIP]
> The desired set is your own `enabledPlugins`. Curate that map and
> `/plugin-maintenance` becomes "make my machine match what I declared."

## Auto-update

Updating plugins by hand is the problem shipshape exists to remove. Once
installed, a `SessionStart` hook arms **marketplace auto-update**: it sets
`autoUpdate: true` for every known marketplace under
[`extraKnownMarketplaces`](https://code.claude.com/docs/en/discover-plugins) in
`~/.claude/settings.json` — the surface Claude Code reads at startup to refresh
marketplaces and update their plugins.

Settings are read before hooks run, so the change takes effect on the **next**
launch; from then on each marketplace keeps itself current. The write is
idempotent — it happens only when a marketplace is missing the flag, so a
settled setup is a silent no-op.

> [!NOTE]
> If your `~/.claude/settings.json` is generated or synced from another source,
> that process will overwrite this edit. Declare `extraKnownMarketplaces` in
> your source of truth instead.

## Version-change callbacks

Your AI artifacts (rules, skills, hooks, plugin manifests) are written against a
particular Claude Code. When Claude Code moves to a new version, some of what
they encode can go stale: a hook event's schema, a settings key, a frontmatter
field. Noticing that yourself means checking a version you have no reason to
look at.

A second `SessionStart` hook checks it for you. It compares `claude --version`
against the version it recorded last session, and when they differ it hands
Claude a document you wrote about what to do next:

```text
# shipshape: Claude Code 2.1.220 → 2.2.4

Claude Code changed version since the last session. Follow these instructions
now, before anything else:

Re-train my AI artifacts against this Claude Code version:
  1. /my-retrain-command
  2. /plugin-maintenance
```

### Writing the document

The document is created for you, so you never have to guess its name. Look in
your shipshape data dir after the first session:

```text
~/.claude/plugins/data/shipshape-<marketplace>/on-claude-code-version-change.md
```

It arrives holding one comment explaining itself, and **a document with nothing
but comments fires nothing**. Write plain instructions into it, naming the
commands you want run:

```markdown
Re-train my AI artifacts against this Claude Code version:
  1. /my-retrain-command
  2. /plugin-maintenance
```

Everything you write reaches Claude unaltered apart from HTML comments, which are
dropped (that's what keeps the template's own explanation from arriving as an
instruction, and it leaves you a place for notes to yourself). Handing Claude the
text *is* the mechanism: a hook cannot invoke a slash command itself, but
`SessionStart` output is context Claude acts on, so the commands your document
names are the commands that run. That also means the document can carry the
reasoning, not just a list. Say why a step matters and Claude has it at the point
of doing the work.

### What fires, and when

| Situation | What happens |
|---|---|
| First ever session | Records the version, creates the document, tells you where it is. Nothing fires. |
| Version unchanged | Silent. No output, no writes to the document. |
| Version changed, document still all comments | Silent. The new version is recorded so you don't get a stale delta later. |
| Version changed, document written | Emits the delta line and your document. |
| Same version again after that | Silent. One version change fires exactly once. |

Any difference in the version string counts, patch bumps included, so `2.1.220 →
2.1.221` fires just like `2.1 → 2.2`.

The version and your document both live in `${CLAUDE_PLUGIN_DATA}`, the
[directory Claude Code guarantees survives plugin
updates](https://code.claude.com/docs/en/plugins-reference#persistent-data-directory).
A version cache would not survive: an update moves shipshape to a new version
dir, and `/plugin-maintenance` prunes the old one.

> [!TIP]
> To see it fire without waiting for an upgrade, roll the recorded version back
> and start a session:
> `echo 0.0.0 > ~/.claude/plugins/data/shipshape-*/state/claude-code-version`
