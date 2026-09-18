# The deep-scan set: who maintains it decides who analyzes it
<!-- covers: VERSION-27, VERSION-28, VERSION-36, VERSION-42 -->

A plugin the user **maintains** is theirs to patch when a Claude Code release
invalidates a hook schema, a settings key, or a frontmatter field. A plugin they
merely **use** is its own maintainer's errand — analyzing it produces a finding
nobody in the room can act on, at the same cost as a finding they can.

Nothing on disk tells the two apart: both are installed, both have a source repo
in their marketplace's manifest, and both have a version cache. So the set is
declared once and reconciled against the install manifest after that. The
declaration lives in shipshape's data dir, keyed by install-manifest key
(`<plugin>@<marketplace>`), which is what makes drift exact.

The manifest is the reconciliation's floor, not its ceiling — see [the
account-sync lane](#the-account-sync-lane) for what it does not name.

## Reconcile, then ask about the difference

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --drift
```

| Bucket | What it means | What to do |
|---|---|---|
| `new` | installed, no decision on record | ask: maintained, or theirs? Anything but `skip` needs the local checkout's path |
| `gone` | decided, no longer installed | offer `--forget <key>` |
| `unreadable` | examined, but the recorded path is not a directory | ask for the new path; never examine nothing and report a pass |
| `targets` | the examined set, each row carrying its `action` | hand these to the fan-out, grouped by `src` |
| `skip` | left to its own maintainer | don't examine, and don't report |
| `synced` | the account-sync lane, which no install manifest names | see below |

`settled: true` means every bucket that asks a question is empty — use
`targets`' rows and say nothing about the reconciliation. Otherwise ask, one
**AskUserQuestion** per outstanding plugin, and record each answer as it comes:

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --set <key> <action> <path>
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --set <key> skip
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --forget <key>
```

The action is the user's standing answer to *what happens to a finding here*,
which is why it is recorded per target rather than decided per run:

| `action` | Ask it as | Finding becomes |
|---|---|---|
| `summarize` | "just tell me" | a line in the report. **Recommend this for a new target** — it presumes nothing. |
| `issue` | "file it" | a draft offered to `/anchor:issue` with the set |
| `edit` | "fix it in place" | a direct edit in that repo, left in the working tree to review |
| `skip` | "not mine" | nothing; the target is never examined |

`skip` takes no path, and passing one is refused: a target nobody examines has
no use for a checkout, and storing one invites a later run to read it.

Recording each answer as it arrives is what keeps the question to once per
plugin. A run that resolves the set and doesn't write it asks again next upgrade,
which is the friction the declaration exists to remove.

## The account-sync lane

Claude Code writes the skills and plugins enabled on the user's claude.ai
account into `~/.claude/skills/synced/<bucket>/` and
`~/.claude/plugins/synced/<bucket>/`, gated by the `syncClaudeAiSkills` and
`syncClaudeAiPlugins` settings keys. They carry no install-manifest row, so the
manifest reads them as absent rather than as unexamined — and a pass over the
manifest alone reports full coverage having never seen them.

`--drift`'s `synced` bucket is what closes that gap:

```json
"synced": { "skills": ["pdf", "xlsx"], "plugins": 2, "unreadable": [] }
```

Skills are named, because their manifest names them. Plugins are counted,
because the bucket's rows carry fields the script does not read. `unreadable`
holds a bucket file that exists and does not parse — never read as empty.

A synced entry the user **maintains** goes in under a bare key, the same way a
build tool does, since no manifest key can address it:

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --set <name> edit <path>
```

Ask once, when a synced entry has no decision on record and the lane is
non-empty, then record the answer so the next upgrade doesn't ask again. A
synced entry nobody maintains needs no row and no mention.

Editing a synced skill in place is never the fix: the folder is a cache of the
account, so a change there reaches neither the account nor a source tree and the
next sync overwrites it. Detect staleness there, land the fix in the source, and
where there is no source say the change has to be made on claude.ai.

## The scan unit is the repo, not the plugin

Two plugins can share one source repo — one repo publishing several plugins is
ordinary — so group `targets`' rows by `src` before fanning out. Analyzing a repo
twice doubles the work and splits its verdicts across two reports.

## A repo that ships as no plugin still belongs here

The install manifest names what the user installed, which leaves out the tooling
that builds, lints, or releases those plugins. That tooling reads the same CLI
and the same schemas and goes stale the same way, and no manifest will ever name
it. It goes in under a bare key:

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --set shipyard edit <path>
```

Bare keys are never reported as `gone`, since no install manifest can vouch for
them. When a finding in a maintained plugin points at one of these tools, offer
to add it — that is the moment the gap is visible, and the next upgrade misses it
again otherwise.
