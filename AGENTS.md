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
  liveness can't be disproven — a lease yielding no pid, an unparseable
  `procStart`, a `date` dialect it can't read, `jq` missing entirely. The absent
  signal is surfaced on stderr, not swallowed, and never read as "safe to
  delete". **An unreadable input is not an absent one**, and the same holds for
  the lock: an age no `stat` dialect can read leaves the holder in place rather
  than counting as old enough to steal.
- **A lease is a PID *and* a process start time.** The OS recycles PIDs, so
  `ps -p <pid>` succeeding proves nothing on its own; comparing start times is
  what rejects the reuse and lets genuinely stale caches be pruned at all.
- **Uninstalls gate on the install manifest**, not on `claude plugin list` and
  the desired set. A key absent from the manifest while another row names the
  same plugin means a shared on-disk install — skip it.
- **An origin that isn't a registered marketplace is never pruned.** The top of
  `cache/` is a marketplace name except where Claude Code puts something else
  there: `synced` is claude.ai's, and nothing local installed it or can put it
  back. Those carry no install-manifest row, so the manifest alone reads them as
  orphans. They're reported, not hidden, because the same class catches what a
  removed marketplace left behind.
- **Project-scope plugins are never uninstalled.** They're checked into someone's
  repo and shared with their team.
- **The parent `cache/<marketplace>/` and `data/` directories are never
  deleted**, only entries within them. `plugin-cache-prune.sh` enforces that by
  path shape rather than by a rule the caller has to remember: a cache path needs
  four segments (a version dir) or three (a plugin dir, cleared with `rmdir`),
  and a data path two, so no argument reaches a parent.
- **The skill never writes its own delete loop.** Enumerating, classifying, and
  deleting are mechanism, and they ship as `plugin-cache-scan.sh` and
  `plugin-cache-prune.sh`. A loop composed for one run is untested at the moment
  it runs, and it lands outside the paths a user can grant once.
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
just generate    # regenerate plugin.json and docs/ from plugin.yml and the sources
just docs        # serve the docsify site locally
just plugin-json # regenerate .claude-plugin/plugin.json alone
just describe    # resync plugin.yml's suite.describe block alone

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
scripts/plugin-cache-scan.sh        classifies cache and data entries against the install manifest
scripts/plugin-cache-prune.sh       deletes the paths it is handed, and refuses everything else
scripts/plugin-maintenance-lock.sh  the cooperative reconcile lock
scripts/tests/                      bash suites, one per script
SPEC.md / STATUS.md                 requirements and their coverage
docs/                               docsify site (_sidebar.md, README.md, favicon are source)
```

`.claude-plugin/plugin.json`, `hooks/hooks.json`, `plugin.yml`'s `suite.describe`
block, and most of `docs/` are **generated** by `shipyard` from the sources above.
Never hand-edit a generated file; edit its source. The projection job
(`.github/workflows/project.yml`) is the writer: it runs shipyard on every push
and commits what it wrote back to the branch. `just generate` runs the same
projection locally, so you can read the pending diff before you push.

Releases are dispatched, not tagged by hand: run the **Release** workflow with a
bump level, and shipyard derives the version from `plugin.yml`, retitles
`CHANGELOG.md`'s `## Unreleased` section, commits, tags that commit, and
publishes. Write the notes into `## Unreleased` first — reading what landed is
what picks the level.

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

The terms this codebase runs on are defined in [SPEC.md](./SPEC.md#concepts):
harness, desired set, installed set, install manifest, scope, version cache,
data dir, `.in_use` lease, maintenance lock, version marker, version-change
guide, version skill. The requirements are written against those definitions, so
that is where they stay current.
