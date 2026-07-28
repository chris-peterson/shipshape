# Output format: composition-first, scannable surfaces

Don't narrate the run as a scroll of per-plugin lines. Use three surfaces: an **inventory summary + plan table** up front, the **native task list** for progress, and a **scannable final report** at the end. Both the opening summary and the closing report lead with the same composition line (installed / enabled / disabled) and share one emoji vocabulary, so the run reads as one coherent thing.

Know what the terminal can and can't do, so this isn't cargo-culted: message text is **append-only**. A printed line can't be redrawn — there's no cursor control in rendered markdown — so a hand-typed progress bar or `- [ ]` checklist just stacks copies and scrolls *worse*. The **only** surface Claude can mutate after emitting it is the harness task list (`TaskCreate` / `TaskUpdate`), which re-renders in place as items flip to `completed`. That's what carries progress; the tables are two separate renders (a plan, then its refresh), not one mutated in place.

## Emoji vocabulary

A shared emoji vocabulary ties the surfaces together — the same marker means the same thing in the plan and the final report, so a glance decodes it:

| Emoji | Meaning |
|-------|---------|
| ✅ | already current (no change) |
| ⬆️ | updated to a newer version |
| 🔄 | refreshed from source (HEAD-tracked, no version number) |
| ➕ | installed · 🗑️ uninstalled |
| 💤 | installed but **disabled** (a deliberate state, left as-is) |
| ⏭️ | skipped (team-shared, or shared on-disk install) |
| 🔒 | stale cache held by a live session (not pruned) · 🧹 pruned |
| 📌 | pinned to a local checkout (held out of update and prune) |
| ⚠️ | needs your judgment (orphan data dir, shared-install anomaly) |

Two different holds, two different markers: 🔒 is a cache dir a live session still has open, which frees itself when that session exits; 📌 is a plugin the user pinned to a local checkout with `scripts/pin-plugin`, which is held until they unpin. Keep "pinned" for the second sense only.

## 1. Inventory summary + plan table

Render after Step 1, before any update/install/uninstall runs.

Lead with a one-line **composition** so the enabled-vs-disabled split is declared up front, not revealed at the end. A disabled plugin is a deliberate state, not drift — the run leaves it alone, and the user should see that scope from the start:

```text
📦 30 installed · ✅ 17 enabled · 💤 13 disabled (1 team-shared) · reconciling the 17 enabled
```

Then a **plan table** — but only when there's a mix of actions worth previewing (installs, uninstalls, skips). When the only planned action is "update every enabled plugin" (the common case), the composition line already says so — don't follow it with 17 identical `queued: update` rows. One row per plugin you'll act on, ordered by marketplace then plugin; the Status column carries the *planned* action:

```text
| Marketplace  | Plugin   | Version | Status            |
|--------------|----------|---------|-------------------|
| acme-tools   | tidydiff | 1.1.0   | ⬆️ queued: update |
| oss-registry | scmkit   | 1.2.0   | ⏭️ team-shared    |
| acme-tools   | gadget   | —       | ➕ queued: install? |
```

## 2. Progress

During Steps 2-3, track work on the **native task list** via `TaskCreate` / `TaskUpdate`. Build the list from the *actual* work the Step-1 diff and Step-4 scan turn up — **one task per non-empty action group**, not a fixed pipeline of phases:

- `Update plugins` — whenever any plugin stays installed. This is the one task with **no count** in its label: `claude plugin update` has no dry-run, so you can't know which plugins actually have an update until you run the pass. Don't guess a number that overstates the work (`Update plugins (29)` when 27 are no-ops) — the real tally of updated-vs-current lands in the final report afterward. It's a single task, not one per plugin.
- `Uninstall N extras` — only if there are extras to remove.
- `Install N missing` — only if the user confirmed missing installs.
- `Prune N stale/orphan caches` — only once the scan finds delete-eligible dirs (no live lease).

Don't create a task for an empty group — an instantly-completed `Reconcile: nothing to do` task is exactly the wall-of-no-ops this redesign removes. If that leaves **≤1 action group** — the common all-current run — skip the task list entirely; the composition line and final report already carry it (the task tool's own guidance is to skip it for trivial single-step work). Mark each task `in_progress` when its group starts and `completed` when it finishes. Step 2's updates run serialized (see Step 2), so the `Update plugins` task stays `in_progress` across the whole pass and flips once at the end — the list is a live status surface, not a per-item animation.

## 3. Final report

Render after Steps 2-3 finish. This is the authoritative result: an emoji-tagged status block, not prose paragraphs. It opens with the *same composition line* the run led with (so the reader who scrolled past the top still sees the enabled/disabled split here) and then reports each area — reconcile, updates, cache, data — as its own short line or table.

List **every enabled plugin on its own row** in the updates table. A maintenance report exists to let the reader confirm each plugin's disposition — "did my plugin get handled?" — and a collapsed count (`tidydiff +5`, `13 others`) hides exactly the names they came to check, forcing a re-run of `claude plugin list`. Completeness wins over brevity here: one row per plugin, ordered by marketplace then plugin. The Version column shows the current version, a `from → to` transition for a plugin that moved, or `—` for a HEAD-tracked plugin with no version number; the Result column carries the emoji-tagged outcome. A large plugin set produces a long table — that's the intended trade.

```text
### Plugin maintenance

📦 22 installed · ✅ 9 enabled · 💤 13 disabled (1 team-shared)
🔁 Reconcile — nothing to install or uninstall; every plugin matches its desired state.

**Updates** (9 enabled)
| Marketplace  | Plugin     | Version | Result       |
|--------------|------------|---------|--------------|
| acme-tools   | tidydiff   | 1.1.0   | ✅ current   |
| acme-tools   | notekeep   | 0.3.0   | ✅ current   |
| acme-tools   | difflens   | 0.15.0  | ✅ current   |
| acme-tools   | speccraft  | 0.4.0   | ✅ current   |
| acme-tools   | tuneup     | 0.4.3   | ✅ current   |
| acme-tools   | trailhead  | 0.9.0   | ✅ current   |
| oss-registry | uikit      | —       | 🔄 refreshed |
| oss-registry | browserkit | —       | 🔄 refreshed |
| oss-registry | devkit     | —       | 🔄 refreshed |

🔒 Cache — 23 stale dirs (~166M) held by live sessions; 🧹 0 pruned (they free up as those sessions exit).
```

(No data line here — there were no genuine orphan data dirs. `-inline` dirs, if present, are silently ignored.)

When plugins actually changed, the movers show their version transition in the same table — no separate treatment, no collapsing the unchanged into a count. The table reads as the plan, refreshed:

```text
**Updates** (5 enabled)
| Marketplace  | Plugin     | Version         | Result       |
|--------------|------------|-----------------|--------------|
| acme-tools   | tidydiff   | 1.1.0           | ✅ current   |
| acme-tools   | difflens   | 0.14.0 → 0.15.0 | ⬆️ updated   |
| acme-tools   | trailhead  | 0.8.0 → 0.9.0   | ⬆️ updated   |
| oss-registry | uikit      | —               | 🔄 refreshed |
| oss-registry | devkit     | —               | 🔄 refreshed |
```

A plugin pinned to a local checkout gets a row like any other, marked 📌 with the checkout in place of a version — the point of the row is that the reader can see *why* it wasn't updated:

```text
| acme-tools   | tidydiff   | ~/src/tidydiff  | 📌 pinned    |
```

Close with the **one action the user takes** — `/reload-plugins` if anything changed on disk, or an explicit "nothing changed, no reload needed" if not. If nothing changed at all — no updates, no installs, no uninstalls, no prune — the report is just the composition line plus that one closing line; don't pad it.
