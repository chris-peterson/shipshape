# shipshape — Specification

shipshape is a Claude Code plugin with two goals for your **harness**: that you
know what's changing in it, and that it stays current. Claude Code itself:
announcing a version change, walking the changelog entries you skipped, and,
when you acknowledge the upgrade, running the re-training instructions you wrote
for one. Your *other* plugins: reconciling installed plugins against your
declared desired set, updating what stays, pruning the stale version caches an
update leaves behind and the data dirs an uninstall would have deleted
unasked, and arming marketplace auto-update so plugins keep themselves
current.

Requirements use [EARS syntax](https://alistairmavin.com/ears) — each is one of:
Ubiquitous (`The <system> shall …`), State-Driven (`While …`), Event-Driven
(`When …`), Optional (`Where …`), or Unwanted Behaviour (`If … then …`).

## Concepts

- **Harness** — everything wrapped around the model that decides how well it works
  for a user: the Claude Code install, the plugins enabled in it, and the rules,
  skills, and hooks they wrote. [Thoughtworks' Technology
  Radar](https://www.thoughtworks.com/radar) (Vol. 34, theme *Putting coding
  agents on a leash*) scopes the term to the *controls* in that set — Agent
  Skills and the marketplaces distributing them on the feedforward side, quality
  gates on the feedback side. shipshape's scope is the staleness those controls
  accumulate, not the controls themselves.
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
- **Version marker** — `${CLAUDE_PLUGIN_DATA}/acknowledged-version`; the Claude
  Code version the user has acknowledged. A newer running version is *pending*.
- **Version-change guide** — `${CLAUDE_PLUGIN_DATA}/on-claude-code-version-change.md`;
  what the user wants done when Claude Code's version changes, written as
  instructions. Carried out unaltered apart from its comments, so the commands
  it names are the commands that run.
- **Guide content** — the guide's lines with HTML comment spans and leading
  blank lines removed. One test of content decides both whether the guide is
  filled in and what gets carried out, which is what lets the seeded template
  explain itself without the explanation arriving as an instruction.
- **Unfilled guide** — a guide with no content. The seeded template is unfilled
  by construction.
- **Version skill** — `/claude-code-version`; everything a user does about a
  version change: read or set the guide, walk what's new, and acknowledge the
  upgrade. It reaches the hook through `${CLAUDE_PLUGIN_ROOT}`, which Claude
  Code resolves when the skill loads, so no shipshape version is baked into a
  path.
- **Acknowledgement** — recording the running version in the marker, which
  clears the banner. The guide runs at that moment and only then, so the skill
  is the only path that acknowledges.

## Requirements

### RECON — Reconciliation

- [RECON-01] When a maintenance run begins, shipshape shall acquire a
  cooperative maintenance lock before performing any mutating plugin operation.
- [RECON-02] If the maintenance lock is held by another live session, then
  shipshape shall stop and report the holding session without reconciling.
- [RECON-03] The maintenance lock shall be re-entrant within a session and shall
  be stolen once older than the stale threshold.
- [RECON-15] If the maintenance lock's age cannot be read, then shipshape shall
  treat the lock as held and refuse to acquire it, reporting why. Stealing is
  reserved for a lock provably older than the threshold; an unreadable age
  proves nothing.
- [RECON-04] When a maintenance run exits by any path, shipshape shall release
  the maintenance lock before completing.
- [RECON-05] shipshape shall build the installed set from `claude plugin list`
  and the desired set from `enabledPlugins` in `~/.claude/settings.json`.
- [RECON-06] shipshape shall diff the installed set against the desired set,
  classifying each plugin as current, extra, or missing.
- [RECON-07] When updating plugins, shipshape shall refresh every marketplace
  once via `claude plugin marketplace update` before updating individual
  plugins.
- [RECON-08] shipshape shall update plugins serially, one at a time, not in a
  parallel batch.
- [RECON-09] If a plugin update fails with a transient error, then shipshape
  shall retry it once serially and report the real outcome.
- [RECON-10] Where a desired plugin is not installed, shipshape shall offer to
  install it and ask before installing.
- [RECON-11] When an installed user-scope plugin is not in the desired set,
  shipshape shall uninstall it with `--keep-data` and verify against the install
  manifest that its key is gone.
- [RECON-11a] shipshape shall never let an uninstall delete a data dir: an
  uninstall from a plugin's last remaining scope deletes
  `${CLAUDE_PLUGIN_DATA}` by default, so the data dir reaches the prune step
  and its confirmation (PRUNE-10) rather than being removed unasked.
- [RECON-12] When reconciliation changes plugins on disk, shipshape shall ask
  the user to run `/reload-plugins` in this and any other active session, and
  shall name the `--force` rerun that a prompt-cache warning requires.
- [RECON-13] If reconciliation made no changes and pruning removed nothing, then
  shipshape shall skip the reload step.
- [RECON-14] If an install or update fails because a marketplace-declared
  command was not accepted — a `headersHelper` minting the archive fetch's
  headers, or a `command` source printing the plugin directory — then shipshape
  shall report the plugin as needing the user's own terminal, quoting the
  command line to run there, and shall not retry it as a transient failure.
  `-y` cannot stand in for that acceptance: Claude Code ignores the flag inside
  a session, and the skill's shell has no TTY to prompt on, so the command is
  printed and declined.

### GUARD — Guardrails

- [GUARD-01] If an extra plugin has project scope, then shipshape shall skip it
  with a warning and not uninstall it.
- [GUARD-02] If an extra plugin's key is absent from `installed_plugins.json`
  while another row for the same plugin name is present, then shipshape shall
  treat it as a shared on-disk install and skip uninstalling it.
- [GUARD-03] shipshape shall gate every uninstall on the install manifest rather
  than on `claude plugin list` and the desired set alone.

### PRUNE — Pruning

- [PRUNE-01] When reconciliation completes, shipshape shall scan the cache and
  data directories and classify each entry against the install paths the install
  manifest records.
- [PRUNE-02] shipshape shall classify a cache dir whose `<plugin>@<marketplace>`
  is no longer installed as an orphan cache.
- [PRUNE-03] shipshape shall classify a cache dir whose version does not match
  the installed version as a stale-version cache.
- [PRUNE-04] shipshape shall classify a data dir whose slug matches no installed
  plugin as an orphan data dir.
- [PRUNE-05] If a data dir slug ends in `-inline`, then shipshape shall ignore
  it entirely and omit it from the report.
- [PRUNE-06] If a cache version dir has a live `.in_use` lease, then shipshape
  shall never delete it and shall report it as skipped (in use).
- [PRUNE-07] shipshape shall determine lease liveness via
  `plugin-cache-in-use.sh` (exit 0 = in use, exit 1 = delete-eligible) and act
  on that verdict without auditing it.
- [PRUNE-08] shipshape shall treat a lease it cannot read as in use: one that
  yields no `pid`, and one whose `procStart` is missing or unparseable. An
  unreadable lease is not an absent lease.
- [PRUNE-09] When a cache dir is empty, or an orphan/stale cache with no live
  lease, shipshape shall delete it without prompting.
- [PRUNE-10] If a data dir to be removed is non-empty, then shipshape shall ask
  first, quoting its size and a sample of file names.
- [PRUNE-11] shipshape shall never delete the parent `cache/<marketplace>/` or
  `data/` directories.
- [PRUNE-12] shipshape shall enumerate and classify cache and data entries via
  `plugin-cache-scan.sh`, which prints a `path|class|verdict|size` row for each
  entry no current install claims and a `#totals` line, rather than assembling
  the walk in the skill.
- [PRUNE-13] shipshape shall delete only via `plugin-cache-prune.sh`, which
  re-checks a cache dir's lease immediately before deleting it and clears a
  plugin dir left empty with `rmdir`.
- [PRUNE-14] If a path given to `plugin-cache-prune.sh` is not a cache version
  dir, a cache plugin dir, or a data dir, then the script shall refuse it, leave
  it untouched, and exit non-zero.
- [PRUNE-15] Where a data dir to be removed is non-empty, `plugin-cache-prune.sh`
  shall skip it unless `--data-confirmed` is passed, so the confirmation is the
  skill's to obtain and the script's to require.
- [PRUNE-16] shipshape shall classify a cache or data entry whose origin is not a
  marketplace in `known_marketplaces.json` as unknown-origin, report it, and
  never prune it. `synced` is such an origin: a plugin turned on in claude.ai has
  no install manifest row, so classifying it by the manifest alone would call it
  an orphan. Reporting rather than ignoring keeps the leftovers of a removed
  marketplace visible. If the registry cannot be read, then no origin is
  recognized and nothing is prunable.

### AUTO — Auto-update enforcement

- [AUTO-01] When a session starts, the auto-update hook shall read the
  registered marketplaces from `~/.claude/plugins/known_marketplaces.json` and
  set `autoUpdate: true` on each one's `extraKnownMarketplaces` entry in
  `~/.claude/settings.json`, creating that entry where it does not exist.
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

### VERSION — Claude Code version changes

- [VERSION-01] When a session starts, the version hook shall compare the running
  Claude Code version against the version marker.
- [VERSION-02] While the running version differs from the marker, the version hook
  shall show the user a banner at every session start, naming both versions,
  linking the changelog entry for the running version, and naming the version
  skill.
- [VERSION-03] When the banner is shown, the version hook shall leave the marker
  unchanged, so the announcement outlives the session it appears in.
- [VERSION-04] The version hook shall deliver the banner on its user-visible channel
  and the handoff to the version skill as model context.
- [VERSION-05] The version hook shall not emit the guide's content, since it fires
  at every session start while a version is pending and the guide is a one-time
  upgrade errand.
- [VERSION-06] Where the guide is absent, the version hook shall seed it with an
  unfilled template naming what to write in it.
- [VERSION-07] When invoked with `--guide`, the version hook shall print the
  guide's content and nothing else.
- [VERSION-08] The version hook shall treat any difference in the version string as
  a change, including a patch bump.
- [VERSION-09] When invoked with `--ack <version>`, the version hook shall record
  that version in the marker and report what it recorded.
- [VERSION-10] When invoked with `--status`, the version hook shall report the
  acknowledged and running versions, whether one is pending, the changelog entry
  for the running version, and the guide's path and filled state, without
  writing the marker.
- [VERSION-11] Where no version has been acknowledged yet, or the marker is not a
  version, the version hook shall write the marker without showing a banner.
- [VERSION-12] Where `SHIPSHAPE_VERSION_NOTICE` is `off`, the version hook shall
  skip the announcement without reading or writing the marker, while `--ack`,
  `--status`, and `--guide` still answer.
- [VERSION-13] The version hook shall read the running version from `claude
  --version`'s stdout alone, so output on stderr is never parsed as a version.
- [VERSION-14] If the running version cannot be determined, or `CLAUDE_PLUGIN_DATA`
  is unset, or `jq` is not on PATH, then the version hook shall report the reason
  on stderr and leave the marker unchanged.
- [VERSION-15] If a comment in the guide is never closed, then the version hook
  shall report it on stderr rather than fall silent.
- [VERSION-16] If a mode other than the announcement cannot answer, then the
  version hook shall exit non-zero rather than report a result it didn't produce.
- [VERSION-17] When the version skill is invoked without a mode, shipshape shall
  report the acknowledged and running versions and summarize what changed.
- [VERSION-18] When the user asks to see or change the guide, shipshape shall show
  it and shall write their instructions into it only once they approve the text.
- [VERSION-19] When the user asks what changed, shipshape shall summarize the
  changelog entries after the acknowledged version through the running version
  in one screen, leading with what the user would act on and offering the
  per-release walk rather than printing it, without acknowledging as a side
  effect.
- [VERSION-20] When the user acknowledges an upgrade, shipshape shall carry out the
  guide's content before recording the version, and shall leave the version
  unacknowledged if a step fails.
- [VERSION-21] Where no version is pending, shipshape shall not carry out the guide.
- [VERSION-22] The version skill shall address the version hook and the plugin
  data dir by placeholder rather than by literal path, so it survives a
  shipshape update.
- [VERSION-23] The version skill shall summarize what changed on every path but
  the guide, so a version is never acknowledged, or offered for acknowledgement,
  without the user having been shown what it holds.
- [VERSION-24] Where a version is pending, the version skill shall close every
  path but the guide with a two-option question — acknowledge now, carrying out
  the guide, or leave it pending — rather than a prose offer.
- [VERSION-25] Where the guide is filled, the version skill shall precede that
  question with what acknowledging will run, in at most three lines.
- [VERSION-26] While carrying out the guide, shipshape shall establish a step's
  findings against the sources the step names before recording the version,
  since recording is what ends the errand and a finding the user cannot act on
  leaves nothing for the banner to bring them back to.
- [VERSION-27] Where a guide step asks for a pass over the user's plugins,
  shipshape shall analyze the ones the user maintains and shall leave the ones
  they only use to their own maintainers, reporting those as a count. Which is
  which is not derivable from the install — both are installed and both have a
  source repo — so shipshape shall keep the user's declaration in the plugin
  data dir, keyed by install-manifest key, and shall accept a bare key for a
  repo that ships as no plugin, since the manifest names what the user
  installed and not the tooling that builds it.
- [VERSION-28] shipshape shall reconcile that declaration against the install
  manifest and shall ask only about the difference: a plugin installed with no
  decision on record, a decision whose plugin is gone, or a recorded source path
  that is no longer a directory. A recorded path it cannot read shall be
  reported as a question rather than scanned or dropped, so a pass is never
  reported over a repo that was not read.
- [VERSION-29] When the user acknowledges an upgrade, shipshape shall dispose of
  every changelog entry between the acknowledged and running versions, giving
  each a line and a disposition, rather than only those the one-screen summary
  led with. The guide runs against what changed, so an entry nobody read is an
  artifact nobody checked.
- [VERSION-30] Where a guide step fans out over independent targets, shipshape
  shall return one verdict per candidate per target, each anchored at the file
  and line that establishes or disproves it, and shall report the verdict count
  so the coverage is legible.
- [VERSION-31] shipshape shall deliver a run's findings in one pass rather than
  one at a time, since the decision the user makes is which of them to act on
  and that needs all of them in view.

### REPORT — Reporting & output model

- [REPORT-01] shipshape shall present a run using three surfaces: an inventory
  summary + plan table, the native task list, and a final report.
- [REPORT-02] shipshape shall lead both the opening summary and the closing
  report with the same composition line (installed / enabled / disabled).
- [REPORT-03] shipshape shall tag statuses with the shared emoji vocabulary.
- [REPORT-04] shipshape shall list every enabled plugin on its own row in the
  updates report rather than collapsing unchanged ones into a count.
- [REPORT-05] shipshape shall report stale-version caches by exception as a
  single count-and-size line, reserving table rows for genuine orphans.
- [REPORT-06] shipshape shall report outcomes only — no per-tool-call preambles,
  no narrated investigation.
- [REPORT-07] shipshape shall report only the current run's plugin maintenance
  and no unrelated work.

## Future Requirements

_(none yet)_
