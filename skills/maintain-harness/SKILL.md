---
name: maintain-harness
description: "Bring your Claude Code harness current: handle a Claude Code version change (what's new, the instructions you wrote for an upgrade, and acknowledging it, which clears shipshape's banner), then reconcile installed plugins against enabledPlugins (update, install/uninstall to match, prune stale caches and orphan data dirs). Use when Claude Code upgraded, when updating, reconciling, or cleaning up plugins, or to see or set the guide of steps that runs after each."
argument-hint: "[all | claude-code | plugins | guide]"
hooks:
  Stop:
    - hooks:
        - type: command
          command: 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/offer-guard.sh"'
---

# Maintain harness
<!-- covers: REPORT-08 -->

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
bash "${CLAUDE_PLUGIN_ROOT}/scripts/maintenance-lock.sh" acquire
```

Exit 3 means another live session holds it, and its stderr names that session:
stop, and say a maintenance run is already active there. Run the same command
again at the start of each half; acquiring a lock this session holds refreshes
its age, so a long upgrade pass doesn't let it go stale.

Release it when the run's mutating work ends, on every exit path, including an
early stop: the plugins half releases it in its Step 6, and a `claude-code` run
releases it after its report.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/maintenance-lock.sh" release
```

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
