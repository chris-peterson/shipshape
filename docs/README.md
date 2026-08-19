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
| Claude Code itself | the `claude-code-version` hook posts a banner when the version moves, and `/claude-code-version` walks what's new, runs the instructions you wrote for an upgrade, and clears the banner |
| Your installed plugins | `/plugin-maintenance` reconciles them against your `enabledPlugins`, updates what stays, and prunes the caches and data dirs an uninstall leaves for later |
| Your marketplaces | the `enforce-autoupdate` hook arms `autoUpdate`, so plugins keep themselves current without you asking |

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
an uninstall leaves cache and data dirs to deal with:

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

1. **Lock** — take a cooperative maintenance lock, since `claude plugin` has no
   concurrency control of its own. If another session is already reconciling,
   the run stops and names it rather than interleaving.
2. **Inventory** — list what's installed (`claude plugin list`) and read your
   desired set.
3. **Update** — `claude plugin update` every plugin in both sets, one at a
   time. Updating in parallel makes plugins from the same marketplace collide
   over its clone, and the failures hide in the output.
4. **Reconcile** — uninstall user-scope extras, offer to install what's
   missing, and skip plugins it shouldn't remove (team-shared project-scope
   ones, and a plugin whose two marketplace rows share one on-disk install).
5. **Scan & prune** — find orphan and stale-version caches and orphan data
   dirs, auto-delete the safe ones, and ask before removing anything that may
   hold user state.
6. **Reload** — plugins on disk aren't the plugins your session is running, so
   it hands you `/reload-plugins` to apply them. Only you can type it, and it
   reaches only the session you type it in.

It lists **every enabled plugin** — each gets a row with its version and result,
so you can confirm each plugin's disposition at a glance rather than re-running
`claude plugin list`. Only caches are reported by exception (stale-version dirs
are routine noise).

Two runs, two outcomes — a reconcile with work to do, and a settled machine
where there's nothing left but to keep auto-update armed:

<div class="cw-session" data-cw-session="examples"></div>

### Cache and data dirs, on your schedule instead of theirs

Claude Code cleans up after an uninstall, but not at the moments you'd want. It
deletes the plugin's **data** directory as part of the uninstall, without
asking, and that's where accumulated state lives. It leaves the superseded
**version cache** in place, marked orphaned, for a background sweep to remove
about 14 days later.

`/plugin-maintenance` inverts both. Its own uninstalls pass `--keep-data`, so a
data dir survives to be reported and you decide whether it goes. And it prunes
stale version caches now rather than two weeks from now, so the cache holds one
version per plugin. It reads each version's live `.in_use` leases first, so it
never prunes a version another running session is still loaded from.

> [!TIP]
> The desired set is your own `enabledPlugins`. Curate that map and
> `/plugin-maintenance` becomes "make my machine match what I declared."

## Auto-update

The `enforce-autoupdate` hook arms **marketplace auto-update** at session start,
so you stop updating plugins by hand. It reads your registered marketplaces from
`~/.claude/plugins/known_marketplaces.json` and, for each one, sets
`autoUpdate: true` on its
[`extraKnownMarketplaces`](https://code.claude.com/docs/en/discover-plugins#configure-auto-updates)
entry in `~/.claude/settings.json`, creating the entry when there isn't one.

That flag is worth arming because the default is off for everything you didn't
get from Anthropic: official marketplaces auto-update out of the box, third-party
and local ones don't, and the only other way to turn it on is one marketplace at
a time through the `/plugin` interface.

Settings are read before hooks run, so the change takes effect on the **next**
launch; from then on each marketplace keeps itself current. The write is
idempotent — it happens only when a marketplace is missing the flag, so a
settled setup is a silent no-op.

Auto-update runs *after* a session starts, with a random delay of up to ten
minutes, so the session you're in keeps the versions it launched with. When
something updates you'll get a prompt to run `/reload-plugins`; otherwise the new
versions are there at your next launch.

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

The `claude-code-version` hook watches for it, and `/claude-code-version` is where
you deal with it.

### The banner

When the version has moved, the next session opens with one line naming both
versions, linking that release's changelog entry, and naming the command that
handles it:

```text
Claude Code 2.1.226 → 2.1.227 · https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#21227 · /claude-code-version to review and clear
```

It stays up until the new version is **acknowledged**: every session repeats the
line until you do, so an update doesn't scroll past unread in a session you
opened to do something else. Ask what changed, say you've seen it, or ask Claude
to handle the upgrade, and it runs the skill. Type `/claude-code-version`
yourself if the line is still there next session.

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

It arrives holding only comments explaining what to write, and **a document with nothing
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
