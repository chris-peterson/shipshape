# shipshape

A Claude Code plugin with two goals for a user's **harness**: that they know
what's changing in it, and that it stays current. It covers Claude Code itself
(announcing a version change, walking the changelog delta, running the
instructions they wrote for an upgrade) and their *other* plugins (reconciling
what's installed against what they declared, updating it, pruning the stale
version caches an update leaves behind and the data dirs an uninstall would
have deleted unasked, arming marketplace auto-update). What the skills do for a
*user* lives on the docs site (https://chris-peterson.github.io/shipshape);
this file is for working on the plugin itself.

`SPEC.md` is the requirement source of record and `STATUS.md` is its coverage
ledger. A change to behavior updates the requirement and the ledger in the same
commit, not as a follow-up.

## This code deletes things

shipshape removes directories from under a user's other plugins, and the machine
it runs on is usually running several Claude Code sessions at once. Every safety
rule here exists because the naive version of the check was wrong in a way that
lost data:

- **Never prune on doubt.** `plugin-cache-in-use.sh` answers *in use* whenever
  liveness can't be disproven — an unparseable `procStart`, a `date` dialect it
  can't read, `jq` missing entirely. The absent signal is surfaced on stderr, not
  swallowed, and never read as "safe to delete".
- **A lease is a PID *and* a process start time.** The OS recycles PIDs, so
  `ps -p <pid>` succeeding proves nothing on its own; comparing start times is
  what rejects the reuse and lets genuinely stale caches be pruned at all.
- **Uninstalls gate on the install manifest**, not on `claude plugin list` and
  the desired set. A key absent from the manifest while another row names the
  same plugin means a shared on-disk install — skip it.
- **Project-scope plugins are never uninstalled.** They're checked into someone's
  repo and shared with their team.
- **The parent `cache/<marketplace>/` and `data/` directories are never
  deleted**, only entries within them.
- **A non-empty data dir asks first**, quoting its size and a sample of names,
  because that's where accumulated user state lives.

`claude plugin` has no concurrency control of its own, which is why a reconcile
takes the cooperative maintenance lock first. The lock is keyed by session id, so
it's re-entrant within a session (each skill step runs in a fresh shell) and
mutually exclusive across them; a lock older than the stale threshold is treated
as an abandoned crashed run and stolen.

## Commands

```bash
just test        # every scripts/tests/*.test.sh
just check       # validate source and preview the pending projection (no write)
just generate    # regenerate plugin.json and docs/ from plugin.yml and the sources
just docs        # serve the docsify site locally

bash scripts/tests/<name>.test.sh    # one suite
```

## Layout

```text
plugin.yml                          canonical descriptor — manifest, marketplace entry, docs copy
skills/plugin-maintenance/SKILL.md  the maintenance skill — the prompt is the implementation
skills/claude-code-version/         everything a user does about a version change: the guide, what's new, acknowledge
hooks/enforce-autoupdate.sh         SessionStart hook that arms marketplace auto-update
hooks/claude-code-version.sh        SessionStart hook that announces a Claude Code version change; also the skill's --status, --guide, and --ack
scripts/plugin-cache-in-use.sh      lease liveness — exit 0 in use, exit 1 delete-eligible
scripts/plugin-maintenance-lock.sh  the cooperative reconcile lock
scripts/tests/                      bash suites, one per script
SPEC.md / STATUS.md                 requirements and their coverage
docs/                               docsify site (_sidebar.md, README.md, favicon are source)
```

`.claude-plugin/plugin.json`, `hooks/hooks.json`, `plugin.yml`'s `suite.describe`
block, and most of `docs/` are **generated** by `shipyard` from the sources above.
Never hand-edit a generated file; edit its source and run `just generate`.

## Conventions

- **Bash, `set -euo pipefail`, no third-party dependencies beyond `jq`** — and a
  missing `jq` is reported and exits without changes rather than degrading.
- **The script decides facts; the skill decides judgment.** Lease liveness and
  lock ownership are deterministic and belong in `scripts/`; what to do about a
  non-empty data dir is a question for the user and belongs in the `SKILL.md`.
  The skill acts on a script's verdict without re-auditing it.
- **A hook writes only when something is missing.** The auto-update hook is
  idempotent: at steady state it changes nothing and prints nothing, so a session
  start stays quiet.
- **Report outcomes, not investigation.** No per-tool-call preambles, no narrated
  reasoning, and nothing about work outside the current run.
- **Every enabled plugin gets its own row** in the updates report; unchanged ones
  are not collapsed into a count. Stale-version caches are the exception —
  reported as one count-and-size line, with table rows reserved for real orphans.

## Glossary

- **Harness** — the Claude Code install, its enabled plugins, and the user's own
  rules, skills, and hooks. shipshape reports what changed in the first, keeps the
  second current, and hands the third to the guide the user wrote. `SPEC.md`
  defines the term and cites its industry use.
- **Desired set** — the plugins declared under `enabledPlugins` in
  `~/.claude/settings.json`. What the user said should be enabled; disk may have
  drifted from it.
- **Installed set** — what `claude plugin list` reports, each with a
  `<plugin>@<marketplace>` key, version, scope, and status.
- **Install manifest** — `~/.claude/plugins/installed_plugins.json`, the record
  every uninstall is gated on.
- **Scope** — a plugin's origin: **user** (personal, safe to reconcile),
  **project** (checked into a repo, team-shared), or **local**.
- **Version cache** — `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`,
  the on-disk copy a pinned session loads at startup.
- **Data dir** — `~/.claude/plugins/data/<plugin>-<marketplace>/`, which may hold
  accumulated user state. A slug ending `-inline` is ignored entirely.
- **`.in_use` lease** — a `{"pid","procStart"}` file each running session drops
  against the version it loaded.
- **Maintenance lock** — the cooperative lock held for a reconcile's duration.
- **Version marker** — `${CLAUDE_PLUGIN_DATA}/acknowledged-version`, the Claude
  Code version the user has *acknowledged*. Not the last one seen: that
  distinction is what makes an announcement outlive the session it appears in.
- **Version-change guide** — `${CLAUDE_PLUGIN_DATA}/on-claude-code-version-change.md`,
  the user's own instructions for a version change. Seeded as comments only, and
  a comments-only guide runs nothing.
- **Version skill** — `/claude-code-version`, the one place a version change is
  handled: read or set the guide, walk what's new, acknowledge. The hook
  announces and stops there, so the skill is what runs the guide — a one-time
  errand doesn't belong on a hook that fires every session until it's cleared.
  It's a skill rather than a documented shell line because
  `${CLAUDE_PLUGIN_ROOT}` resolves in skill content: the path to the hook
  carries shipshape's own version, so anything literal goes stale at the next
  update. It's model-invocable, which is what lets the hook's handoff reach it.
