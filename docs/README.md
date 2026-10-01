<div class="ph-hero" style="--accent: color-mix(in srgb, var(--color-red) 54%, light-dark(black, white))">

<h1 class="ph-lede"><span class="ph-name">shipshape:</span> your harness, current and tidy.</h1>

<div class="ph-badge"><img class="ph-mark" src="favicon.svg" alt="shipshape" width="26" height="26">

[](_tags.md ':include')

</div>

</div>

Your **harness** is everything wrapped around the model that decides how well it
works for you: Claude Code itself, the plugins you've installed, and the rules,
skills, and hooks you wrote. It moves without asking. Claude Code updates itself
in the background, plugins fall behind the set you declared, and your own
artifacts were written against whatever version was current that week. shipshape
tells you what changed, and keeps what it can current.

| What moves | What shipshape does about it |
|---|---|
| Claude Code itself | the `check-claude-code-version` hook posts a banner when the version moves, and `/maintain-harness claude-code` walks what's new, runs the instructions you wrote for an upgrade, and clears the banner |
| Your installed plugins | `/maintain-harness plugins` reconciles them against your `enabledPlugins`, updates what stays, and prunes the caches and data dirs an uninstall leaves for later |
| Your marketplaces | the `enforce-autoupdate` hook enables `autoUpdate`, so plugins keep themselves current without you asking |

> [!TIP]
> [Thoughtworks' Technology Radar](https://www.thoughtworks.com/radar) (Vol. 34,
> theme *Putting coding agents on a leash*) defines a **coding agent harness** as
> "controls that guide agents' behavior before code is generated and provide
> feedback afterwards to enable self-correction". The feedforward half is
> Agent Skills and the plugin marketplaces that distribute them. Those controls
> are only as good as their current version, which is the part shipshape keeps
> in order.

## Install

```bash
claude plugin marketplace add chris-peterson/claude-marketplace
claude plugin install shipshape@chris-peterson
```

## Skills

One skill, [`/shipshape:maintain-harness`](/skills/maintain-harness), covers both.
Its argument picks what runs:

| Run | What it does |
|---|---|
| `/maintain-harness` | Handles a pending Claude Code upgrade, then reconciles your plugins. With no upgrade pending, it says so in one line and goes straight to plugins. |
| `/maintain-harness claude-code` | [The upgrade alone](/?id=maintain-harness-claude-code): what's new, your instructions, acknowledge |
| `/maintain-harness plugins` | [The plugins alone](/?id=your-plugins-maintain-harness-plugins): reconcile, update, and prune |
| `/maintain-harness guide` | [Your guide](/?id=your-harness-maintenance-guide): show it, change it, or set it up |

Both hooks run at session start and need nothing from you: the wiring is on the
[hooks](/hooks) page.

## Configuration

shipshape works with no setup. What you can shape is what it acts on and what
runs after it does:

| To change | Edit | Details |
|---|---|---|
| Which plugins `/maintain-harness plugins` keeps installed | `enabledPlugins` in `~/.claude/settings.json` | [Your plugins](/?id=your-plugins-maintain-harness-plugins) |
| What runs after an upgrade, and after plugins change | `harness-maintenance-guide.md` in shipshape's data dir | [Your harness maintenance guide](/?id=your-harness-maintenance-guide) |
| Which repos the upgrade check may report on, file against, or fix | `version-scan-targets.json` in shipshape's data dir, written from your answers | [The built-in check](/?id=the-built-in-check) |
| Whether the version banner shows | `SHIPSHAPE_VERSION_NOTICE` in the `env` block of `~/.claude/settings.json` | [What happens when](/?id=what-happens-when) |
| Whether a marketplace auto-updates | `extraKnownMarketplaces.<name>.autoUpdate` in `~/.claude/settings.json` | [Auto-update](/?id=auto-update) |

shipshape's data dir is `~/.claude/plugins/data/shipshape-<marketplace>/`. Ask
`/maintain-harness guide` to show or change your guide rather than hunting for the
file.

## In action

A new Claude Code arrives without a word about it, plugins drift out of date, and
an uninstall takes the data dir with it:

<div class="cw-session" data-cw-session="session"></div>

## Your plugins: `/maintain-harness plugins`

Run it from inside Claude Code whenever you want to tidy up:

```text
/maintain-harness plugins
```

It reconciles **installed** plugins against the **desired** set you've declared
in `~/.claude/settings.json` (`enabledPlugins`), then:

1. **Lock**: take a cooperative maintenance lock, since `claude plugin` has no
   concurrency control of its own. The lock covers the whole `/maintain-harness`
   run, so if another session is already maintaining its harness, the run stops
   and names it rather than interleaving.
2. **Inventory**: list what's installed (`claude plugin list`) and read your
   desired set.
3. **Update**: `claude plugin update` every plugin in both sets, one at a
   time. Updating in parallel makes plugins from the same marketplace collide
   over its clone, and the failures hide in the output.
4. **Reconcile**: uninstall user-scope extras, offer to install what's
   missing, and skip plugins it shouldn't remove (team-shared project-scope
   ones, and a plugin whose two marketplace rows share one on-disk install).
5. **Scan & prune**: find orphan and stale-version caches and orphan data
   dirs, auto-delete the safe ones, and ask before removing anything that may
   hold user state.
6. **Reload**: plugins on disk aren't the plugins your session is running, so
   it hands you `/reload-plugins` to apply them. Only you can type it, and it
   reaches only the session you type it in.
7. **Your guide**: when the run updated, installed, or uninstalled a plugin,
   it carries out the plugins section of
   [your guide](/?id=your-harness-maintenance-guide).

It lists **every enabled plugin**, and each gets a row with its version and result,
so you can confirm each plugin's disposition at a glance rather than re-running
`claude plugin list`. Only caches are reported by exception (stale-version dirs
are routine noise).

### Cache and data dirs, on your schedule instead of theirs

Claude Code cleans up after an uninstall, but not at the moments you'd want. It
deletes the plugin's **data** directory as part of the uninstall, without
asking, and that's where accumulated state lives. It leaves the superseded
**version cache** in place, marked orphaned, for a background sweep to remove
about 14 days later.

`/maintain-harness plugins` inverts both. Its own uninstalls pass `--keep-data`, so a
data dir survives to be reported and you decide whether it goes. And it prunes
stale version caches now rather than two weeks from now, so the cache holds one
version per plugin. It reads each version's live `.in_use` leases first, so it
never prunes a version another running session is still loaded from.

> [!TIP]
> The desired set is your own `enabledPlugins`. Curate that map and
> `/maintain-harness plugins` becomes "make my machine match what I declared."

## Auto-update

The `enforce-autoupdate` hook enables **marketplace auto-update** at session start,
so you stop updating plugins by hand. It reads your registered marketplaces from
`~/.claude/plugins/known_marketplaces.json` and, for each one, sets
`autoUpdate: true` on its
[`extraKnownMarketplaces`](https://code.claude.com/docs/en/discover-plugins#configure-auto-updates)
entry in `~/.claude/settings.json`, creating the entry when there isn't one.

That flag is worth enabling because the default is off for everything you didn't
get from Anthropic: official marketplaces auto-update out of the box, third-party
and local ones don't, and the only other way to turn it on is one marketplace at
a time through the `/plugin` interface.

Settings are read before hooks run, so the change takes effect on the **next**
launch; from then on each marketplace keeps itself current. The write is
idempotent: it happens only when a marketplace is missing the flag, so a
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

Claude Code updates itself in the background, and the new version takes effect
at your next launch. Its own notice tells you an update installed, not what's in
it, so two things go unnoticed. The change itself, which turns a new behavior
into a mystery until you think to check `claude --version` against the
changelog. And the staleness it leaves in your own AI artifacts: the rules,
skills, hooks, and plugin manifests you wrote against the version before it, whose
hook schemas, settings keys, and frontmatter fields may not mean what they did.

The `check-claude-code-version` hook watches for it, and `/maintain-harness` is where
you deal with it.

### The banner

When the version has moved, the next session opens with one line naming both
versions and naming the command that handles it:

```text
Claude Code: /maintain-harness  # 2.1.226 → 2.1.227
```

It stays up until the new version is **acknowledged**: every session repeats the
line until you do, so an update doesn't scroll past unread in a session you
opened to do something else. Ask what changed, say you've seen it, or ask Claude
to handle the upgrade, and it runs the skill. Type `/maintain-harness`
yourself if the line is still there next session.

The first session after installing shipshape records the version you're on and
says nothing, since there's no delta to report yet.

### `/maintain-harness claude-code`

The upgrade half picks what to do from what you asked for:

| Ask for | What happens |
|---|---|
| your guide | Shows the upgrade section of [your guide](/?id=your-harness-maintenance-guide), and writes new steps once you've approved the text |
| what's new | What landed between the version you acknowledged and the one you're running: what you'd act on first, then every other entry |
| acknowledge, dismiss, "handled" | Summarizes what changed, runs the built-in check and your own guide, records the version, and the banner is gone |

Everything but the guide opens with that summary, so you see what a version
holds before you clear it. Acknowledging is the only thing that runs the upgrade
errand, and the only thing that clears the banner. Asking what's new leaves it
up. It's a skill rather than a shell line you could copy from here on purpose:
shipshape's own version is in the path to the hook it calls, so anything literal
would stop resolving at the next update.

### The built-in check

Acknowledging an upgrade runs a check shipshape ships with, whether or not you
ever write instructions of your own. It reads every changelog entry between the
version you acknowledged and the one you're running, finds what that
invalidates in your own `~/.claude`, and then looks for the same staleness in
the repos you've said are yours to patch.

Which repos those are is the one thing shipshape can't work out from disk: a
plugin you maintain and a plugin you merely use look identical there. So the
first `/maintain-harness claude-code` asks, one plugin author at a time, and records your
answer:

| Your answer | What a finding in that repo becomes |
|---|---|
| just tell me | a line in the report, and nothing is written |
| file it | a drafted issue, offered to `/anchor:issue` with the rest |
| fix it in place | an edit in that repo's working tree, for you to review |
| not mine | nothing: it's left to its own maintainer, and counted |

Later runs reconcile that against what you have installed and ask only about
the difference, so a plugin you've already answered for never comes up again.

### What happens when

| Situation | What you get |
|---|---|
| First session after installing | The version is recorded. Nothing else. |
| Version unchanged | Silent. |
| Version changed | The banner, repeating every session until acknowledged. |
| You acknowledge, upgrade section written | What changed, the built-in check, your instructions carried out, then the banner clears. |
| You acknowledge, upgrade section empty | What changed, the built-in check, then the banner clears. |
| After it's acknowledged | Silent, until the next version change. |

Any difference in the version string counts, patch bumps included, so `2.1.220 →
2.1.221` announces just like `2.1 → 2.2`.

The marker and your guide both live in `${CLAUDE_PLUGIN_DATA}`, the
[directory Claude Code guarantees survives plugin
updates](https://code.claude.com/docs/en/plugins-reference#persistent-data-directory).
A version cache would not survive: an update moves shipshape to a new version
dir, and `/maintain-harness plugins` prunes the old one.

To silence the banner, set `SHIPSHAPE_VERSION_NOTICE` to `off` in the `env`
block of `~/.claude/settings.json`:

```json
{
  "env": {
    "SHIPSHAPE_VERSION_NOTICE": "off"
  }
}
```

## Your harness maintenance guide

Anything you want done *on top of* what shipshape does is a document you write:
one file, a section for each half.

```text
~/.claude/plugins/data/shipshape-<marketplace>/harness-maintenance-guide.md
```

```markdown
## After a Claude Code upgrade

Re-train my AI artifacts against this Claude Code version: /my-retrain-command

## After plugins change

1. /reload-plugins

### my-plugin
2. /my-plugin:install-my-plugin
```

| Section | Carried out |
|---|---|
| After a Claude Code upgrade | once, when you acknowledge a new version, after the built-in check |
| After plugins change | at the end of a run that updated, installed, or uninstalled a plugin |

One file because the default run does both halves in a row, and a step in one
often depends on the other. A `###` subheading, one per plugin say, stays inside
its section. Text outside the two sections never runs, and the run tells you
where it is.

You don't have to write it from scratch. The first run that finds no guide looks
for the CLI installers your plugins ship and offers a plugins section that
refreshes them, and asks whether you want anything run on an upgrade. Say no to
both and it writes the file with both sections empty, so it doesn't ask again.
An empty section is a finished state: the built-in check still runs on every
upgrade.

A reload has to come before a plugin's own installer: until you run
`/reload-plugins`, the session still points at the version it started on, and an
installer run from there re-pins to the version you just updated away from.
Commands only you can type, like `/reload-plugins` and any marked
`disable-model-invocation`, close the report as a numbered list in the order you
wrote them.

Everything you write reaches Claude unaltered apart from HTML comments, which
are dropped: that's what keeps the template's own explanation from arriving as
an instruction, and it leaves you a place for notes to yourself. Handing Claude
the text *is* the mechanism: nothing here can invoke a slash command on your
behalf, but text Claude reads is text Claude acts on, so the commands your guide
names are the commands that run. That also means it can carry the reasoning, not
just a list. Say why a step matters and Claude has it at the point of doing the
work.

The upgrade section runs when you acknowledge, once. The hook that spots the
version change fires at every session start until you do, which is right for a
banner and wrong for an errand, so the announcement and the errand are
separated, and acknowledging is what joins them.

If you wrote steps into `on-claude-code-version-change.md` or
`after-plugin-maintenance.md`, the next `/maintain-harness` run moves them under the
matching heading and removes the old file.
