---
name: maintain-harness
description: "Bring your Claude Code harness current: handle a Claude Code version change (what's new, the instructions you wrote for an upgrade, and acknowledging it, which clears shipshape's banner), then reconcile installed plugins against enabledPlugins (update, install/uninstall to match, prune stale caches and orphan data dirs). Use when Claude Code upgraded, when updating, reconciling, or cleaning up plugins, or to see or set the guide of steps that runs after each."
argument-hint: "[all | claude-code | plugins | guide]"
disable-model-invocation: true
hooks:
  Stop:
    - hooks:
        - type: command
          command: 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/offer-guard.sh"'
---

# Maintain harness
<!-- covers: REPORT-08, HARNESS-07 -->

shipshape keeps two things current: Claude Code itself, and the user's plugins.
Each is one half of this skill, kept in its own reference so a run loads only the
half it does.

## Resolved paths

Claude Code fills in these two for the install that's running when this skill
loads. The references are read as plain files, so their commands still carry the
literal `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_DATA}`. Replace each with
the value here before running it:

```text
CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA}
```

## Take the maintenance lock
<!-- covers: HARNESS-06 -->

One run at a time, across sessions: both halves write shared state (the plugin
manifest and caches, the acknowledged version, the guide, the user's repos).
Take the lock before either half:

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash "${CLAUDE_PLUGIN_ROOT}/scripts/maintenance-lock.sh" acquire
```

Exit 3 means another live session holds it, and its stderr names that session:
stop, and say a maintenance run is already active there. Run the same command
again at the start of each half; acquiring a lock this session holds refreshes
its age, so a long upgrade pass doesn't let it go stale.

Release it when the run's mutating work ends, on every exit path, including an
early stop: the plugins half releases it in its Step 6, and a `claude-code` run
releases it after its report.

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash "${CLAUDE_PLUGIN_ROOT}/scripts/maintenance-lock.sh" release
```

## Track what the run changes
<!-- covers: REPORT-12, REPORT-13 -->

The run ends by listing every path it changed, so the user knows when they're
done. Their other sessions work in the same checkouts, so `git status` can't say
which changes are this run's. Snapshot a repo before the run's first write to it:

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-changes.sh" start <repo>...
```

- **Acknowledging an upgrade:** every target `src` that `version-scan-targets.sh
  --drift` lists, before the built-in guide's repair step, then each repo a step
  of the user's guide writes to that isn't one of them, before that step.
- **A step of the guide's plugins section:** each repo it writes to, before the
  step.

A repeated `start` keeps a repo's first snapshot, so there's no need to track
which repos are already in. A dir that isn't a git work tree gets a row saying
its changes weren't tracked.

## Close the run
<!-- covers: REPORT-10, REPORT-12 -->

A run closes once, after its last half: under `all`, after the plugins half's
report. Close with the changes, then the steps the user takes, and nothing after
them.

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-changes.sh" report
```

It prints `<repo>|<path>|<state>|<before>` per changed path and a `#totals` line.
Render one table that also carries what the run changed outside a repo: the
issues it filed, the version it recorded, the guide if it was edited, and the
caches it pruned. A plugin the run updated, installed, or uninstalled already has
its row in the Updates table, so here it gets one count row.

```text
**Changed this run**
| Where | Path | State |
|---|---|---|
| ~/src/acme-widgets | `src/foo.md` | uncommitted (modified) |
| ~/src/acme-widgets | `src/bar.md` | uncommitted (modified), already had other changes |
| ~/src/acme-tools | `hooks/x.sh` | committed abc1234 |
| [acme/widgets#12](<issue-url>) | <issue title> | filed |
| shipshape | `<CLAUDE_PLUGIN_DATA>/acknowledged-version` | recorded 1.2.3 |
| plugin cache | 15 stale version dirs | pruned (59M) |
| plugins | 2 updated, 1 uninstalled | see Updates |
```

| `state` | Row |
|---|---|
| `modified`, `added`, `deleted`, `renamed`, `untracked` | `uncommitted (<state>)` |
| `committed <sha>` | `committed <sha>` |
| `restored` | `restored to HEAD` |
| `not-a-repo` | `not tracked: not a git work tree` |

`before` of `dirty` appends "already had other changes": the user reviews that
file knowing part of its diff is someone else's. Where `report` exits 1, say the
list couldn't be produced and quote its stderr line, rather than rebuilding it
from memory. When nothing changed anywhere, the section is one line:
`Changed this run: nothing.`

Then the steps, per the half that closed: output-format.md's closing for the
plugins half, or `Nothing left to run.` when there are none.

## Pick the half
<!-- covers: HARNESS-01, HARNESS-02, HARNESS-03 -->

The first word of the argument picks what runs. Anything after it, and a request
phrased in prose, picks the mode inside that half.

| Argument | Runs |
|---|---|
| *(none)*, `all` | Claude Code, then plugins |
| `claude-code`, `cc` | [references/claude-code.md](references/claude-code.md) |
| `plugins` | [references/plugins.md](references/plugins.md) |
| `guide` | [references/guide.md](references/guide.md): show, change, or set up the user's guide |

Where there's no argument, a request that names only one half ("what changed
in 2.1.300", "prune my plugin caches") runs that half alone, and one about the
user's own steps ("show my guide", "what runs after maintenance") is `guide`.

## All
<!-- covers: HARNESS-02, HARNESS-04 -->

Run `--status` from the Claude Code half first.

- **`pending` is true:** run the Claude Code half in full: the what-changed
  walk, the acknowledge question, and on acknowledge, the guide and the
  recording. On **Ask me again later**, the version stays pending and the plugins
  half still runs.
- **`pending` is false:** give the one status line and go straight to plugins.
  There's no upgrade to walk, and the guide runs only on one.

Then run the plugins half in full. Its report comes last, so the run ends on the
action the user takes, which is usually `/reload-plugins`.

## A guide step that names plugin maintenance
<!-- covers: HARNESS-05 -->

The guide's upgrade section can name `/maintain-harness plugins`, which is the
plugins half. Under
`claude-code`, carry it out where the guide puts it, by reading
[references/plugins.md](references/plugins.md). Under `all`, the plugins half
that follows is that step, so it runs once, after the Claude Code half.
