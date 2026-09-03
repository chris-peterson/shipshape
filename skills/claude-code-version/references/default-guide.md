# The built-in guide: the errand every upgrade earns

<!-- covers: VERSION-34, VERSION-35, VERSION-36, VERSION-37 -->

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
[What changed](../SKILL.md#what-changed) section. Two sources, in order:

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --drift
```

`mirror` names a local checkout of `anthropics/claude-code` when the user has
recorded one — `git -C <mirror> fetch -q` then `git -C <mirror> show
origin/main:CHANGELOG.md` reads the whole file. An empty `mirror` means read it
through `gh` instead:

```bash
gh api repos/anthropics/claude-code/contents/CHANGELOG.md --jq '.content' | base64 -d
```

Offer `--set-mirror <path>` when a user turns out to have a checkout the
declaration doesn't know about; it makes every later upgrade cheaper. Never
assume a path — an unrecorded mirror is a question, not a guess.

**Read the first-party reference implementations too, where they are
reachable.** Anthropic ships its own worked examples, and one that now does
something the user's artifacts describe differently is the same staleness signal
as a changelog entry — often a stronger one, since a changelog line can omit a
shape change the example shows plainly. From a mirror they are directories;
through `gh` they are one API call each, so read the ones the changelog entries
actually implicate rather than all of them.

| Path | What a change there implicates |
|---|---|
| `plugins/` | plugin manifests, skill and command frontmatter, hook wiring |
| `examples/hooks/` | hook events, payload shape, exit-code contract |
| `examples/settings/` | settings keys, permission syntax |
| `examples/mdm/` | managed-settings profiles |
| `scripts/` | anything the CLI is driven by |

## 2. Check the user's own harness

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

## 3. Fan out over the declared targets

`targets` from `--drift` is the set, each row carrying its own `action`. Group
the rows by `src` first — one repo can back several plugins, and analyzing it
twice splits its verdicts across two reports.

Where `settled` is false, resolve the question first: read
[deep-scan-set.md](deep-scan-set.md) for what each bucket means. A run does not
examine a target it could not read.

Each target answers with the verdict contract from
[Acknowledge](../SKILL.md#acknowledge): one anchored verdict per candidate, no
hedges, counted in the report.

## 4. Act on each finding by its target's disposition

`action` is what happens to a finding, and it is the user's recorded preference
rather than a judgment to make per run:

| `action` | What to do with a finding |
|---|---|
| `summarize` | one line in the report: the file, the line, and what a fix would cost. Nothing is written. The default, because it presumes nothing. |
| `issue` | draft it for filing — title, a why-first body written for someone who has never seen that part of the repo, the exact files and lines, a size estimate — then offer the set to `/anchor:issue`. |
| `edit` | land the fix as a direct edit in that repo for the user to review. No branch, no commit — leaving it in the working tree is what lets them read it before it goes anywhere. |
| `skip` | not examined at all; contributes a count, never a row. |

An `edit` target still reports what was changed. A fix nobody was told about is
indistinguishable from a fix that never happened.

## 5. Report once

One pass, in this order, and nothing per tool call:

1. The changelog disposition — every entry, one line each.
2. What the user's own `~/.claude` needs, and where the fix belongs.
3. Per target: the verdict count, then the findings in their disposition's shape.
4. The skipped count — plugins left to their own maintainers, named as a number
   rather than a list.

Where the whole pass turns up nothing, that is the answer: say the release was
internal to Claude Code and touched nothing the user maintains. A quiet upgrade
is a real outcome and worth stating plainly.
