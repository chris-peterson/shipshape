# shipshape — Specification

shipshape is a Claude Code plugin that maintains your *other* Claude Code
plugins — reconciling installed plugins against your declared desired set,
updating what stays, pruning the stale caches and orphan data dirs that
uninstall leaves behind, and arming marketplace auto-update so plugins keep
themselves current.

Requirements use [EARS syntax](https://alistairmavin.com/ears) — each is one of:
Ubiquitous (`The <system> shall …`), State-Driven (`While …`), Event-Driven
(`When …`), Optional (`Where …`), or Unwanted Behaviour (`If … then …`).

## Concepts

- **Desired set** — the plugins declared under `enabledPlugins` in
  `~/.claude/settings.json` (a map of `<plugin>@<marketplace>` → bool). The set
  the user has said should be enabled; disk state may have drifted from it.
- **Installed set** — the plugins reported by `claude plugin list`, each with a
  `<plugin>@<marketplace>` key, version, scope, and status.
- **Install manifest** — `~/.claude/plugins/installed_plugins.json`; records
  each on-disk install once, keyed by `<plugin>@<marketplace>`.
- **Scope** — a plugin's origin: **user** (personal, safe to reconcile),
  **project** (checked into a repo, team-shared), or **local**.
- **Version cache** — `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`;
  a per-version on-disk copy loaded at the startup of any session pinned to it.
- **Data dir** — `~/.claude/plugins/data/<plugin>-<marketplace>/` (hyphen-joined);
  may hold accumulated user state.
- **`.in_use` lease** — a per-version reference count: each running session
  drops a `{"pid","procStart"}` lease file; a version dir is live while any
  lease names a running process whose start time still matches `procStart`.
- **Maintenance lock** — a cooperative lock held for the duration of a
  reconcile, since `claude plugin` operations have no concurrency control.
- **Marketplace auto-update** — `extraKnownMarketplaces.<name>.autoUpdate` in
  settings.json; when true, a marketplace refreshes and updates its plugins at
  startup.

## Requirements

### RCON — Reconciliation

- [RCON-01] When a maintenance run begins, shipshape shall acquire a
  cooperative maintenance lock before performing any mutating plugin operation.
- [RCON-02] If the maintenance lock is held by another live session, then
  shipshape shall stop and report the holding session without reconciling.
- [RCON-03] The maintenance lock shall be re-entrant within a session and shall
  be stolen once older than the stale threshold.
- [RCON-04] When a maintenance run exits by any path, shipshape shall release
  the maintenance lock before completing.
- [RCON-05] shipshape shall build the installed set from `claude plugin list`
  and the desired set from `enabledPlugins` in `~/.claude/settings.json`.
- [RCON-06] shipshape shall diff the installed set against the desired set,
  classifying each plugin as current, extra, or missing.
- [RCON-07] When updating plugins, shipshape shall refresh every marketplace
  once via `claude plugin marketplace update` before updating individual
  plugins.
- [RCON-08] shipshape shall update plugins serially, one at a time, not in a
  parallel batch.
- [RCON-09] If a plugin update fails with a transient error, then shipshape
  shall retry it once serially and report the real outcome.
- [RCON-10] Where a desired plugin is not installed, shipshape shall offer to
  install it and ask before installing.
- [RCON-11] When an installed user-scope plugin is not in the desired set,
  shipshape shall uninstall it and verify against the install manifest that its
  key is gone.
- [RCON-12] When reconciliation changes plugins on disk, shipshape shall ask
  the user to run `/reload-plugins` in this and any other active session.
- [RCON-13] If reconciliation made no changes and pruning removed nothing, then
  shipshape shall skip the reload step.

### GARD — Guardrails

- [GARD-01] If an extra plugin has project scope, then shipshape shall skip it
  with a warning and not uninstall it.
- [GARD-02] If an extra plugin's key is absent from `installed_plugins.json`
  while another row for the same plugin name is present, then shipshape shall
  treat it as a shared on-disk install and skip uninstalling it.
- [GARD-03] shipshape shall gate every uninstall on the install manifest rather
  than on `claude plugin list` and the desired set alone.

### PRUN — Pruning

- [PRUN-01] When reconciliation completes, shipshape shall scan the cache and
  data directories and classify each entry against the currently installed set.
- [PRUN-02] shipshape shall classify a cache dir whose `<plugin>@<marketplace>`
  is no longer installed as an orphan cache.
- [PRUN-03] shipshape shall classify a cache dir whose version does not match
  the installed version as a stale-version cache.
- [PRUN-04] shipshape shall classify a data dir whose slug matches no installed
  plugin as an orphan data dir.
- [PRUN-05] If a data dir slug ends in `-inline`, then shipshape shall ignore
  it entirely and omit it from the report.
- [PRUN-06] If a cache version dir has a live `.in_use` lease, then shipshape
  shall never delete it and shall report it as skipped (in use).
- [PRUN-07] shipshape shall determine lease liveness via
  `plugin-cache-in-use.sh` (exit 0 = in use, exit 1 = delete-eligible) and act
  on that verdict without auditing it.
- [PRUN-08] shipshape shall treat a missing or unparseable lease `procStart` as
  in use.
- [PRUN-09] When a cache dir is empty, or an orphan/stale cache with no live
  lease, shipshape shall delete it without prompting.
- [PRUN-10] If a data dir to be removed is non-empty, then shipshape shall ask
  first, quoting its size and a sample of file names.
- [PRUN-11] shipshape shall never delete the parent `cache/<marketplace>/` or
  `data/` directories.

### AUTO — Auto-update enforcement

- [AUTO-01] When a session starts, the auto-update hook shall set
  `autoUpdate: true` for every known marketplace under `extraKnownMarketplaces`
  in `~/.claude/settings.json`.
- [AUTO-02] The auto-update hook shall write only when a marketplace is missing
  the flag, leaving settings unchanged at steady state.
- [AUTO-03] The auto-update hook shall preserve existing `extraKnownMarketplaces`
  entries and all other settings keys.
- [AUTO-04] If no marketplaces are registered, then the auto-update hook shall
  exit without changes.
- [AUTO-05] If `jq` is not on PATH, then the auto-update hook shall report that
  jq is required and exit without changes.
- [AUTO-06] The maintenance run shall report each marketplace's auto-update
  status without writing it.

### RPRT — Reporting & output model

- [RPRT-01] shipshape shall present a run using three surfaces: an inventory
  summary + plan table, the native task list, and a final report.
- [RPRT-02] shipshape shall lead both the opening summary and the closing
  report with the same composition line (installed / enabled / disabled).
- [RPRT-03] shipshape shall tag statuses with the shared emoji vocabulary.
- [RPRT-04] shipshape shall list every enabled plugin on its own row in the
  updates report rather than collapsing unchanged ones into a count.
- [RPRT-05] shipshape shall report stale-version caches by exception as a
  single count-and-size line, reserving table rows for genuine orphans.
- [RPRT-06] shipshape shall report outcomes only — no per-tool-call preambles,
  no narrated investigation.
- [RPRT-07] shipshape shall report only the current run's plugin maintenance
  and no unrelated work.

## Future Requirements

_(none yet)_
