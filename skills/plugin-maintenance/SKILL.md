---
name: plugin-maintenance
description: Reconcile installed Claude Code plugins against the desired set, update them, and prune stale caches/data. Triggers on 'sync plugins', 'update my plugins'.
disable-model-invocation: true
---

# Plugin Maintenance

Reconcile installed Claude Code plugins against the **desired set** declared in `~/.claude/settings.json` (`enabledPlugins`), then update what stays, install what's missing, uninstall what doesn't belong, and prune stale caches and data dirs.

The `claude plugin uninstall` command does **not** prune `~/.claude/plugins/cache/` or `~/.claude/plugins/data/`. This skill does, but only with confirmation — data dirs may hold user state worth preserving.

## Source of truth

- **Desired plugins:** `~/.claude/settings.json` → `enabledPlugins` (a map of `<plugin>@<marketplace>` → bool). This is the set you've declared should be enabled; the disk state may have drifted from it.
- **Installed plugins:** `claude plugin list` output. Format: each entry has `<plugin>@<marketplace>`, `Version`, `Scope` (user/project/local), `Status` (enabled/disabled).

## Guardrail: project-scope team-shared plugins

Plugins with **Scope: project** are checked into a repo's `.claude/settings.json` and shared with the team. **Do not uninstall them** — `claude plugin uninstall` will fail with a clear error. Report them as "skipped (team-shared)" and move on. User-scope plugins are personal and safe to reconcile.

## Guardrail: a plugin shared by two marketplaces

The same plugin can be published to more than one marketplace — a public marketplace and a separate mirror, say. When both are registered (common while migrating from one to the other), `claude plugin list` shows two rows for that plugin — `foo@marketplace-a` and `foo@marketplace-b` — but `installed_plugins.json` records the install **once**, under whichever marketplace it was installed from. The other row points at that same on-disk install.

`claude plugin uninstall foo@marketplace-a` then removes the plugin's only install record, uninstalling `foo` entirely — including the copy that was enabled and in use — and returns a success message regardless, so the command's exit can't confirm the intended "remove just this marketplace copy" effect.

**The tell:** a `<plugin>@<marketplace>` row in `claude plugin list` that has no matching key in `installed_plugins.json`, while another row for the same plugin name does. That row shares the single on-disk install — uninstalling it deletes the shared copy.

So gate every extra uninstall on the install manifest, not on `claude plugin list` plus the desired set alone (Step 3). A plugin with genuinely independent install records per marketplace — a key present in the manifest for each marketplace — is reconciled as before.

## Flow

```mermaid
%%{ init: { 'look': 'handDrawn' } }%%
flowchart TD
    Start(["/plugin-maintenance"]) --> List["claude plugin list"]
    List --> Read["Read enabledPlugins from settings.json"]
    Read --> Diff["Diff installed vs desired"]
    Diff --> Update["Update kept plugins (parallel)"]
    Update --> Reconcile{Reconcile diffs}
    Reconcile -->|extras| Uninstall["Uninstall extras (skip project-scope + shared installs)"]
    Reconcile -->|missing| Install["Offer to install missing"]
    Uninstall --> Scan
    Install --> Scan
    Scan["Scan caches + data dirs"] --> Report["Report orphans + stale versions"]
    Report --> Confirm{Delete?}
    Confirm -->|empty caches| Auto["Delete without prompting"]
    Confirm -->|non-empty data| Ask["Ask before each non-empty data dir"]
    Auto --> Reload["/reload-plugins"]
    Ask --> Reload
    Reload --> Done([Done])
```

## Output model: two tables + the native task list

Don't narrate the run as a scroll of per-plugin lines. Use three surfaces: a **plan table** up front, the **native task list** for progress, and a **refreshed table** at the end.

Know what the terminal can and can't do, so this isn't cargo-culted: message text is **append-only**. A printed line can't be redrawn — there's no cursor control in rendered markdown — so a hand-typed progress bar or `- [ ]` checklist just stacks copies and scrolls *worse*. The **only** surface Claude can mutate after emitting it is the harness task list (`TaskCreate` / `TaskUpdate`), which re-renders in place as items flip to `completed`. That's what carries progress; the tables are two separate renders (a plan, then its refresh), not one mutated in place.

**1. Plan table** — render after Step 1, before any update/install/uninstall runs. One row per plugin you'll act on, ordered by marketplace then plugin. The Status column carries the *planned* action so the user sees the whole scope before anything changes:

```text
| Marketplace    | Plugin   | Version | Status            |
|----------------|----------|---------|-------------------|
| chris-peterson | beacon   | 1.1.0   | queued: update    |
| chris-peterson | moor     | 0.6.1   | queued: update    |
| official       | gitlab   | 1.2.0   | skip: team-shared |
| chris-peterson | newthing | —       | queued: install?  |
```

**2. Progress** — during Steps 2-3, track work on the **native task list** via `TaskCreate` / `TaskUpdate`. Build the list from the *actual* work the Step-1 diff and Step-4 scan turn up — **one task per non-empty action group**, not a fixed pipeline of phases:

- `Update kept plugins (N)` — whenever the kept set is non-empty. This is the one group you can't pre-filter: you don't know which plugins have an update until you run the pass, so it's a single task, not one per plugin.
- `Uninstall N extras` — only if there are extras to remove.
- `Install N missing` — only if the user confirmed missing installs.
- `Prune N stale/orphan caches` — only once the scan finds delete-eligible dirs (no live lease).

Don't create a task for an empty group — an instantly-completed `Reconcile: nothing to do` task is exactly the wall-of-no-ops this redesign removes. If that leaves **≤1 action group** — the common all-current run — skip the task list entirely; the plan and refreshed tables already carry it (the task tool's own guidance is to skip it for trivial single-step work). Mark each task `in_progress` on launch and `completed` on return. Because Step 2's updates run in parallel and return in one batch, ticks flip together rather than trickle — the list is a live status surface, not an animation.

**3. Refreshed table** — render after Steps 2-3 finish. The *same* table, now with terminal statuses and version transitions. This is the authoritative result:

```text
| Marketplace    | Plugin | Previous Version | Current Version | Status                |
|----------------|--------|------------------|-----------------|-----------------------|
| chris-peterson | beacon | 1.1.0            | 1.3.0           | updated               |
| chris-peterson | moor   | 0.6.1            | 0.6.1           | current               |
| official       | gitlab | 1.2.0            | 1.2.0           | skipped (team-shared) |
```

For a large desired set, collapse the rows that ended up `current` with no change into a single trailing count and keep the rows that actually changed (`updated` / `uninstalled` / `install? (missing)` / `skipped (...)`) — but keep the table shape so it reads as the plan, refreshed:

```text
17 other plugins already current.
```

If nothing changed at all — no updates, no extras, no missing — skip both tables and say so in one line: `All 20 desired plugins installed and current; nothing to reconcile.`

## Step 1: Inventory

Run in parallel:

```bash
claude plugin list
```

```bash
cat ~/.claude/settings.json | jq '.enabledPlugins'
```

Build two sets of `<plugin>@<marketplace>` keys: **installed** (with scope) and **desired**. Once you've diffed them (Step 3's classification), render the **plan table** from the "Output model" section — this is the up-front table the user sees before anything changes.

Also read the install manifest — Step 3 gates uninstalls on it (see "a plugin shared by two marketplaces"):

```bash
jq '.plugins | keys' ~/.claude/plugins/installed_plugins.json
```

The manifest keys by the same `<plugin>@<marketplace>` form. A `claude plugin list` row whose key is absent here shares another marketplace's single on-disk install.

While you have the marketplace state, note **auto-update** coverage for the final report — a marketplace is auto-updating when its `extraKnownMarketplaces.<name>.autoUpdate` is `true` in `~/.claude/settings.json`:

```bash
jq '.extraKnownMarketplaces | to_entries | map({(.key): (.value.autoUpdate // false)}) | add' ~/.claude/settings.json
```

shipshape's `SessionStart` hook enforces this — it arms any marketplace missing the flag, effective next launch — so the skill only **reports** status here; it doesn't write. Surface any marketplace still showing `false` so the user knows the hook will pick it up.

## Step 2: Update kept plugins

For every plugin that appears in **both** sets, run `claude plugin update` in parallel:

```bash
claude plugin update <plugin>@<marketplace>
```

While the batch runs, track it on the **native task list** (see "Output model") — mark the `Update kept plugins` task `in_progress` on launch, `completed` when the batch returns. Don't emit a line per plugin; the results land in the refreshed table (Step 3).

## Step 3: Reconcile differences

- **Extras** (installed, not desired):
  - **Shared on-disk install** (the extra's `<plugin>@<marketplace>` key is absent from `installed_plugins.json`, but another row for the same plugin name is present) → **do not uninstall.** Removing this marketplace key deletes the plugin's only install record, taking the enabled copy with it. Surface it as a warning with the evidence — the row is enabled in `claude plugin list` yet absent from the manifest — and let the user resolve it deliberately: re-point `enabledPlugins` to the desired marketplace, or uninstall and reinstall from that marketplace. Report as "skipped (shared install)".
  - **User-scope** → `claude plugin uninstall <plugin>@<marketplace> -y`, then confirm against the manifest: re-read `installed_plugins.json` and check the key is gone. The uninstall reports success regardless, so verify the effect rather than trusting the message.
  - **Project-scope** → skip with a warning ("team-shared via repo settings; remove from the repo's `.claude/settings.json` instead")
- **Missing** (desired, not installed):
  - Offer to install: `claude plugin install <plugin>@<marketplace>`
  - Ask before installing — the desired set may be aspirational or out-of-date.

Now render the **refreshed table** (see "Output model") — the plan table from Step 1, updated in place with terminal statuses and version transitions. The **Status** column carries `updated` / `current` / `skipped (team-shared)` / `skipped (shared install)` / `uninstalled` / `install? (missing)`. For a large desired set, collapse the unchanged `current` rows into a trailing count; if nothing changed at all, skip the table and say so in one line.

## Step 4: Scan caches and data dirs

After reconcile, scan both directories. The cache layout is `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. The data layout is `~/.claude/plugins/data/<plugin>-<marketplace>/` (note: hyphen-joined, not `@`).

```bash
find ~/.claude/plugins/cache -mindepth 3 -maxdepth 3 -type d
```

```bash
find ~/.claude/plugins/data -mindepth 1 -maxdepth 1 -type d
```

Classify every entry against the **currently installed** set (use `claude plugin list` again — the inventory just changed):

- **Orphan cache** — `<plugin>@<marketplace>` no longer installed. Delete-eligible (subject to the `.in_use` check below).
- **Stale version cache** — `<plugin>@<marketplace>` is installed but `<version>` doesn't match the current installed version. Delete-eligible (subject to the `.in_use` check below). Nothing prunes these automatically — left alone they accumulate, and since each version dir is loaded at the startup of any session pinned to it, that's wasted disk and a heavier plugin set. Running this skill is what keeps the cache at one version per plugin.
- **Orphan data dir** — `<plugin>-<marketplace>` slug doesn't match any installed plugin. This is the orphan class nothing else cleans: `claude plugin uninstall` doesn't remove data dirs, and the version-cache lifecycle never touches them. Watch for **legacy slugs** like `<plugin>-inline` left over from local/inline installs. These look orphaned because the slug style changed, not because the plugin was uninstalled — flag them clearly so the user knows the data may still matter.

### Respect `.in_use` leases

Each plugin version dir carries an `.in_use/` directory in which every running session drops a lease file — `{"pid":<n>,"procStart":"<ts>"}`. It's a reference count: a version dir is **live** if any lease names a running process **whose start time still matches the lease's `procStart`**. **Never delete a cache dir with a live lease** — another session loaded that version at startup and is still using its hooks/skills; pruning it breaks that session until it restarts. A lease whose PID is dead is stale and safe to ignore (a platform sweep, recorded in `~/.claude/plugins/.last_inuse_sweep`, eventually clears dead leases).

**Match `procStart`, not just the PID.** The OS recycles PIDs: a dead session's PID gets handed to an unrelated new process, so a `ps -p <pid>` hit alone does **not** prove the lease is live — it false-positives on reuse and wedges the cache dir forever (nothing prunes it). The lease stores `procStart` precisely to disambiguate, so the check compares it to the running process's actual start time, handling two wrinkles: `procStart` is written in **UTC** while `ps -o lstart=` prints **local** time (compared as epoch seconds, matching in either zone since the field's timezone is undocumented), and `date` may be GNU (`date -d`) or BSD (`date -j -f`).

That logic ships as a script — call it per version dir; exit `0` means in use (don't prune), `1` means safe to prune. It's conservative by design: a missing/unparseable `procStart` counts as in use, so uncertainty never prunes.

```bash
if bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-cache-in-use.sh" "$version_dir"; then
  : # live lease — skip (in use)
else
  : # no live lease — delete-eligible
fi
```

(The `.in_use` mechanism is observed from disk, not documented — treat it as a conservative safety check: when a lease looks live, or when you can't confidently prove it dead, don't prune.)

**Report by exception here too.** Stale-version caches are routine — every update leaves one behind — and they're auto-deletable (Step 5), so they don't warrant a row each. Roll them into a single line: count and total size. Reserve table rows for the classes that need user judgment: **orphan caches/data** and **legacy slugs**. If there are none of those, a one-line summary is the whole report.

```text
Stale-version caches: 12 dirs, ~70M — auto-pruned.
```

When orphans or legacy slugs are present, table only those:

```text
| Path                                     | Class       | Size |
|------------------------------------------|-------------|------|
| ~/.claude/plugins/data/beacon-inline     | legacy slug | 744K |
| ~/.claude/plugins/data/old-plugin-old-mp | orphan data | 0    |
```

## Step 5: Clean up (with confirmation)

- **Live-leased cache dirs** (the `.in_use` check above passed) — **never delete**, regardless of class. A live session is loaded from it; pruning breaks that session. Report as "skipped (in use)".
- **Empty cache dirs and orphan/stale caches with no live lease** — safe to delete; do it without asking.
- **Non-empty data dirs** — **ask first**. They may hold user state (settings, history, accumulated context). Quote the size and a sample of file names so the user can decide.
- **Legacy-slug data dirs** — never auto-delete. Show the slug, the size, and the suspected current slug so the user can choose to migrate, archive, or remove.

Use `rm -rf` only after explicit confirmation for non-empty dirs. Never delete the parent `cache/<marketplace>/` or `data/` directories themselves.

## Step 6: Reload plugins

Installs, uninstalls, and updates change plugins on disk but don't take effect in the running session — Claude Code reads the plugin set once at startup and freezes it. `/reload-plugins` re-reads it in place (no restart). It's a built-in command that only a human can type: there's no CLI flag, hook, or skill that triggers a reload, and no way to reload across sessions — each running session is an independent process. So the reconcile only lands where the user runs the reload:

```text
Ask the user to run /reload-plugins in this session — and in any other active
Claude Code session, since each loads plugins independently.
```

Two notes worth stating in the report:

- **Other running sessions still need their own reload.** This reconcile only landed in the session that ran it; every other live session keeps the plugin set it loaded at startup until it reloads or restarts. (Their *loaded* version dirs were protected from pruning by the `.in_use` check in Step 5 — they're stale, not broken.)
- **Reload is rarely needed going forward.** With marketplace auto-update on (shipshape's `SessionStart` hook), every new session loads the current set at launch. This step matters mainly for the session that just ran a manual reconcile.

Skip this entirely if Step 3 made no changes and Step 5 pruned nothing — there's nothing to reload.

## CLI reference

```bash
claude plugin list                                    # inventory
claude plugin update <plugin>@<marketplace>           # update
claude plugin install <plugin>@<marketplace>          # install
claude plugin uninstall <plugin>@<marketplace> -y     # uninstall (fails on project-scope)
claude plugin --help                                  # full subcommand list (includes prune, enable, disable)
```

`claude plugin prune` removes auto-installed dependencies that are no longer needed but does **not** touch caches or data dirs — that's still this skill's job.

## Paths

```text
Settings:              ~/.claude/settings.json  (enabledPlugins = desired set)
Cache:                 ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/
Data:                  ~/.claude/plugins/data/<plugin>-<marketplace>/
Known marketplaces:    ~/.claude/plugins/known_marketplaces.json
Installed manifest:    ~/.claude/plugins/installed_plugins.json
```
