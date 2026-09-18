# The built-in guide: the errand every upgrade earns

<!-- covers: VERSION-27, VERSION-31, VERSION-34, VERSION-35, VERSION-36, VERSION-37, VERSION-43 -->

An upgrade invalidates artifacts whether or not the user has written a guide.
Their rules were written against a system prompt that has moved, their hooks
against an event payload that may have changed shape, their skill and plugin
frontmatter against fields the loader may now read differently. So the version
skill runs this pass on **every** acknowledged upgrade, and a written guide adds
steps to it rather than replacing it.

Nobody has to maintain a plugin for this to be worth running: the target that
is always present is the user's own `~/.claude`.

## 1. Read what changed

Walk every changelog entry between `acknowledged` and `current`, per the
[What changed](../SKILL.md#what-changed) section, which carries the read. A user
who keeps a local checkout can put the pull in their own guide, where a
machine-specific path belongs; the skill does not hold one.

**Read the first-party reference implementations the entries implicate.**
Anthropic ships its own worked examples, and one that now does something the
user's artifacts describe differently is the same staleness signal as a
changelog entry — often a stronger one, since a changelog line can omit a shape
change the example shows plainly. The repo carries docs and examples rather than
source, so most releases implicate nothing here; read only the paths an entry
actually points at, one `gh api` call each — `gh` reads arbitrary repo paths
without a URL per file, and needs no configuration to do it.

| Path | What a change there implicates |
|---|---|
| `plugins/` | plugin manifests, skill and command frontmatter, hook wiring |
| `examples/hooks/` | hook events, payload shape, exit-code contract |
| `examples/settings/` | settings keys, permission syntax |
| `examples/mdm/` | managed-settings profiles |
| `scripts/` | anything the CLI is driven by |

## 2. Repair shipshape first, when the session is in shipshape's own checkout

shipshape reads the changelog, the install manifest, the plugin cache and the
user's `~/.claude`, so a release that moves any of those leaves it scanning with
a stale map — and every verdict the rest of this guide produces was reached with
that map. Fixing it after the fan-out ratchets the wrong way: the findings are
already in hand, reached by the version that had the defect.

So when the working directory is shipshape's own repo, take the changelog to
shipshape before anything else, land the fixes there, and run `just test`. Its
disposition is `edit` by construction here — the checkout is open in front of
the user.

Where the change is material — a script the skill calls, a bucket it reads, a
step it runs — the running install is still the old one, since a plugin is
loaded at session start. Say so and ask the user to restart with
`claude --plugin-dir .` so the rest of the pass runs on the repaired version.
That is what makes the next upgrade start from a better place instead of
rediscovering the same gap.

Outside shipshape's checkout this step is not skipped so much as unavailable:
there is nothing to edit. Note what a finding in shipshape would be and carry it
into the report.

## 3. Check the user's own harness

`~/.claude` is the universal target. What is present varies, so read what is
there rather than assuming a layout:

| Artifact | Read for |
|---|---|
| `rules/` | claims about harness behavior that a release changed |
| `skills/` | frontmatter fields, invocation shape, bundled script paths |
| `hooks/` and `settings.json` | event names, payload fields, permission entries, config keys |
| `agents/`, `commands/` | frontmatter the loader reads |
| `plugins/*/`.claude-plugin/ | manifest fields |

**`~/.claude` may be a deployed copy.** Where a declared `edit` target's repo
deploys into it — a rules repo with a sync step, an artifacts monorepo — a fix
written into `~/.claude` is discarded the next time that sync runs, silently and
with nothing to recover from. So `~/.claude` is where staleness is **detected**;
the fix goes to whichever declared target owns the file. When a target is
declared `edit` and the user's own guide or its README says it deploys into
`~/.claude`, treat the repo as the source and `~/.claude` as its output.

**`~/.claude/skills/synced/` is someone else's.** It holds the skills enabled on
the user's claude.ai account, and Claude Code overwrites it from the account.
Read it for staleness like anything else; never write to it. A fix landed there
reaches neither the account nor a source tree, is discarded at the next sync,
and is reported as a fix that held — the failure the deployed-copy rule above
exists to prevent, one layer down. Where a synced skill is stale, say the change
has to be made on claude.ai.

## 4. Fan out over the declared targets

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --drift
```

`targets` is the set, each row carrying its own `action`. Group the rows by
`src` first — one repo can back several plugins, and analyzing it twice splits
its verdicts across two reports.

Where `settled` is false, resolve the question first: read
[deep-scan-set.md](deep-scan-set.md) for what each bucket means. A run does not
examine a target it could not read. `synced` is the one bucket `settled` does
not gate — it names what the install manifest cannot, and the same reference
says what to do with it.

Each target answers with the verdict contract from
[Acknowledge](../SKILL.md#acknowledge): one anchored verdict per candidate, no
hedges, counted in the report.

## 5. Act on each finding by its target's disposition

`action` is what happens to a finding, and it is the user's recorded preference
rather than a judgment to make per run:

| `action` | What to do with a finding |
|---|---|
| `summarize` | one line in the report: the file, the line, and what a fix would cost. Nothing is written. The default, because it presumes nothing. |
| `issue` | draft it for filing — title, a why-first body written for someone who has never seen that part of the repo, the exact files and lines, a size estimate — then offer the set to `/anchor:issue`. |
| `edit` | land the fix as a direct edit in that repo for the user to review. No branch, no commit — leaving it in the working tree is what lets them read it before it goes anywhere. |
| `skip` | not examined at all, and not mentioned. |

An `edit` target still reports what was changed. A fix nobody was told about is
indistinguishable from a fix that never happened.

A target's recorded disposition is its default, not a verdict on the run. Where
a finding lands somewhere other than where its disposition points — a
`summarize` target whose finding is a one-line fix, an `issue` target the user
is sitting in — offer the other shape when the walk reaches it.

## 6. Report once, then walk the findings

One pass, in this order, and nothing per tool call:

1. The changelog disposition — every entry, one line each.
2. What the user's own `~/.claude` needs, and where the fix belongs.
3. Per target: the verdict count, then the findings in their disposition's shape.

**Report only what the run was configured to act on.** The declared set is the
answer to what shipshape is for; a count of the plugins outside it is a fact
about somebody else's software, and putting it at the end of the report asks the
user to hold a number they have nothing to do with. Skipped targets earn no
line, no count, and no closing tally.

Then take the findings one at a time and ask **file it or fix it now**, one
**AskUserQuestion** per finding, carrying the file, the line and the size of the
fix into the question itself. The report is what puts every finding in view; the
walk is what turns each one into a decision. A single closing offer to file the
set makes the user answer for all of them at once, which is the one shape that
suits none of them.

Where the whole pass turns up nothing, that is the answer: say the release was
internal to Claude Code and touched nothing the user maintains. A quiet upgrade
is a real outcome and worth stating plainly.
