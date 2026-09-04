# First run: configure, preview, then report

<!-- covers: VERSION-38, VERSION-39, VERSION-40 -->

The built-in guide runs against the repos the user maintains and the
dispositions they chose. On a first run neither exists, so a changelog summary
has nothing to be about. Configure first, report second.

Detect it from the declaration: `--drift` reporting an empty `targets` and an
empty `skip` means nothing has ever been recorded. A settled declaration with
one `new` plugin is not a first run — that is the ordinary drift question,
answered in place.

## Open with two lines

```text
This is the first time running `/shipshape:claude-code-version`.

A couple quick questions…
```

No release summary, no version delta, and **no inventory table.** Listing every
installed plugin before the first question makes it read as a quiz on data the user has
not been given a reason to care about. Each question carries its own list.

## 1. Which repos are theirs to patch

The one thing shipshape cannot derive. Read
[deep-scan-set.md](deep-scan-set.md) for the buckets and dispositions.

**Walk one source owner at a time** — the `source` each `new` entry carries,
cut down to its host and owner. One question per owner, and the question is
always the same one:

```text
Do you own or maintain any of these plugins?
acme-lint, acme-deploy, acme-docs
  ▸ All of them
    None of them
    Let me choose
```

**Name the plugins and ask the one thing.** The grouping is shipshape's
bookkeeping, not the user's: don't explain that they share a source repo, don't
explain what a bundled plugin is, don't build a premise the user has to accept
before the question makes sense. Every clause that isn't the list or the question
is a clause they have to read twice.

**Not one marketplace at a time.** An owner's plugins spread across several
marketplaces, and a shared marketplace holds several owners' — so walking
marketplaces asks the same owner twice and mixes strangers into one question.
Owner is what predicts the answer: someone maintains all of their own repos and
none of anyone else's. A `source` that is a relative path means the plugin lives
inside its marketplace's own repo, so those group together too.

Then find the checkouts yourself and confirm them, rather than asking for a
path:

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-scan-targets.sh --resolve
```

```text
Found them here — use these?
    ~/src/<owner>/acme-lint
    ~/src/<owner>/acme-deploy
    …
  ▸ Yes
    Some are wrong
```

**A resolved path is a candidate, so it has to be confirmable.** `--resolve`
matches each plugin's marketplace `source` against the directories Claude Code
has recorded and checks the candidate's `origin`, which is enough to tell three
same-named repos apart. What it cannot know is that a marketplace publishes some
plugins from a *distribution* repo that aggregates work done elsewhere: the
`source` then points at where the plugin ships from, not where its author edits
it, and the match is confidently wrong. So the confirmation always offers a
correction, and a corrected path is recorded as given — never argued with.

A plugin `--resolve` cannot place is asked about directly, for that plugin,
rather than by asking for a root.

The other follow-up, in plain words:

```text
When I find something in one of these, what should I do?
  ▸ Fix it and show me
    Write it up so I can file it
    Just tell me about it
```

Record each answer as it arrives. A run that resolves the set without writing it
asks again next upgrade.

**Keep the words plain.** The user is meeting this for the first time: no
"disposition", no "bare key", no "sub-group", no counting things as
"singletons". Say what the choice does to them — *fix it and show me*, *just
tell me about it*.

**Then offer the repos they already work in.** A repo that isn't a plugin can
still be written against the CLI and its schemas — the place their rules and
skills live, a tool that builds something. The install manifest cannot see those,
but `permissions.additionalDirectories` in `~/.claude/settings.json` is the
user's own list of directories they work in beyond a project, so it is where
such a repo usually already is:

```bash
jq -r '(.permissions.additionalDirectories // [])[]' ~/.claude/settings.json
```

Filter it before offering anything: the same list carries scratch paths and
globs, so keep only entries that are a directory holding `.git`, and expand a
leading `~`. Offer what survives, one option each.

**Never name a repo shipshape did not derive.** A path recalled from elsewhere
in the conversation is not something the skill knows, and offering it as an
option tells the user shipshape found it. Where the filter yields nothing, the
question stands on its own with no options prefilled.

## 2. Preview the upgrade

Show what the configuration just produced — the run they would get, not a
description of the feature:

```text
On an upgrade, shipshape will:
  · walk every changelog entry between the version you acknowledged and the one you're running
  · check your ~/.claude rules, skills, hooks and settings
  · read <n> repos and write up what it finds so you can file it
  · read <n> repos and fix what it finds, leaving the edits for you to review
  · leave <n> plugins to their own maintainers
```

Derive every line from the declaration: the counts and the wording follow what
they chose, and a group with no rows contributes no line. The preview is what
makes the next question answerable.

## 3. Did we miss anything

One question, and the last one:

```text
Did we miss anything?
```

An open question, because either kind of answer can arrive. A **repo** is
recorded as a target, resolved and confirmed like the rest. A **step** — pull a
mirror first, run a project's own export recipe — goes into their guide, written
as imperative prose: each step naming the command or path it acts on, with the
*why* kept only where it changes what the step does.

Show them the file and the wording, and write only once they approve:

```text
~/.claude/plugins/data/shipshape-<marketplace>/on-claude-code-version-change.md

  Refresh the local mirror before the changelog read:
      git -C <mirror-path> pull -p
```

"No" is a complete answer, and the common one. An unfilled guide is a finished
configuration — the built-in guide is the errand.

## Then report what changed

The summary now has something to be relevant to: lead with the entries touching
the artifacts they just named, and close with the acknowledge question per
[the skill](../SKILL.md#close-with-the-question).
