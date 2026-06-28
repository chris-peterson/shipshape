# <img src="favicon.svg" alt="shipshape" width="64" height="64" style="vertical-align: middle"> shipshape

Keep your Claude Code plugins up to date.

shipshape is a Claude Code plugin for maintaining your *other* Claude Code
plugins. It does two things: a `/plugin-maintenance` skill that reconciles your
installed plugins and reaps the clutter Claude Code leaves behind, and a
load-time hook that turns on marketplace auto-update so plugins stay current on
their own.

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

It reports **by exception** — only plugins that changed get a row; everything
already current collapses into a one-line count.

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
