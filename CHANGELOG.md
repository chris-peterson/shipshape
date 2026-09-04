# Changelog

## 0.11.1

### Fixed

- **`/claude-code-version` tells a first run from a configured machine.** It now reads whether you have a declaration, and how many repos it examines and skips, so a machine you have already configured isn't walked back through the setup questions. A declaration that is on disk but unreadable reads as unknown rather than missing, so a corrupt file can't restart them either.

## 0.11.0

### Added

- **shipshape now includes a default guide.** Acknowledging used to carry out your version-change document and nothing else, so with none written an upgrade only cleared a banner. The built-in guide runs every time: it reads every changelog entry and the first-party examples they implicate, checks your `~/.claude` rules, skills, hooks and settings, and works through the repos you've declared. Your own guide adds to it instead of replacing it, so yours can shrink to the part only your machine knows.
- **The first run asks what it needs, then shows you what it will do.** `/claude-code-version` on an unconfigured machine walks your installed plugins a repo owner at a time — one question each, not one per plugin — finds each checkout itself and asks you to confirm it rather than asking for a path, then previews the run your answers produce before asking whether anything is missing.
- Each declared target carries **what should happen to a finding in it**: fix it in place, write it up so you can file it, or just report it. Where a repo you have set to fix-in-place deploys into `~/.claude`, the fix goes to the repo — one written into the deployed copy is discarded the next time your sync runs.

### Changed

- A version-change guide run reports the outcome of each step rather than every command it took to get there. A multi-step guide used to arrive as thirty greps and directory listings surfaced one at a time, with the handful of results you could act on buried among them.
- A file the run writes for its own bookkeeping goes to a scratch path, never into a repo your guide names. Where your guide asks for a document and doesn't say where, it lands in scratch with its path reported, rather than untracked at the root of a repo you share with your other sessions. A path your guide does name is still honored.

## 0.10.0

### Added

- `/claude-code-version` asks once which of your plugins you **maintain**, and analyzes only those when your version-change guide calls for a pass over them. A plugin you only use is its own maintainer's errand, reported as a count rather than examined. Your answers are recorded, so later upgrades ask only about a plugin you've since installed or removed, or a source checkout that has moved. A repo that ships as no plugin — the tool that builds them, your rules repo — goes in under a name you pick, since no install manifest will ever name it.

### Changed

- Acknowledging an upgrade accounts for every changelog entry between the version you acknowledged and the one you're running, each with a line saying whether it touches your artifacts. The one-screen summary still leads, so the decision in front of you stays short; behind it, nothing goes unread — your guide runs against what changed, and an entry nobody read is an artifact nobody checked.
- A guide step that fans out over several repos comes back with one verdict per candidate, anchored at the file and line that establishes or disproves it, and the report carries the count. Findings arrive together rather than one at a time, because the decision is which of them to act on.
- The changelog walk reads the whole file, preferring a local checkout of `anthropics/claude-code` where you have one, rather than the single release the status URL anchors at.

### Other

- The docs site sidebar names each skill by what you type — `/plugin-maintenance` and `/claude-code-version`.
- Local and CI builds run the same projection, so a preview renders the site that deploys.

## 0.9.1

### Changed

- `/claude-code-version` answers a step of your version-change guide that asks for findings by checking the code the step names, rather than by writing down what the changelog implies, and fans out over independent targets in parallel. The version is recorded once every step has landed a result you can act on.

### Other

- The docs site favicon is a red ship's wheel with a green hub.

## 0.9.0

### Added

- `/plugin-maintenance` reclaims a `cache/<marketplace>/<plugin>/` directory once its last version has been pruned.

### Changed

- Pruning runs from scripts shipped with the plugin. A maintenance run no longer writes a throwaway delete script, no longer stops to ask permission to run it, and removes only what one of your registered marketplaces put there; a plugin you synced from claude.ai is reported and left alone.
- `/claude-code-version` closes with a two-option question, acknowledge and run your guide or leave it pending, where it used to close with a sentence offering to. Where your guide is filled in, up to three lines above the question say what acknowledging will run.

### Fixed

- Two maintenance runs can no longer reconcile at once. A lock whose age could not be read counted as decades stale, so a second run stole a lock the first had just taken and both proceeded against the same install manifest and caches.
- A half-written `.in_use` lease no longer costs a live session its plugin. A lease the prune could not parse read as no lease at all, and the cache directory another session was running from was deleted.

## 0.8.0

### Fixed

- A plugin whose install or update needs a command only you can accept — a marketplace's `headersHelper`, which mints the headers for the plugin's archive fetch, or a `command` source, which prints the plugin directory — now comes back as ⌨️ **needs your terminal**, quoting the line to run in your own shell. `/plugin-maintenance` used to read that refusal as a transient failure and retry it, which printed the same warning and left the plugin neither installed nor updated. Passing `-y` doesn't reach it either: Claude Code ignores the flag inside a session.

### Other

- The `/plugin-maintenance` skill and its output-format reference each state the output model once, so the emoji vocabulary and the report layout have a single home. `AGENTS.md` points at `SPEC.md` for the glossary rather than restating it.

## 0.7.0

### Added

- `/claude-code-version` opens with what changed on every path but the guide. Acknowledging an upgrade now summarizes the release before it runs your instructions and clears the banner, so what a version holds reaches you whether or not you think to ask for it.

### Changed

- The what's-new summary is one screen: the handful of items you'd act on, one line each with the version each landed in, and the per-release walk on request rather than printed by default.
- The docs and the version hook describe Claude Code's self-update as it works. The update installs in the background while a session runs, and the new version takes effect at your next launch.

## 0.6.0

### Fixed

- Running `/plugin-maintenance` no longer destroys a plugin's data directory. Uninstalling from a plugin's last scope deletes `${CLAUDE_PLUGIN_DATA}` by default, and the reconcile was doing that in its uninstall step, ahead of the confirmation meant to ask you first. Uninstalls now pass `--keep-data`, so accumulated state survives to be reported and you decide whether it goes.
- `/plugin-maintenance` tells you to rerun `/reload-plugins --force` when a reload warns and skips over the prompt cache, so a reconcile can no longer read as applied while nothing was reloaded.
- The auto-update report reads your registered marketplaces from `known_marketplaces.json`. A marketplace with no settings entry now shows as not yet armed, where it used to show as nothing at all.
- The docs site said plugins update in parallel. They update one at a time, which is what keeps two plugins from the same marketplace colliding over its clone.
- The docs site said an uninstall leaves cache and data directories behind. Claude Code deletes the data directory as part of the uninstall and sweeps a superseded version cache about 14 days later, so what shipshape changes is the timing.

### Changed

- Your version-change guide runs when you acknowledge an upgrade through `/claude-code-version`, not automatically at the first session start after one. 0.5.0's notes described the earlier behavior. The banner still repeats every session until you acknowledge it.
- The docs site reaches its own pages: the two skills, the hooks, the spec, and the coverage ledger are in the sidebar, and the home page carries the version and the skill listing. Its in-page links resolve, and the example transcripts show figures from real runs.

### Added

- `/claude-code-version` handles a Claude Code version change in one place: read or write the instructions you want run on an upgrade, walk the changelog entries between the version you acknowledged and the one you're running, or acknowledge, which runs your instructions and clears the banner.

### Other

- Local `just docs` and `just check` builds were pinned to a stale generator, so a preview rendered a different site than the one deployed. Contributors now build with the same version CI does.
- Each requirement in `SPEC.md` is anchored at the code that implements it with a `covers:` marker, so `STATUS.md` cites the file and a grep finds the spot.

## 0.5.0

### Added
- shipshape now tells you when **Claude Code itself** changed version, and runs whatever you want done about it. A new `SessionStart` hook opens the session with one line naming both versions and linking that release's changelog entry (`Claude Code 2.1.226 → 2.1.227 · …#21227`). It repeats every session until you've acknowledged it, so an update can't scroll past unread in a session you opened for something else — and acknowledging it in conversation, asking what changed, or reading the entry together is what clears it. There's nothing to type. Installing shipshape records the version you're already on, so the first session is quiet.
- On that same version change, Claude is handed a document you wrote about what to do next. Your rules, skills, hooks, and plugin manifests were written against a particular Claude Code, and an upgrade can quietly invalidate a hook event's schema, a settings key, or a frontmatter field. Write the commands you want run into `~/.claude/plugins/data/shipshape-<marketplace>/on-claude-code-version-change.md` (it's created for you, and one holding only comments runs nothing) and they're carried out at the top of the first session after an upgrade. The document reaches Claude as you wrote it, so it can carry the reasoning for a step, not just the command. Silence the whole thing with `SHIPSHAPE_VERSION_NOTICE=off` in the `env` block of `~/.claude/settings.json`.

### Changed
- The docs site now carries shipshape's requirements at [`/spec`](https://chris-peterson.github.io/shipshape/#/spec), backed by a new `SPEC.md` written in [EARS syntax](https://alistairmavin.com/ears) and a `STATUS.md` recording where each of the 56 requirements is implemented. If you want to know what shipshape promises about pruning a cache a live session still holds, or when it refuses to uninstall something, that's now written down rather than inferred from the skill prompt.
- The maintenance report's worked examples use invented marketplace and plugin names, so nothing in the documentation reads as a real plugin being flagged as an orphan.

### Other
- Build tooling moved to [shipyard](https://github.com/chris-peterson/shipyard): `plugin.json`, the hook registration, and most of the docs site are generated from `plugin.yml` and `hooks/hooks.yml`, and a preview gate on every PR shows the pending projection. For contributors this replaces the hand-maintained artifacts and the pre-commit hook — edit the source, run `just generate`.
- Contributor conventions moved into `AGENTS.md` (the same file the agents read), with `CLAUDE.md` pointing at it.

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
