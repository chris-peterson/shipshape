---
name: claude-code-version
description: Handle a Claude Code version change — what's new, the instructions to run on an upgrade, and acknowledging it, which clears shipshape's banner.
---

# Claude Code version

shipshape tracks the Claude Code version the user has **acknowledged**, and
banners every session start while the running version is ahead of it. This skill
is everything a person does about that: read or set the instructions that run on
a version change, walk what changed, and acknowledge the upgrade.

Acknowledging is what runs their instructions. The `SessionStart` hook announces
and stops there, so this skill is the only path that dispatches the guide —
recording the version any other way clears the banner and silently drops the
errand it was announcing.

## Start with the facts
<!-- covers: VERSION-22 -->

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/hooks/claude-code-version.sh --status
```

Run it as written, at the top of every mode. Both paths arrive already resolved
for the install that's running; a path recalled or copied from elsewhere carries
shipshape's own version and goes stale at the next update. Keep the
`CLAUDE_PLUGIN_DATA` assignment too — the variable reaches hook processes, not
the shell a Bash tool call runs in. The same holds for the `--guide` and `--ack`
commands below.

```json
{
  "acknowledged": "2.1.234",
  "current": "2.1.235",
  "pending": true,
  "changelog": "https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#21235",
  "guide": { "path": "…/on-claude-code-version-change.md", "filled": true }
}
```

`acknowledged` is null before shipshape's first session has recorded anything.
`pending` is the banner: true means one is up. `guide.filled` is false while the
document holds nothing but comments, which is what it ships as.

## Pick the mode
<!-- covers: VERSION-17, VERSION-23 -->

| What was asked | Mode |
|---|---|
| "what runs when the version changes", "set my upgrade instructions", "show the guide" | [The guide](#the-guide) |
| "what's new", "what changed", "walk me through it" | [What changed](#what-changed) |
| "handled", "acknowledge", "dismiss", "clear the banner", or the user has taken the update in | [Acknowledge](#acknowledge) |

**Every path but the guide opens with what changed.** Acknowledging and the
no-argument path both lead with the what-changed summary, so a version is
never cleared, or offered up for clearing, without the user seeing what's in
it. The guide path is the exception: writing instructions for a future upgrade
is not handling this one.

With no argument, report the status line, summarize what changed, then close
with the question. When a banner is up, lead with the two versions:

```text
Claude Code 2.1.234 → 2.1.235, unacknowledged. Your version-change guide is written.
```

## Close with the question
<!-- covers: VERSION-24, VERSION-25 -->

While `pending` is true, every path but the guide ends in one
**AskUserQuestion**. What precedes it is a screen of prose, and a sentence
offering to acknowledge at the bottom of that reads as the end of the report
rather than a decision waiting on the user.

**Where `guide.filled` is true, say what acknowledging will run.** Read the
guide with `--guide` and put **at most three lines** above the question, one per
thing it does, in the guide's own terms. This is a reminder, not the document:
fold related steps together, and drop the rationale the guide carries for you.
Where it holds more than three things to do, name the three that change files or
run commands, and say how many are left.

| Field | Value |
|---|---|
| `header` | `Version` |
| `question` | `Acknowledge Claude Code <current>?` |
| First option | **Acknowledge + run guide** — "Carries out your version-change guide, then records `<current>`. The banner stops." Where `guide.filled` is false, the label is **Acknowledge** and the description is the recording alone. |
| Second option | **Ask me again later** — "Leaves it pending. The banner is back next session." |

**Acknowledge** is the go-ahead: the summary is already given, so pick up
[acknowledging](#acknowledge) at its guide step. On **Ask me again later**,
stop — nothing is recorded, and there's nothing to add after their answer.

## The guide
<!-- covers: VERSION-18 -->

The guide is the user's own instructions for a version change, at `guide.path`.
Read that file raw and show it, comments included — the comments are their notes
and the seeded explanation, and only the acknowledge step strips them.

To set it, write plain instructions naming the commands they want run:

```markdown
Re-train my AI artifacts against this Claude Code version:
  1. /my-retrain-command
  2. /plugin-maintenance
```

Draft against what they asked for, show them the text, and edit the file once
they approve. Everything in it reaches the model unaltered apart from HTML
comments, so it can carry the *why* of a step and not just the list. Leave the
seeded comment block in place unless they ask for it gone.

Then show what would actually run, so a stray `<!--` doesn't go unnoticed:

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/hooks/claude-code-version.sh --guide
```

Setting the guide is not acknowledging. Leave a pending version pending.

## What changed
<!-- covers: VERSION-19 -->

Fetch the `changelog` URL from `--status` and walk the entries **after**
`acknowledged` through `current` — every release they skipped, not just the one
they landed on. When nothing is pending, walk the entry for `current` instead
and say that's where they already are.

**Report one screen.** The person reading has an upgrade to get through, not a
changelog to study. Lead with the handful of items *this* user would act on: a
new skill, command, or tool; a changed default; and anything touching the
artifacts they write — hook events and schemas, settings keys, skill and plugin
frontmatter, permission syntax — since that staleness is what the guide exists
to repair. One line each, naming the version it landed in. Then say how many
entries you passed over, and offer the per-release walk rather than printing it.

Nothing worth acting on is its own answer: say the releases were internal fixes
and stop there.

Walking is not acknowledging. While `pending` is true, close with the
[question](#close-with-the-question).

## Acknowledge
<!-- covers: VERSION-20, VERSION-21, VERSION-23 -->

Stop here when `pending` is false: there's no upgrade to handle, and the guide
is an upgrade errand rather than something to run on request. Say what's
acknowledged and offer to walk what changed.

**1. Lead with what changed.** Give the one-screen summary before anything
else. Acknowledging is what clears the banner, so this is the last point at
which the user sees what they're clearing. Skip it only when they've already
had the summary this session.

**2. Read the guide.** Comments are already stripped; empty output means an
unfilled document and nothing to carry out.

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/hooks/claude-code-version.sh --guide
```

**3. Carry it out**, in the order written, before recording anything. It's the
user's own instruction to you. If a step fails or needs a decision, stop and
ask — leaving the version unacknowledged means the banner brings them back to
it, where recording first would bury a half-run upgrade.

**4. Record the version.** Use the version the user was *shown* — the one this
session's banner and hook context name. Fall back to `current` from `--status`
only when this session carries no banner, which is the case when they're acting
on one they saw earlier. Claude Code can update its own binary mid-session, and
recording a version nobody was shown swallows that change.

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/hooks/claude-code-version.sh --ack <version>
```

**5. Report** what ran and what was recorded. The script prints its own line;
pass it through:

```text
Ran your version-change guide: /my-retrain-command, /plugin-maintenance.
shipshape: acknowledged Claude Code 2.1.235.
```

A non-zero exit means nothing was recorded and the banner will be back next
session — surface the script's stderr rather than reporting a dismissal that
didn't happen.
