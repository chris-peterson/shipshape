# shipshape — Specification

shipshape is a Claude Code plugin with two goals for your **harness**: that you
know what's changing in it, and that it stays current. Claude Code itself:
announcing a version change, walking the changelog entries you skipped, and,
when you acknowledge the upgrade, running the re-training instructions you wrote
for one. Your *other* plugins: reconciling installed plugins against your
declared desired set, updating what stays, pruning the stale version caches an
update leaves behind and the data dirs an uninstall would have deleted
unasked, and enabling marketplace auto-update so plugins keep themselves
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
- **Managed plugin** — one whose key's `@<origin>` is a marketplace in
  `known_marketplaces.json`. The rest are *unmanaged*: `<name>@synced` is a
  plugin turned on in claude.ai and governed there, which nothing local
  installed and no local marketplace serves. Both sets are diffed over managed
  keys only.
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
  `/maintain-harness` run, across both halves, since `claude plugin` operations
  have no concurrency control and the upgrade half writes shared state too.
- **Marketplace auto-update** — `extraKnownMarketplaces.<name>.autoUpdate` in
  settings.json; when true, a marketplace refreshes and updates its plugins at
  startup.
- **Plugin data dir** — `${CLAUDE_PLUGIN_DATA}`, the per-plugin directory Claude
  Code guarantees survives plugin updates. shipshape's own state belongs here
  rather than in a version cache, which an update abandons and a prune removes.
- **Version marker** — `${CLAUDE_PLUGIN_DATA}/acknowledged-version`; the Claude
  Code version the user has acknowledged. A newer running version is *pending*.
- **Harness maintenance guide** — `${CLAUDE_PLUGIN_DATA}/harness-maintenance-guide.md`;
  what the user wants done after each half of the harness skill, written as
  instructions in two sections: `## After a Claude Code upgrade` and
  `## After plugins change`. Each half carries out only its own section, and a
  `###` subheading stays inside the section it sits in. Carried out unaltered
  apart from its comments, so the commands it names are the commands that run.
- **Section** — the lines under one of the guide's two headings, up to the next
  `##` heading. Text before the first heading or under any other `##` heading
  is *stray*: never carried out, and reported.
- **Guide content** — the guide's lines with HTML comment spans and leading
  blank lines removed. One test of content decides both whether the guide is
  filled in and what gets carried out, which is what lets the seeded template
  explain itself without the explanation arriving as an instruction.
- **Unfilled section** — a section with no content. Both sections of the seeded
  template are unfilled by construction.
- **Harness skill** — `/maintain-harness`; shipshape's one entry point. Its
  argument picks a half: `claude-code`, `plugins`, or `all` (the default, both
  in that order). Each half lives in its own reference file, so a run loads only
  what it does. The skill body states the resolved `${CLAUDE_PLUGIN_ROOT}` and
  `${CLAUDE_PLUGIN_DATA}`, which Claude Code fills in when the skill loads, and
  the references' commands take those values, so no shipshape version is baked
  into a path.
- **Version skill** — the harness skill's `claude-code` half; everything a user
  does about a version change: read or set the guide's upgrade section, walk
  what's new, and acknowledge the upgrade.
- **Acknowledgement** — recording the running version in the marker, which
  clears the banner. The guide runs at that moment and only then, so the skill
  is the only path that acknowledges.

## Requirements

### HARNESS — The entry point

- [HARNESS-01] shipshape shall expose one user-facing skill, `/maintain-harness`,
  whose first argument word selects what runs: `claude-code` (or `cc`),
  `plugins`, `all`, or `guide` (show, change, or set up the guide, running
  neither half).
- [HARNESS-02] When `/maintain-harness` is invoked with no argument or with
  `all`, shipshape shall run the Claude Code half and then the plugins half.
- [HARNESS-03] Where `/maintain-harness` has no argument and the request names
  only one half, shipshape shall run that half alone.
- [HARNESS-04] While running `all` with no version pending, shipshape shall
  report the acknowledged version in one line and proceed to the plugins half
  without walking the changelog or carrying out the guide's upgrade section. Where the
  user leaves a pending version pending, the plugins half shall still run.
- [HARNESS-05] Where a step in the guide's upgrade section names
  `/maintain-harness plugins`, shipshape shall carry out the plugins half for it:
  in place under `claude-code`, and once, after the Claude Code half, under
  `all`.
- [HARNESS-06] When a `/maintain-harness` run begins, shipshape shall acquire the
  maintenance lock before either half, acquire it again at the start of each
  half so its age stays fresh, and release it when the run's mutating work ends
  on every exit path.
- [HARNESS-07] The harness skill shall be started only by the user typing it,
  never invoked by Claude, since a run updates, uninstalls, and prunes the
  user's plugins.

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
  No flag can stand in for that acceptance, `-y` and `--accept-command` alike:
  Claude Code ignores either one inside a session, and the skill's shell has no
  TTY to prompt on, so the command is printed and declined.
- [RECON-16] shipshape shall leave every unmanaged plugin out of the diff, the
  updates, installs, and uninstalls, and shall list each installed one in the
  final report under its origin: `synced` as managed in claude.ai, any other
  origin as not a registered marketplace. If the marketplace registry, the
  plugin list, or the settings file cannot be read, then shipshape shall stop
  the reconcile and report which, since an unreadable registry would mark every
  plugin unmanaged and an unreadable list or settings file would hide one.

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
- [PRUNE-17] If a top-level `cache/` entry holds a `.git` directory, then
  shipshape shall classify it as a scratch clone, report it as one entry, and
  never descend into it. Claude Code clones into `cache/temp_git_*` and
  `cache/temp_subdir_*.clone` while resolving a marketplace; a marketplace origin
  holds plugin dirs and keeps its own clone under `marketplaces/`, so the `.git`
  is what tells the two apart. Reported whole, a leftover clone is one line
  naming what Claude Code created; walked at the version-dir depth it becomes one
  line per directory inside it.
- [PRUNE-18] shipshape shall report each entry in the update staging directory
  (`~/.cache/claude/staging`, overridable with `CLAUDE_STAGING_DIR`) as a staged
  download, with its size, and shall not prune it. A failed auto-update leaves
  its download there. The directory is outside `~/.claude/plugins`, and
  `plugin-cache-prune.sh` accepts cache and data paths only (PRUNE-14), so the
  entry is surfaced for the user to clear rather than reached by widening that
  guard.

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
  shall show the user a banner at every session start, naming both versions and
  the version skill, and shall link the changelog in the handoff, anchored at the
  running version's heading. The anchor reaches an entry only where the running
  version has one; Claude Code ships versions the changelog never mentions, and
  for those the link opens the top of the file.
- [VERSION-03] When the banner is shown, the version hook shall leave the marker
  unchanged, so the announcement outlives the session it appears in.
- [VERSION-04] The version hook shall deliver the banner on its user-visible channel
  and the handoff to the version skill as model context. The handoff shall tell
  Claude to name the command for the user to type, since only the user starts
  the harness skill (HARNESS-07).
- [VERSION-05] The version hook shall not emit the guide's content, since it fires
  at every session start while a version is pending and the guide is a one-time
  upgrade errand.
- [VERSION-06] When invoked with `--status`, the version hook shall take the
  guide's path and whether its upgrade section is filled from
  `harness-guide.sh --status`, so the guide has one reader.
- [VERSION-07] The version hook shall treat any difference in the version string as
  a change, including a patch bump.
- [VERSION-08] When invoked with `--ack <version>`, the version hook shall record
  that version in the marker and report what it recorded.
- [VERSION-09] When invoked with `--status`, the version hook shall report the
  acknowledged and running versions, whether one is pending, the changelog entry
  for the running version, the guide's path and whether its upgrade section is
  filled, and the
  declaration's path, whether it has been configured, and its examined and
  skipped counts, without writing the marker.
- [VERSION-10] Where no version has been acknowledged yet, or the marker is not a
  version, the version hook shall write the marker without showing a banner.
- [VERSION-11] Where `SHIPSHAPE_VERSION_NOTICE` is `off`, the version hook shall
  skip the announcement without reading or writing the marker, while `--ack` and
  `--status` still answer.
- [VERSION-12] The version hook shall read the running version from `claude
  --version`'s stdout alone, so output on stderr is never parsed as a version.
- [VERSION-13] If the running version cannot be determined, or `CLAUDE_PLUGIN_DATA`
  is unset, or `jq` is not on PATH, then the version hook shall report the reason
  on stderr and leave the marker unchanged.
- [VERSION-14] If a mode other than the announcement cannot answer, then the
  version hook shall exit non-zero rather than report a result it didn't produce.
- [VERSION-15] When the version skill is invoked without a mode, shipshape shall
  report the acknowledged and running versions and summarize what changed. The
  status line shall carry nothing beyond the versions except what needs the
  user's action.
- [VERSION-16] When the user asks to see or change the guide's upgrade section,
  shipshape shall handle it as GUIDE-08 does.
- [VERSION-17] When the user asks what changed, shipshape shall summarize the
  changelog entries after the acknowledged version through the running version,
  leading with what the user would act on and then walking every remaining
  entry, without acknowledging as a side effect. It shall never offer a walk in
  place of giving one, count entries it didn't show, or describe entries as
  passed over. A version in that range with no changelog entry shall be named as
  having none, without characterizing what it contained.
- [VERSION-18] When the user acknowledges an upgrade, shipshape shall carry out the
  guide's content before recording the version, and shall leave the version
  unacknowledged if a step fails.
- [VERSION-19] Where no version is pending, shipshape shall not carry out the guide.
- [VERSION-20] The version skill shall address the version hook and the plugin
  data dir by placeholder rather than by literal path, so it survives a
  shipshape update.
- [VERSION-21] The version skill shall summarize what changed on every path but
  the guide, so a version is never acknowledged, or offered for acknowledgement,
  without the user having been shown what it holds.
- [VERSION-22] Where a version is pending, the version skill shall close every
  path but the guide with a two-option question — acknowledge now, carrying out
  the guide, or leave it pending — rather than a prose offer.
- [VERSION-23] The version skill shall precede that question with what
  acknowledging will run, in at most three lines — the built-in guide's scope
  always, and the user's own steps where their guide is filled. Acknowledging is
  never the recording alone, so a description offering only that the banner
  stops understates a fan-out over every repo the user declared.
- [VERSION-24] While carrying out the guide, shipshape shall establish a step's
  findings against the sources the step names before recording the version,
  since recording is what ends the errand and a finding the user cannot act on
  leaves nothing for the banner to bring them back to.
- [VERSION-25] Where a guide step asks for a pass over the user's plugins,
  shipshape shall analyze the ones the user maintains and shall leave the ones
  they only use to their own maintainers, reporting nothing about them — not a
  list, not a count, and not a closing tally. The declaration has already
  settled that they are not the run's business, and a number about software the
  user does not maintain gives them nothing to act on. Which is
  which is not derivable from the install — both are installed and both have a
  source repo — so shipshape shall keep the user's declaration in the plugin
  data dir, keyed by install-manifest key, and shall accept a bare key for a
  repo that ships as no plugin, since the manifest names what the user
  installed and not the tooling that builds it.
- [VERSION-26] shipshape shall reconcile that declaration against the install
  manifest and shall ask only about the difference: a plugin installed with no
  decision on record, a decision whose plugin is gone, or a recorded source path
  that is no longer a directory. A recorded path it cannot read shall be
  reported as a question rather than scanned or dropped, so a pass is never
  reported over a repo that was not read.
- [VERSION-27] When the user acknowledges an upgrade, shipshape shall dispose of
  every changelog entry between the acknowledged and running versions, giving
  each a line and a disposition, rather than only those the one-screen summary
  led with. The guide runs against what changed, so an entry nobody read is an
  artifact nobody checked.
- [VERSION-28] Where a guide step fans out over independent targets, shipshape
  shall return one verdict per candidate per target, each anchored at the file
  and line that establishes or disproves it, and shall report the verdict count
  so the coverage is legible.
- [VERSION-29] shipshape shall deliver a run's findings in one pass rather than
  one at a time, since the decision the user makes is which of them to act on
  and that needs all of them in view. It shall then walk the findings one at a
  time, asking per finding whether to file it or fix it now and carrying the
  file, the line and the size of the fix into the question. Delivering the set
  is what makes the findings comparable; a single closing offer over the set
  asks for one answer across findings whose answers differ.
- [VERSION-30] While carrying out a multi-step guide, shipshape shall report the
  outcome of each step rather than each tool call it took, so the results the
  user can act on are not buried in the mechanics of reaching them.
- [VERSION-31] shipshape shall write a file it creates for its own bookkeeping
  to a scratch path outside any repo the guide names — including where the guide
  asks for a document without naming a path, since a repo the guide names is
  shared with the user's other sessions and an invented address lands the file
  untracked beside their work. Where the guide names a path, shipshape shall
  honor it.
- [VERSION-32] When the user acknowledges an upgrade, shipshape shall carry out
  its own built-in guide, and the user's guide shall add to that rather than
  replace it. An upgrade invalidates the artifacts a user already has, so a
  user who has written no guide of their own shall not receive an upgrade that
  only clears a banner.
- [VERSION-33] The built-in guide shall check the user's own `~/.claude`
  artifacts, since those are present for every user whether or not they
  maintain a plugin. Where a declared target's repo deploys into `~/.claude`,
  shipshape shall detect staleness there and land the fix in that repo, because
  a fix written into the deployed copy is discarded by the next sync. It shall
  read `~/.claude/skills/synced/` and shall never write to it: that folder is a
  cache of the user's claude.ai account, so a fix landed there reaches neither
  the account nor a source tree and is reported as a fix that held.
- [VERSION-34] Each declared target shall carry the user's recorded disposition
  for a finding in it — summarized, drafted for filing, or fixed in place — and
  shipshape shall act on that rather than deciding per run. `summarize` shall be
  the disposition that presumes nothing and the one a target defaults to.
- [VERSION-35] The built-in guide shall read the changelog from its raw URL,
  which needs no CLI and no credential. It shall read the first-party reference
  implementations an entry implicates through `gh`, which reaches arbitrary repo
  paths without a URL per file. Both need no configuration and reach any
  machine. A user who keeps a local checkout may put the pull in their own
  guide, where a machine-specific path belongs.
- [VERSION-36] Where no declaration has ever been recorded, the version skill
  shall take the user's configuration before reporting what changed, rather
  than opening with the changelog summary every configured path opens with. The
  summary describes a release against the artifacts a user maintains, and on a
  first run shipshape does not yet know what those are, so the report has
  nothing to be relevant to.
- [VERSION-37] While taking that configuration, shipshape shall ask about
  installed plugins in groups rather than one at a time, and shall record each
  answer as it arrives. A machine carries tens of plugins whose answer is
  uniform within a marketplace, and a run that resolves the whole set without
  writing it asks again at the next upgrade.
- [VERSION-38] Once that configuration is recorded, shipshape shall preview the
  run it produces — what an upgrade will read, and what it will do with a
  finding in each target — derived from the declaration rather than described
  in general terms, and shall then ask only whether the user wants to add
  anything. Where they do, shipshape shall write their input into the guide as
  imperative prose and show them the file path and the rewritten form before
  writing it.
- [VERSION-39] The version skill shall select the first run from the
  declaration's configured state as `--status` reports it, and where the
  declaration is present but unreadable the version hook shall report that state
  as unknown rather than as unconfigured. Every mode runs `--status` and no mode
  runs anything else first, so a signal absent from it is a signal the skill
  cannot act on; and an unreadable declaration read as an absent one starts a
  first run that asks again for every decision already recorded.
- [VERSION-40] shipshape shall reconcile the account-sync lane alongside the
  install manifest, reporting the synced skills it can name and the synced
  plugin rows it can count, and shall report a bucket file that does not parse
  as unreadable rather than as empty. Skills and plugins enabled on the user's
  claude.ai account carry no install-manifest row, so a pass over the manifest
  alone reads them as absent rather than as unexamined and reports full coverage
  having never seen them. A synced entry the user maintains shall be declarable
  under a bare key, since no manifest key can address it.
- [VERSION-41] Where the session's working directory is shipshape's own
  checkout, the built-in guide shall repair shipshape against what changed
  before it examines any other target, and where the repair is material it shall
  ask the user to restart with `--plugin-dir` before the rest of the pass runs.
  shipshape reads the changelog, the install manifest, the plugin cache and
  `~/.claude`, so a release that moves any of those leaves every later verdict
  reached with a stale map; and a plugin is loaded at session start, so the
  repair does not reach the running install on its own.

- [VERSION-42] Where the plugin data dir Claude Code hands the session is a
  `-inline` lane and the install manifest names exactly one marketplace the same
  plugin is installed from, shipshape shall read and write the version marker,
  the harness maintenance guide and the declaration in that installed plugin's lane
  instead. A plugin mounted with `--plugin-dir` gets a lane of its own, so the
  same machine at the same Claude Code version otherwise reads as one that has
  never run shipshape: the marker resets, the guide is absent, and an empty
  declaration selects the first run for decisions already on disk. Where the
  manifest names no marketplace, names more than one, or cannot be read,
  shipshape shall leave the session in its own lane and say why, since
  re-answering a question costs less than writing into a lane resolved from a
  guess.
- [VERSION-43] shipshape shall answer a reconciliation whatever order its inputs
  arrive in: a recorded checkout that has moved, or a marketplace manifest that
  does not parse, shall reach the report as the question it is even when it is
  the last row read. Both are read in loops whose exit status is the last thing
  they test, so the ordering decides between a reported question and a command
  that exits without output — and the silent exit is indistinguishable from a
  clean pass.

### GUIDE — The harness maintenance guide

- [GUIDE-01] shipshape shall keep the harness maintenance guide in the plugin
  data dir, where it survives plugin updates.
- [GUIDE-02] shipshape shall create the guide only once the user has answered
  the setup offer (GUIDE-07) or through a migration (GUIDE-06); reading the
  guide's path, state, or a section shall not create it. A seeded guide holds
  both headings and comments only, so both sections are unfilled.
- [GUIDE-03] shipshape shall read the guide by section: each half reads only its
  own, a `###` subheading stays inside its section, headings match regardless of
  case and trailing space, and stray text is reported on stderr and never
  carried out.
- [GUIDE-04] shipshape shall read a section's content with comments and leading
  blanks removed, and shall report an unclosed comment on stderr.
- [GUIDE-05] Where the session's data dir is a `--plugin-dir` inline lane,
  shipshape shall read the guide from the installed plugin's lane.
- [GUIDE-06] When the guide is read or seeded while it is absent and the older
  `on-claude-code-version-change.md` or `after-plugin-maintenance.md` holds
  content, shipshape shall write that content under the matching heading, with
  any `##` heading of its own demoted to `###` and any line naming
  `/plugin-maintenance` dropped, since the plugins section is what follows an
  upgrade. It shall then remove each older
  file it finds, and shall never overwrite
  a guide already present.
- [GUIDE-07] When a plugins run or a request about the guide finds it absent,
  shipshape shall offer to set up both sections, proposing a
  `/reload-plugins`-first refresh of the CLI installers the installed plugins
  ship where any exist, and shall write only the text the user approves. Where
  the user declines both, shipshape shall seed the guide, so the offer is not
  repeated.
- [GUIDE-08] When the user asks to see or change the guide, shipshape shall show
  the file raw, and edit it only after the user approves the drafted text.
- [GUIDE-09] When a plugins run updated, installed, or uninstalled a plugin,
  shipshape shall carry out the guide's plugins section in the order written,
  after releasing the maintenance lock.
- [GUIDE-10] Where a plugins run updated, installed, and uninstalled nothing,
  shipshape shall not carry out the plugins section.
- [GUIDE-11] Where a plugins-section step names a command Claude cannot invoke —
  a built-in such as `/reload-plugins`, or one marked
  `disable-model-invocation` — shipshape shall list it for the user in the
  section's order as the report's closing, with `/reload-plugins` appearing
  once.
- [GUIDE-12] shipshape shall list the CLI installers the installed plugins ship
  (`commands/install-*.md` and `skills/install-cli/SKILL.md` under each current
  `installPath`) as `/<plugin>:<name>`, so neither the setup offer nor a guide
  step derives them by hand.

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
- [REPORT-08] Once a shipshape skill has been invoked in a session, shipshape
  shall block every reply in that session that offers more work instead of doing
  it, and name the phrase it matched, so Claude rewrites the reply.
- [REPORT-09] Where a rewrite still matches, shipshape shall let the reply
  through and name the phrase to the user rather than block again, and a phrase
  quoted inside a code span or fence shall not count as an offer.
- [REPORT-10] shipshape shall end a run's reply with the steps the user takes,
  each given as the exact command in the order it must run, with no rationale
  attached and nothing after them.

## Future Requirements

_(none yet)_
