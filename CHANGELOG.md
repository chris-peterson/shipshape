# Changelog

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
