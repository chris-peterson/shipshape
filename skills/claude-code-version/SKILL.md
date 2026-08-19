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

| What was asked | Mode |
|---|---|
| "what runs when the version changes", "set my upgrade instructions", "show the guide" | [Guide](#mode-1--the-guide) |
| "what's new", "what changed", "walk me through it" | [What's new](#mode-2--whats-new) |
| "handled", "acknowledge", "dismiss", "clear the banner", or the user has taken the update in | [Acknowledge](#mode-3--acknowledge) |

With no argument, report the status line and offer the three. When a banner is
up, lead with the two versions:

```text
Claude Code 2.1.234 → 2.1.235, unacknowledged. Your version-change guide is written.
```

## Mode 1 — the guide

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

## Mode 2 — what's new

Fetch the `changelog` URL from `--status` and walk the entries **after**
`acknowledged` through `current` — every release they skipped, not just the one
they landed on. When nothing is pending, walk the entry for `current` instead
and say that's where they already are.

Report per version, newest first, and keep it to what this user would act on.
Call out anything that touches the artifacts they write — hook events and
schemas, settings keys, skill and plugin frontmatter, permission syntax — since
that staleness is what the guide exists to repair.

Walking is not acknowledging. End by offering to acknowledge (Mode 3) while
`pending` is true, and take an assenting reply as the go-ahead.

## Mode 3 — acknowledge

Stop here when `pending` is false: there's no upgrade to handle, and the guide
is an upgrade errand rather than something to run on request. Say what's
acknowledged and offer Mode 2.

**1. Read the guide.** Comments are already stripped; empty output means an
unfilled document and nothing to carry out.

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/hooks/claude-code-version.sh --guide
```

**2. Carry it out**, in the order written, before recording anything. It's the
user's own instruction to you. If a step fails or needs a decision, stop and
ask — leaving the version unacknowledged means the banner brings them back to
it, where recording first would bury a half-run upgrade.

**3. Record the version.** Use the version the user was *shown* — the one this
session's banner and hook context name. Fall back to `current` from `--status`
only when this session carries no banner, which is the case when they're acting
on one they saw earlier. Claude Code can update its own binary mid-session, and
recording a version nobody was shown swallows that change.

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash ${CLAUDE_PLUGIN_ROOT}/hooks/claude-code-version.sh --ack <version>
```

**4. Report** what ran and what was recorded. The script prints its own line;
pass it through:

```text
Ran your version-change guide: /my-retrain-command, /plugin-maintenance.
shipshape: acknowledged Claude Code 2.1.235.
```

A non-zero exit means nothing was recorded and the banner will be back next
session — surface the script's stderr rather than reporting a dismissal that
didn't happen.
