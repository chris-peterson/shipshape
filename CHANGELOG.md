# Changelog

## 0.4.4

### Changed
- The `plugin-maintenance` final report now lists **every enabled plugin on its own row** — name, version (or a `from → to` transition for a plugin that moved), and result — rather than collapsing a marketplace's unnamed remainder into a count (`beacon +5`) or a block of unchanged plugins into `13 others`. A maintenance report exists to let the reader confirm each plugin's disposition; a collapsed count defeated that, forcing a re-run of `claude plugin list` to answer "did my plugin get handled?". The composition line, emoji vocabulary, and reconcile/updates/cache/data structure are unchanged, and caches stay reported by exception. (#7)

## 0.4.3

### Changed
- The `plugin-maintenance` skill's output spec — the emoji vocabulary, the three surface layouts, and the worked examples — moved into a `references/output-format.md` companion. The procedure (Steps 0–6) now leads the file instead of sitting behind ~90 lines of formatting, and the two guardrails and the `.in_use` section no longer restate the scripts that own their logic.
- The skill description no longer advertises "Triggers on ..." phrases. With `disable-model-invocation` set, the skill is user-invoked only, so the description now reads as the `/plugin-maintenance` command it is rather than listing triggers that can never fire.

### Other
- The `SessionStart` hook is registered with an explicit `"matcher": "*"`, matching the documented convention.
- Documented the auto-update hook's "takes effect on the next launch" output line in the README, and added a hermetic test suite for `enforce-autoupdate.sh` — arm only a pending marketplace, preserve unrelated settings keys, no churn at steady state, and a conservative no-op when `jq` is absent.

## 0.4.2

### Changed
- `plugin-maintenance` now declares the enabled/disabled split up front. A composition line (installed · enabled · disabled) leads both the opening inventory and the closing report, so "enabled" is no longer introduced only at the end. A disabled plugin is framed as a deliberate state the run leaves alone, not drift.
- The final report is now a scannable, emoji-tagged status block (composition → reconcile → updates → cache → data) instead of prose, grouped and counted rather than one row per plugin. A shared emoji vocabulary ties the plan and the report together.

### Fixed
- `-inline` data dirs are no longer flagged for judgment on every run. They're benign artifacts of testing a plugin locally, not orphans — the skill now ignores them entirely.

## 0.4.1

### Fixed
- `plugin-maintenance` output no longer leaks internal dialog. The 0.4.0 render-surface redesign (plan table, task list, refreshed table) never governed the *voice* between the surfaces, so a run still narrated a preamble before every command and walked the user through its own `.in_use` investigation. The skill now adds a **Voice** section: do the reasoning silently, no per-tool-call preambles, no narrated investigation (report the conclusion in one line), stay in scope, and keep the final summary short.
- The `.in_use` guidance is now "act on the verdict, don't audit it" — an all-in-use run is normal (background spares and long-lived sessions pin the versions they loaded), not a cue to go verify `plugin-cache-in-use.sh` with ad-hoc `ps` calls. Pinned stale caches collapse to a one-line count instead of a who-holds-what roster.
- The update task label drops its plugin count. `Update plugins (N)` read as N updates when most were no-ops; since `claude plugin update` has no dry-run, the count can't be known up front, so the real updated-vs-current tally lands in the refreshed table instead.
- Dropped the "kept" adjective for plugins throughout — it implied the others were lesser; "Update plugins" reads the same without the ranking.

## 0.4.0

### Fixed
- `plugin-maintenance` no longer races on the shared plugin state that `claude plugin` mutates without locking (#2):
  - **Within a run** — updates were run in parallel, and plugins sharing a marketplace each re-cloned it concurrently, colliding (`destination path already exists`) so some updates failed with `Plugin not found` and were silently skipped. The skill now refreshes all marketplaces once up front (`claude plugin marketplace update`), then updates **serialized**, surfacing and retrying any failure instead of losing it in parallel output.
  - **Across runs** — a new advisory lock (`scripts/plugin-maintenance-lock.sh`, keyed on the Claude Code session) guards the whole reconcile. A second overlapping run bails instead of interleaving on the manifest and caches; a crashed run's lock self-clears once stale. Re-entrant within a session, mutually exclusive across.

### Other
- Added a hermetic test suite for the lock (`scripts/tests/plugin-maintenance-lock.test.sh`); `just test` now runs every `scripts/tests/*.test.sh`.

## 0.3.1

### Other
- Maintenance release — no functional changes. Cut to validate `release.yml` end-to-end after restoring the `MARKETPLACE_DISPATCH_TOKEN` repo secret, whose absence had failed the marketplace-dispatch step on the prior three releases (#5).

## 0.3.0

### Features
- The `plugin-maintenance` skill now presents its run as three stable surfaces instead of a scroll of per-plugin one-liners: a **plan table** up front (what will be updated/installed/removed), the **native task list** for progress (scoped to the action groups that actually have work), and a **refreshed table** at the end with outcomes and version transitions.

### Fixed
- The `.in_use` cache-lease check no longer risks pruning a version dir out from under a live session. It previously matched on PID alone, but the OS recycles PIDs — a dead session's PID handed to an unrelated process would false-positive as "in use" and wedge a stale cache forever. The check now also compares the lease's `procStart` against the running process's actual start time (tolerant of the UTC/local gap and of GNU vs BSD `date`), so recycled PIDs are correctly treated as dead and stale caches get pruned.
- The lease check is **conservative by construction**: a missing or unparseable `procStart`, or `jq` being absent, reports "in use" (with a loud stderr warning for the `jq` case) so uncertainty never prunes.

### Other
- Extracted the lease-liveness logic from skill prose into a real, testable artifact, `scripts/plugin-cache-in-use.sh`, invoked by the skill.
- Added a hermetic regression suite (`scripts/tests/plugin-cache-in-use.test.sh`, run via `just test`) covering the parse, PID-reuse, and conservative-safety paths.

## 0.2.2

### Other
- The `plugin-maintenance` skill is now marked `disable-model-invocation`, dropping its description from every session's always-resident context. Still available via `/`; Claude no longer auto-loads it.

## 0.2.1

### Other
- Trimmed the `plugin-maintenance` skill's `description` frontmatter to cut the always-resident context cost. Kept the "sync plugins" / "update my plugins" cues; dropped the name-echo and redundant trigger phrases.

## 0.2.0

### Features
- Plugin reconciliation now guards against uninstalling a plugin shared by two registered marketplaces. When `claude plugin list` shows two rows for one plugin but `installed_plugins.json` records a single shared install, the extra is skipped — surfaced with the manifest evidence for you to resolve — instead of being uninstalled and taking the enabled copy down with it. Real uninstalls are verified against the manifest afterward, since `claude plugin uninstall` reports success regardless of effect.

## 0.1.1

### Changed
- Sharpened the description ("all your AI plugins" → "your Claude Code plugins") and aligned the marketplace suite metadata with the bridge.ai schema: group slug, declared `activations`, and dropped the derived accent, the passive flag, and the spoke flag.

## 0.1.0

Initial entry.
