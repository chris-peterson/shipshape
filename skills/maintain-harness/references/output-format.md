# Output format: composition-first, scannable surfaces
<!-- covers: REPORT-01, REPORT-02, REPORT-03, REPORT-04 -->

Don't narrate the run as a scroll of per-plugin lines. Use three surfaces: an **inventory summary + plan table** up front, a **progress surface** (the native task list where the session offers it), and a **scannable final report** at the end. Both the opening summary and the closing report lead with the same composition line (installed / updating) and share one emoji vocabulary, so the run reads as one coherent thing.

Know what the terminal can and can't do, so this isn't cargo-culted: message text is **append-only**. A printed line can't be redrawn — there's no cursor control in rendered markdown — so a hand-typed progress bar or `- [ ]` checklist stacks a new copy each time it's posted. Where the session offers the harness task tools (`TaskCreate` / `TaskUpdate`), the task list is the **only** surface Claude can mutate after emitting it: it re-renders in place as items flip to `completed`, so it carries progress. Where the session doesn't offer them, a checklist re-posted as each item finishes carries it instead, at the cost of one copy per item (section 2). The tables are two separate renders (a plan, then its refresh), not one mutated in place.

## Emoji vocabulary

A shared emoji vocabulary ties the surfaces together — the same marker means the same thing in the plan and the final report, so a glance decodes it:

| Emoji | Meaning |
|-------|---------|
| ✅ | already current (no change) |
| ⬆️ | updated to a newer version |
| 🔄 | refreshed from source (HEAD-tracked, no version number) |
| ➕ | installed · 🗑️ uninstalled · ➖ removed by an update |
| ⏭️ | skipped (team-shared, shared on-disk install, or an origin that isn't a registered marketplace) |
| ☁️ | managed in claude.ai (a `<name>@synced` plugin, left to its account) |
| 🔒 | stale cache pinned by a live session (not pruned) · 🧹 pruned |
| ⚠️ | needs your judgment (orphan data dir, shared-install anomaly) |
| ⌨️ | needs your terminal (a marketplace-declared command only you can accept) |
| 🔧 | needs your fix (installed, but the settings file holding its enable does not load) |
| ⏸️ | held by the plugin's Claude Code version range (not updated, updated short of the newest, not installed, or not loaded) |

## 1. Inventory summary + plan table
<!-- covers: RECON-22 -->

Render after Step 1, before any update/install/uninstall runs.

Lead with a one-line **composition**: how many plugins are installed and how many the run updates. The run updates every managed plugin whether it's enabled or not, so the line doesn't split them by enabled state, and nothing else in the run does either. What it does name is an unmanaged plugin (plugins.md Step 1), which the run leaves alone, with its count and why:

```text
📦 30 installed · updating all 30
📦 31 installed · updating 30 · ☁️ 1 managed in claude.ai
```

Then a **plan table** — but only when there's a mix of actions worth previewing (installs, uninstalls, skips). When the only planned action is "update every plugin" (the common case), the composition line already says so — don't follow it with 30 identical `queued: update` rows. One row per plugin you'll act on, ordered by marketplace then plugin; the Status column carries the *planned* action:

```text
| Marketplace  | Plugin   | Version | Status            |
|--------------|----------|---------|-------------------|
| acme-tools   | tidydiff | 1.1.0   | ⬆️ queued: update |
| oss-registry | scmkit   | 1.2.0   | ⏭️ team-shared    |
| acme-tools   | gadget   | n/a     | ➕ queued: install? |
```

## 2. Progress
<!-- covers: REPORT-11 -->

During Steps 2-3, show progress on one of two surfaces, chosen once before Step 2 by reading the session's own tool list:

- **`TaskCreate` and `TaskUpdate` are offered**, either listed as tools or named as deferred tools to load: track work on the **native task list**.
- **They aren't offered**: post the same items as a markdown `- [ ]` checklist, and re-post it with the item checked each time a group finishes. Claude Code offers the task tools to a fixed list of model ids and withholds them from the rest unless `CLAUDE_CODE_ENABLE_TODO_TOOLS` is set, so a current model on a default install takes this branch.

Read the tool list; never call `TaskList` to see whether it errors. In a session without the tools, that error lands right under the skill's load line and reads to the user as shipshape being broken. Take the branch without saying which one, and don't stall on the absence.

Both branches build the same items from the *actual* work the Step-1 diff and Step-4 scan turn up — **one item per non-empty action group**, not a fixed pipeline of phases:

- `Update plugins` — whenever any plugin stays installed. This is the one task with **no count** in its label: `claude plugin update` has no dry-run, so you can't know which plugins actually have an update until you run the pass. Don't guess a number that overstates the work (`Update plugins (29)` when 27 are no-ops) — the real tally of updated-vs-current lands in the final report afterward. It's a single task, not one per plugin.
- `Uninstall N extras` — only if there are extras or unused dependencies to remove.
- `Install N missing` — only if the user confirmed missing installs.
- `Prune N stale/orphan caches` — only once the scan finds delete-eligible dirs (no live lease).

Don't create an item for an empty group — an instantly-completed `Reconcile: nothing to do` item is exactly the wall-of-no-ops this redesign removes. If that leaves **≤1 action group** — the common all-current run — skip the progress surface entirely; the composition line and final report already carry it (the task tool's own guidance is to skip it for trivial single-step work). On the task list, mark each task `in_progress` when its group starts and `completed` when it finishes; on a checklist, post it once before the first group and again as each group finishes. Step 2's updates run serialized (see Step 2), so the `Update plugins` item stays open across the whole pass and closes once at the end — progress is a status surface, not a per-plugin animation.

## 3. Final report

Render after Steps 2-3 finish. This is the authoritative result: an emoji-tagged status block, not prose paragraphs. It opens with the *same composition line* the run led with (so the reader who scrolled past the top still sees the run's scope here) and then reports each area — reconcile, updates, cache, data — as its own short line or table.

List **every plugin Step 2 updated on its own row** in the updates table. A maintenance report exists to let the reader confirm each plugin's result — "did my plugin get handled?" — and a collapsed count (`tidydiff +5`, `13 others`) hides exactly the names they came to check, forcing a re-run of `claude plugin list`. Completeness wins over brevity here: one row per plugin, ordered by marketplace then plugin. Show the table on every run, an all-current one included. The Version column shows the current version, a `from → to` transition for a plugin that moved, or `n/a` for a HEAD-tracked plugin with no version number; the Result column carries the emoji-tagged outcome. A large plugin set produces a long table — that's the intended trade.

<!-- covers: REPORT-14 -->
The **Last updated** column is the age `plugin-last-updated.sh` printed for the plugin's key (plugins.md Step 2), copied as printed. With marketplace auto-update on, a plugin is usually updated before the run reaches it, so most rows read ✅ current; the age is what separates one that moved an hour ago from one that hasn't moved in months. A row with no manifest record behind it (uninstalled, removed by an update, not installed, unmanaged) reads `-`. Where the script exited non-zero, leave the column out, and put its stderr line under the table.

<!-- covers: RECON-16 -->
A plugin `plugin-unmanaged.sh` lists (Step 1) gets its row too, with its origin in the Marketplace column, so the reader can see it was left alone and why. A `synced` row reads `☁️ managed in claude.ai`; any other origin reads `⏭️ not a registered marketplace`:

```text
| synced       | helper     | 2.0.0   | -            | ☁️ managed in claude.ai |
```

<!-- covers: RECON-18 -->
An unused dependency the reconcile uninstalled (plugins.md Step 3) reads `🗑️ uninstalled (unused dependency)`, so the reader can tell it from an extra they removed from `enabledPlugins` themselves:

```text
| acme-tools   | helperlib  | 1.0.0   | -            | 🗑️ uninstalled (unused dependency) |
```

<!-- covers: RECON-19 -->
A plugin an update installed as a new dependency (plugins.md Step 2) reads `➕ installed (dependency)`, so the reader sees a plugin they never asked for and where it came from. One the update pass removed reads `➖ removed by an update`:

```text
| acme-tools   | helperlib  | 1.0.0   | just now     | ➕ installed (dependency) |
| acme-tools   | oldlib     | 0.9.0   | -            | ➖ removed by an update |
```

<!-- covers: RECON-17 -->
An install whose output names a settings file that does not load (plugins.md Step 3) reads `🔧 not enabled`, with the file and the reason Claude Code gave in parentheses:

```text
| acme-tools   | gadget     | 1.0.0   | just now     | 🔧 not enabled: ~/.claude/settings.json does not load (its "cleanupPeriodDays" is not valid) |
```

<!-- covers: RECON-20 -->
A plugin its Claude Code version range held back (plugins.md Steps 1-3) reads ⏸️ with the range Claude Code gave, so the reader can tell a plugin that is current from one that can't move or isn't running:

```text
| acme-tools   | tidydiff   | 1.1.0           | 5w ago       | ⏸️ held: 1.2.0 needs Claude Code >=9.9.0 |
| acme-tools   | difflens   | 0.14.0 → 0.15.0 | just now     | ⬆️ updated, ⏸️ held below 0.16.0 (needs Claude Code >=9.9.0) |
| acme-tools   | gadget     | 1.0.0           | -            | ⏸️ not installed: needs Claude Code >=9.9.0 |
| acme-tools   | notekeep   | 0.3.0           | 2mo ago      | ⏸️ not loaded: needs Claude Code >=9.9.0 |
```

<!-- covers: RECON-21 -->
An update or install whose output plugins.md doesn't name reads ⚠️ with the line Claude Code printed, never ✅:

```text
| acme-tools   | trailhead  | 0.9.0   | 3d ago       | ⚠️ "<the line Claude Code printed>" |
```

```text
### Plugin maintenance

📦 9 installed · updating all 9
🔁 Reconcile — nothing to install or uninstall; every plugin matches its desired state.

**Updates**
| Marketplace  | Plugin     | Version | Last updated | Result       |
|--------------|------------|---------|--------------|--------------|
| acme-tools   | difflens   | 0.15.0  | 6h ago       | ✅ current   |
| acme-tools   | notekeep   | 0.3.0   | 3mo ago      | ✅ current   |
| acme-tools   | speccraft  | 0.4.0   | 2d ago       | ✅ current   |
| acme-tools   | tidydiff   | 1.1.0   | 5w ago       | ✅ current   |
| acme-tools   | trailhead  | 0.9.0   | 1d ago       | ✅ current   |
| acme-tools   | tuneup     | 0.4.3   | 1y ago       | ✅ current   |
| oss-registry | browserkit | n/a     | 9d ago       | 🔄 refreshed |
| oss-registry | devkit     | n/a     | just now     | 🔄 refreshed |
| oss-registry | uikit      | n/a     | 4d ago       | 🔄 refreshed |

🔒 Cache — 23 stale dirs (~166M) pinned by live sessions; 🧹 0 pruned (they free up as those sessions exit).
```

(No data line here — there were no genuine orphan data dirs. `-inline` dirs, if present, are silently ignored.)

When plugins actually changed, the movers show their version transition in the same table — no separate treatment, no collapsing the unchanged into a count. The table reads as the plan, refreshed:

```text
**Updates**
| Marketplace  | Plugin     | Version         | Last updated | Result       |
|--------------|------------|-----------------|--------------|--------------|
| acme-tools   | difflens   | 0.14.0 → 0.15.0 | just now     | ⬆️ updated   |
| acme-tools   | tidydiff   | 1.1.0           | 5w ago       | ✅ current   |
| acme-tools   | trailhead  | 0.8.0 → 0.9.0   | just now     | ⬆️ updated   |
| oss-registry | devkit     | n/a             | 9d ago       | 🔄 refreshed |
| oss-registry | uikit      | n/a             | 4d ago       | 🔄 refreshed |
```

<!-- covers: REPORT-10 -->
Close with **what the run changed**, then **what the user does**, and end the
reply there. The changes table is SKILL.md's **Close the run**, and it goes
after Step 7, which can write too. Anything after the steps buries them, so the closing is the last
thing in the reply.

Each step is the exact command, with no reason attached. The user acts on the
list and reads past any explanation, so a step that needs a sentence to justify
it costs them the step. When anything changed on disk, the step is
`/reload-plugins`. When nothing changed, the closing is one line saying no reload
is needed. If nothing changed at all (no updates, installs, uninstalls or
prunes), the report is the composition line, the Updates table, and that
closing line.

```text
Run /reload-plugins here and in your other sessions.
```

A 🔧 row puts a numbered list ahead of the reload: fixing the file, which is
the one step that isn't a command and names the file with Claude Code's reason,
then `claude plugin enable <plugin>@<marketplace>` for each plugin the desired
set enables whose enable didn't land in it. A plugin set `false` in
`enabledPlugins` gets no enable step. A reload before the fix loads the same ignored file.

```text
Run these, in order:
1. Fix ~/.claude/settings.json: its "cleanupPeriodDays" is not valid
2. /reload-plugins, here and in your other sessions
```

A ⏸️ row whose message said `Run \`claude update\`` puts `claude update` in
the same numbered list, once however many rows asked for it, after any file fix
and before the reload: the plugins it held move only on a later run, under the
newer Claude Code.

<!-- covers: GUIDE-11 -->
When the guide's plugins section (Step 7) leaves commands only the user can type,
the closing is one numbered list of exact commands, in the order they must run,
with `/reload-plugins` appearing once and ahead of every plugin's installer,
since an installer runs whichever version the session has loaded:

```text
Run these, in order:
1. /reload-plugins, here and in your other sessions
2. /foo:install-foo
3. /bar:install-bar
```
