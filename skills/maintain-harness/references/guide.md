# The harness maintenance guide

The user's own instructions for after each half of `/maintain-harness`, in one
file with one section per half:

```markdown
## After a Claude Code upgrade

Re-train my AI artifacts against this version: /my-retrain-command

## After plugins change

1. /reload-plugins

### my-plugin
2. /my-plugin:install-my-plugin
```

Each half carries out only its own section, since they fire on different
events: the upgrade section once, when a new Claude Code version is
acknowledged; the plugins section after any run that updated, installed, or
uninstalled a plugin. A `###` subheading stays inside its section. Text outside
the two sections is never carried out, and the script names it on stderr; say
so where it turns up, quoting the line, so the user can move it.

Everything in a section reaches the model unaltered apart from HTML comments, so
it can carry the *why* of a step and not just the list.

```bash
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash "${CLAUDE_PLUGIN_ROOT}/scripts/harness-guide.sh" --status
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash "${CLAUDE_PLUGIN_ROOT}/scripts/harness-guide.sh" --section plugins
CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash "${CLAUDE_PLUGIN_ROOT}/scripts/harness-guide.sh" --seed
```

`--status` reports `path`, `present`, `upgrade.filled`, `plugins.filled`, and
`stray`. `--section` prints one section with comments stripped (nothing when the
guide is absent). `--seed` writes the template, both headings and comments only,
and leaves a guide already on disk alone. `--installers` lists the CLI
installers the installed plugins ship, as `/<plugin>:<name>`. `--status`,
`--section`, and `--seed` first move an older guide's steps in, when one is on
disk.

## Show or change it
<!-- covers: GUIDE-08 -->

When the user asks to see or change their guide (or what runs after an upgrade,
or after maintenance), read `--status`. Where `present` is false, set it up
instead (below). Otherwise read the file at `path` raw and show it, comments
included: the comments are their notes and the seeded explanation.

To change it, draft plain instructions naming the commands, under the heading
for when they should run, show the text, and edit the file once they approve.
Leave the seeded comment block in place unless they ask for it gone. Then print
the section you changed with `--section`, so a stray `<!--` doesn't go
unnoticed. Setting the guide runs nothing: it acknowledges no version and
maintains no plugins.

## Set it up
<!-- covers: GUIDE-07, GUIDE-12 -->

An absent guide means the user has never been asked. Ask once, with what this
machine actually needs:

1. **Find the follow-up steps the installed plugins ship.** These are CLI
   installers, and each wrapper they install is pinned to the version path it
   ran from, so an update leaves it pointing at the old one:

   ```bash
   CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA} bash "${CLAUDE_PLUGIN_ROOT}/scripts/harness-guide.sh" --installers
   ```
2. **Ask about both sections in one AskUserQuestion**, one question each:
   - header `Plugins`: where installers turned up, the first option is **Refresh
     plugin CLIs**, whose description names the installers found and says the
     section puts `/reload-plugins` first, since an installer run before the
     reload re-pins to the version just updated away from. Then **Write my own**
     (they say what to run, and you draft it) and **Nothing**. Where no
     installers turned up, offer only the last two.
   - header `Upgrade`: **Nothing** (shipshape's own check runs on every upgrade
     regardless) and **Write my own**.
3. **Write the answer.** Seed the file first, which puts both headings and the
   explanatory comments in place on every path, then show the drafted text and
   add it under its heading once they approve. Write the installer step as an
   instruction to find the installers at run time rather than a list of the ones
   found today, so the section still covers a plugin installed later. **Nothing**
   for both stops at the seed: the file is present with both sections unfilled,
   so no later run asks again.
