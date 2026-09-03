# The deep-scan set: who maintains it decides who analyzes it
<!-- covers: VERSION-27, VERSION-28 -->

A plugin the user **maintains** is theirs to patch when a Claude Code release
invalidates a hook schema, a settings key, or a frontmatter field. A plugin they
merely **use** is its own maintainer's errand — analyzing it produces a finding
nobody in the room can act on, at the same cost as a finding they can.

Nothing on disk tells the two apart: both are installed, both have a source repo
in their marketplace's manifest, and both have a version cache. So the set is
declared once and reconciled against the install manifest after that. The
declaration lives in shipshape's data dir, keyed by install-manifest key
(`<plugin>@<marketplace>`), which is what makes drift exact.

## Reconcile, then ask about the difference

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --drift
```

| Bucket | What it means | What to do |
|---|---|---|
| `new` | installed, no decision on record | ask: maintained, or theirs? A `scan` needs the local checkout's path |
| `gone` | decided, no longer installed | offer `--forget <key>` |
| `unreadable` | decided `scan`, the recorded path is not a directory | ask for the new path; never scan nothing and report a scan |
| `scan` | the deep-scan set | hand these paths to the fan-out |
| `skip` | left to its own maintainer | report as a count, don't examine |

`settled: true` means every bucket that asks a question is empty — use `scan`'s
rows and say nothing about the reconciliation. Otherwise ask, one
**AskUserQuestion** per outstanding plugin, and record each answer as it comes:

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --set <key> scan <path>
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --set <key> skip
```

Recording each answer as it arrives is what keeps the question to once per
plugin. A run that resolves the set and doesn't write it asks again next upgrade,
which is the friction the declaration exists to remove.

## The scan unit is the repo, not the plugin

Two plugins can share one source repo — one repo publishing several plugins is
ordinary — so group `scan`'s rows by `src` before fanning out. Analyzing a repo
twice doubles the work and splits its verdicts across two reports.

## A repo that ships as no plugin still belongs here

The install manifest names what the user installed, which leaves out the tooling
that builds, lints, or releases those plugins. That tooling reads the same CLI
and the same schemas and goes stale the same way, and no manifest will ever name
it. It goes in under a bare key:

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --set shipyard scan <path>
```

Bare keys are never reported as `gone`, since no install manifest can vouch for
them. When a finding in a maintained plugin points at one of these tools, offer
to add it — that is the moment the gap is visible, and the next upgrade misses it
again otherwise.
