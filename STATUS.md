# shipshape — Implementation Status

Tracks coverage of the requirements in [SPEC.md](./SPEC.md) against the single
in-repo implementation. Status vocabulary: **Covered** · **Partial** ·
**Missing** · **Contradicts**.

**Coverage: 73/73 requirements Covered (100%)**
**Evidence pointers:** file

Location holds the file. To find the spot inside it, grep for the requirement
id: every covering site carries a `covers:` marker naming the ids implemented
there, as an HTML comment under the heading in markdown and a `#` comment above
the block in shell. `grep -rn 'covers:.*RECON-08' skills hooks scripts` is the
lookup. Keeping the id in the source rather than restating each heading here
means an edit can't leave the two disagreeing.

## RECON — Reconciliation

| ID          | Status  | Location |
|-------------|---------|----------|
| RECON-01   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-maintenance-lock.sh |
| RECON-02   | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-03   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-maintenance-lock.sh |
| RECON-04   | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-05   | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-06   | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-07   | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-08   | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-09   | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-10   | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-11   | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-11a  | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-12   | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-13   | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-14   | Covered | skills/plugin-maintenance/SKILL.md |
| RECON-15   | Covered | scripts/plugin-maintenance-lock.sh |

## GUARD — Guardrails

| ID          | Status  | Location |
|-------------|---------|----------|
| GUARD-01   | Covered | skills/plugin-maintenance/SKILL.md |
| GUARD-02   | Covered | skills/plugin-maintenance/SKILL.md |
| GUARD-03   | Covered | skills/plugin-maintenance/SKILL.md |

## PRUNE — Pruning

| ID          | Status  | Location |
|-------------|---------|----------|
| PRUNE-01   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-scan.sh |
| PRUNE-02   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-scan.sh |
| PRUNE-03   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-scan.sh |
| PRUNE-04   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-scan.sh |
| PRUNE-05   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-scan.sh |
| PRUNE-06   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-prune.sh |
| PRUNE-07   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-in-use.sh |
| PRUNE-08   | Covered | skills/plugin-maintenance/SKILL.md |
| PRUNE-09   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-prune.sh |
| PRUNE-10   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-prune.sh |
| PRUNE-11   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-prune.sh |
| PRUNE-12   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-scan.sh |
| PRUNE-13   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-prune.sh |
| PRUNE-14   | Covered | scripts/plugin-cache-prune.sh |
| PRUNE-15   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-prune.sh |
| PRUNE-16   | Covered | skills/plugin-maintenance/SKILL.md; scripts/plugin-cache-scan.sh; scripts/plugin-cache-prune.sh |

## AUTO — Auto-update enforcement

| ID          | Status  | Location |
|-------------|---------|----------|
| AUTO-01    | Covered | hooks/enforce-autoupdate.sh |
| AUTO-02    | Covered | hooks/enforce-autoupdate.sh |
| AUTO-03    | Covered | hooks/enforce-autoupdate.sh |
| AUTO-04    | Covered | hooks/enforce-autoupdate.sh |
| AUTO-05    | Covered | hooks/enforce-autoupdate.sh |
| AUTO-06    | Covered | skills/plugin-maintenance/SKILL.md |

## VERSION — Claude Code version changes

| ID          | Status  | Location |
|-------------|---------|----------|
| VERSION-01 | Covered | hooks/claude-code-version.sh |
| VERSION-02 | Covered | hooks/claude-code-version.sh |
| VERSION-03 | Covered | hooks/claude-code-version.sh |
| VERSION-04 | Covered | hooks/claude-code-version.sh |
| VERSION-05 | Covered | hooks/claude-code-version.sh |
| VERSION-06 | Covered | hooks/claude-code-version.sh |
| VERSION-07 | Covered | hooks/claude-code-version.sh |
| VERSION-08 | Covered | hooks/claude-code-version.sh |
| VERSION-09 | Covered | hooks/claude-code-version.sh |
| VERSION-10 | Covered | hooks/claude-code-version.sh |
| VERSION-11 | Covered | hooks/claude-code-version.sh |
| VERSION-12 | Covered | hooks/claude-code-version.sh |
| VERSION-13 | Covered | hooks/claude-code-version.sh |
| VERSION-14 | Covered | hooks/claude-code-version.sh |
| VERSION-15 | Covered | hooks/claude-code-version.sh |
| VERSION-16 | Covered | hooks/claude-code-version.sh |
| VERSION-17 | Covered | skills/claude-code-version/SKILL.md |
| VERSION-18 | Covered | skills/claude-code-version/SKILL.md |
| VERSION-19 | Covered | skills/claude-code-version/SKILL.md |
| VERSION-20 | Covered | skills/claude-code-version/SKILL.md |
| VERSION-21 | Covered | skills/claude-code-version/SKILL.md |
| VERSION-22 | Covered | skills/claude-code-version/SKILL.md |
| VERSION-23 | Covered | skills/claude-code-version/SKILL.md |
| VERSION-24 | Covered | skills/claude-code-version/SKILL.md |
| VERSION-25 | Covered | skills/claude-code-version/SKILL.md |

## REPORT — Reporting & output model

| ID          | Status  | Location |
|-------------|---------|----------|
| REPORT-01  | Covered | skills/plugin-maintenance/references/output-format.md |
| REPORT-02  | Covered | skills/plugin-maintenance/references/output-format.md |
| REPORT-03  | Covered | skills/plugin-maintenance/references/output-format.md |
| REPORT-04  | Covered | skills/plugin-maintenance/references/output-format.md |
| REPORT-05  | Covered | skills/plugin-maintenance/SKILL.md |
| REPORT-06  | Covered | skills/plugin-maintenance/SKILL.md |
| REPORT-07  | Covered | skills/plugin-maintenance/SKILL.md |
