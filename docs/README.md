# <img src="favicon.svg" alt="shipshape" width="64" height="64" style="vertical-align: middle"> shipshape

Keep your Claude Code plugins up to date.

shipshape is a Claude Code plugin for maintaining your *other* Claude Code
plugins. It does three things: a `/plugin-maintenance` skill that reconciles your
installed plugins and reaps the clutter Claude Code leaves behind, a `pin-plugin`
script that points one plugin at your local checkout while you work on it, and a
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
2. **Update** — refresh every marketplace once, then `claude plugin update` each
   plugin in both sets serially (parallel updates of one marketplace collide on
   its re-clone), skipping any plugin you've pinned.
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

## Pinning a plugin to a local checkout

You notice a bug in a plugin you maintain, but the session is loading it from a
read-only marketplace cache. `pin-plugin` points that one plugin at your working
copy instead:

The script ships inside the plugin, so its path carries the installed shipshape
version and moves on every update. Nothing puts it on `PATH` — name it once and
reuse it:

```bash
pin=~/.claude/plugins/cache/chris-peterson/shipshape/<version>/scripts/pin-plugin

bash "$pin" pin anchor ~/src/anchor    # then start the sessions that need it
bash "$pin" list
bash "$pin" unpin anchor
```

Claude Code resolves where each plugin loads from via its `installPath` in
`~/.claude/plugins/installed_plugins.json`; a pin repoints that at your checkout
and records the marketplace install it displaced, which `unpin` restores.

A pin refuses a checkout of a *different* plugin: the checkout loads under the
pinned plugin's install record, so pinning `anchor` at a `beacon` checkout would
put beacon's skills, commands, and hooks where anchor's belong.

> [!IMPORTANT]
> **This is a between-sessions operation, run from a shell.** Claude Code reads
> `installPath` once at startup, and `/reload-plugins` re-reads the plugin set
> without re-resolving it — so a pin cannot move the session that applies it.
> That's also why there's no slash command for it: an in-session entrypoint could
> only tell you to restart. Exit, pin, then start the sessions that need the
> checkout. Inside a session that *did* load the checkout, skill edits are live;
> other artifacts need `/reload-plugins`.

### Why this belongs in shipshape

A pin can't survive on its own. `claude plugin update` repoints `installPath` at
a fresh cache dir, and shipshape arms marketplace auto-update on every launch —
either one silently clobbers a hand-edited manifest. So a pin is a **declared
exception to the reconcile**, and `/plugin-maintenance` honors it: a pinned plugin
is skipped by update and prune (including the origin cache dir `unpin` restores
to), never uninstalled as an extra, and re-asserted if something moved it. It's
the `.in_use` lease idea extended from "hold this version" to "hold this plugin
at my path."

Pinning validates the checkout (it must have a readable
`.claude-plugin/plugin.json`) and refuses rather than half-applying: a bad path
writes neither the pins file nor the manifest. A plugin with install records
under several scopes is refused too, since which one to repoint isn't a guess
worth making.

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
