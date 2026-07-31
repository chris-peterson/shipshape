# shipshape — Specification

shipshape is a Claude Code plugin that maintains your *other* Claude Code
plugins — reconciling installed plugins against your declared desired set,
updating what stays, pruning the stale caches and orphan data dirs that
uninstall leaves behind, and arming marketplace auto-update so plugins keep
themselves current. It also watches Claude Code's own version, handing Claude
your re-training instructions the first session after it changes.

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
- **Plugin data dir** — `${CLAUDE_PLUGIN_DATA}`, the per-plugin directory Claude
  Code guarantees survives plugin updates. shipshape's own state belongs here
  rather than in a version cache, which an update abandons and a prune removes.
- **Callback document** — `${CLAUDE_PLUGIN_DATA}/on-claude-code-version-change.md`;
  what the user wants done when Claude Code's version changes, written as
  instructions. Emitted into the session unaltered apart from its comments, so
  the commands it names are the commands that run.
- **Document content** — the document's lines with HTML comments and leading
  blank lines removed. One test of content decides both whether the document is
  filled in and what gets emitted, which is what lets the seeded template
  explain itself without the explanation arriving as an instruction.
- **Unfilled document** — a callback document with no content. The seeded
  template is unfilled by construction.

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

### CALL — Claude Code version-change callbacks

- [CALL-01] When a session starts, the version-callback hook shall compare the
  version reported by `claude --version` against the version recorded on the
  previous run.
- [CALL-02] The version-callback hook shall record the current version in the
  plugin data dir on every run that reads a version, whether or not callbacks
  fire.
- [CALL-03] Where the callback document is absent, the version-callback hook
  shall seed it with an unfilled template naming what to write in it.
- [CALL-04] When no version has been recorded yet, the version-callback hook
  shall record the current version and report the callback document's path
  without emitting callbacks.
- [CALL-05] When the recorded version differs from the current version, the
  version-callback hook shall emit the callback document's content, led by a
  line naming the recorded and current versions and an instruction to follow it
  now.
- [CALL-06] The version-callback hook shall treat any difference in the version
  string as a change, including a patch bump.
- [CALL-07] While the recorded version matches the current version, the
  version-callback hook shall exit without output.
- [CALL-08] If the callback document is unfilled, then the version-callback hook
  shall record the version and emit nothing.
- [CALL-09] The version-callback hook shall record the new version before
  emitting, so one version change fires exactly once.
- [CALL-10] If `${CLAUDE_PLUGIN_DATA}` is unset, then the version-callback hook
  shall report that it is required and exit without writing state.
- [CALL-11] If `claude` is absent from PATH or fails to report a version, then
  the version-callback hook shall report that and exit without writing state.

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
