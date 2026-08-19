# <img src="favicon.svg" alt="shipshape" width="64" height="64" style="vertical-align: middle"> shipshape

Know what's changing in your Claude Code harness, and keep it current.

Your **harness** is everything wrapped around the model that decides how well it
works for you: Claude Code itself, the plugins you've installed, and the rules,
skills, and hooks you wrote. It moves without asking. Claude Code updates itself
between launches, plugins fall behind the set you declared, and your own
artifacts were written against whatever version was current that week. shipshape
has two jobs about that: tell you what changed, and keep what it can current.

| What moves | What shipshape does about it |
|---|---|
| Claude Code itself | a `SessionStart` hook banners a version change, and `/claude-code-version` walks what's new, runs the instructions you wrote for an upgrade, and clears the banner |
| Your installed plugins | `/plugin-maintenance` reconciles them against your `enabledPlugins`, updates what stays, and reaps the caches and data dirs `uninstall` leaves behind |
| Your marketplaces | a second `SessionStart` hook arms `autoUpdate`, so plugins keep themselves current without you asking |

> [!TIP]
> [Thoughtworks' Technology Radar](https://www.thoughtworks.com/radar) (Vol. 34,
> theme *Putting coding agents on a leash*) defines a **coding agent harness** as
> "controls that guide agents' behavior before code is generated and provide
> feedback afterwards to enable self-correction" — the feedforward half being
> Agent Skills and the plugin marketplaces that distribute them. Those controls
> are only as good as their current version, which is the part shipshape keeps
> in order.

## In action

A new Claude Code arrives without a word about it, plugins drift out of date, and
`uninstall` leaves clutter behind:

<div class="cw-session" data-cw-session="session"></div>

## Install

```bash
claude plugin marketplace add chris-peterson/claude-marketplace
claude plugin install shipshape@chris-peterson
```

## The `/plugin-maintenance` skill

Run it from inside Claude Code whenever you want to tidy up:

```text
/plugin-maintenance
```

It reconciles **installed** plugins against the **desired** set you've declared
in `~/.claude/settings.json` (`enabledPlugins`), then:

1. **Inventory** — list what's installed (`claude plugin list`) and read your
   desired set.
2. **Update** — `claude plugin update` every plugin in both sets, in parallel.
3. **Reconcile** — uninstall user-scope extras, offer to install what's
   missing, and skip plugins it shouldn't remove (team-shared project-scope
   ones, and a plugin whose two marketplace rows share one on-disk install).
4. **Scan & prune** — find orphan and stale-version caches and orphan data
   dirs, auto-delete the safe ones, and ask before removing anything that may
   hold user state.

It lists **every enabled plugin** — each gets a row with its version and result,
so you can confirm each plugin's disposition at a glance rather than re-running
`claude plugin list`. Only caches are reported by exception (stale-version dirs
are routine noise).

Two runs, two outcomes — a reconcile with work to do, and a settled machine
where there's nothing left but to keep auto-update armed:

<div class="cw-session" data-cw-session="examples"></div>

### What it cleans that nothing else does

`claude plugin uninstall` removes a plugin but leaves its cache and **data**
directories behind. Claude Code maintains per-version `.in_use` leases and
sweeps dead ones, but it doesn't reap orphaned data dirs or stale versions left
by updates. shipshape closes that gap — and it respects live `.in_use` leases,
so it never prunes a version another running session is still using.

> [!TIP]
> The desired set is your own `enabledPlugins`. Curate that map and
> `/plugin-maintenance` becomes "make my machine match what I declared."

## Auto-update

Updating plugins by hand is the problem shipshape exists to remove. Once
installed, a `SessionStart` hook arms **marketplace auto-update**: it sets
`autoUpdate: true` for every known marketplace under
[`extraKnownMarketplaces`](https://code.claude.com/docs/en/discover-plugins) in
`~/.claude/settings.json` — the surface Claude Code reads at startup to refresh
marketplaces and update their plugins.

Settings are read before hooks run, so the change takes effect on the **next**
launch; from then on each marketplace keeps itself current. The write is
idempotent — it happens only when a marketplace is missing the flag, so a
settled setup is a silent no-op.

> [!NOTE]
> If your `~/.claude/settings.json` is generated or synced from another source,
> that process will overwrite this edit. Declare `extraKnownMarketplaces` in
> your source of truth instead.

## When Claude Code changes version

Claude Code updates itself between launches without saying much about it. Two
things go unnoticed when it does. The change itself, which turns a new behavior
into a mystery until you think to check `claude --version` against the
changelog. And the staleness it leaves in your own AI artifacts — the rules,
skills, hooks, and plugin manifests you wrote against the version before it, whose
hook schemas, settings keys, and frontmatter fields may not mean what they did.

A second `SessionStart` hook watches for it, and `/claude-code-version` is where
you deal with it.

### The banner

When the version has moved, the next session opens with one line naming both
versions, linking that release's changelog entry, and naming the command that
handles it:

```text
Claude Code 2.1.226 → 2.1.227 · https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#21227 · /claude-code-version to review and clear
```

It stays up until the new version is **acknowledged**: every session repeats the
line while it isn't, so an update doesn't scroll past unread in a session you
opened to do something else. Ask what changed, tell Claude you've seen it, or
ask it to deal with the upgrade, and it runs the skill for you — most of the
time there's nothing for you to type. Type it yourself when the cue doesn't land
and the line is still there next session.

The first session after installing shipshape records the version you're on and
says nothing, since there's no delta to report yet.

### `/claude-code-version`

One skill, and it picks what to do from what you asked for:

| Ask for | What happens |
|---|---|
| your guide | Shows the instructions that run on a version change, and writes new ones once you've approved the text |
| what's new | Walks the changelog entries between the version you acknowledged and the one you're running |
| acknowledge, dismiss, "handled" | Runs your guide, records the version, and the banner is gone |

Acknowledging is the only thing that runs your guide, and the only thing that
clears the banner — asking what's new leaves it up. It's a skill rather than a
shell line you could copy from here on purpose: shipshape's own version is in
the path to the hook it calls, so anything literal would stop resolving at the
next update.

### Your version-change guide

What Claude should do about an upgrade is a document you write. It's created for
you, so you never have to guess its name — look in your shipshape data dir after
the first session:

```text
~/.claude/plugins/data/shipshape-<marketplace>/on-claude-code-version-change.md
```

It arrives holding one comment explaining itself, and **a document with nothing
but comments runs nothing**. Write plain instructions into it, naming the
commands you want run:

```markdown
Re-train my AI artifacts against this Claude Code version:
  1. /my-retrain-command
  2. /plugin-maintenance
```

Everything you write reaches Claude unaltered apart from HTML comments, which
are dropped — that's what keeps the template's own explanation from arriving as
an instruction, and it leaves you a place for notes to yourself. Handing Claude
the text *is* the mechanism: nothing here can invoke a slash command on your
behalf, but text Claude reads is text Claude acts on, so the commands your
document names are the commands that run. That also means the document can carry
the reasoning, not just a list. Say why a step matters and Claude has it at the
point of doing the work.

It runs when you acknowledge the upgrade, once. The hook that spots the version
change fires at every session start until you do, which is right for a banner
and wrong for an errand — so the announcement and the errand are separated, and
acknowledging is what joins them.

You don't have to open the file yourself: `/claude-code-version` will show it to
you and write what you dictate.

### What happens when

| Situation | What you get |
|---|---|
| First session after installing | The version is recorded, the document is created. Nothing else. |
| Version unchanged | Silent. |
| Version changed | The banner, repeating every session until acknowledged. |
| You acknowledge, document written | Your instructions carried out, then the banner clears. |
| You acknowledge, document still all comments | Nothing to run; the banner clears. |
| After it's acknowledged | Silent, until the next version change. |

Any difference in the version string counts, patch bumps included, so `2.1.220 →
2.1.221` announces just like `2.1 → 2.2`.

The marker and your document both live in `${CLAUDE_PLUGIN_DATA}`, the
[directory Claude Code guarantees survives plugin
updates](https://code.claude.com/docs/en/plugins-reference#persistent-data-directory).
A version cache would not survive: an update moves shipshape to a new version
dir, and `/plugin-maintenance` prunes the old one.

To silence the banner, set `SHIPSHAPE_VERSION_NOTICE` to `off` in the `env`
block of `~/.claude/settings.json`:

```json
{
  "env": {
    "SHIPSHAPE_VERSION_NOTICE": "off"
  }
}
```
