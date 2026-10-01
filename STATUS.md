# shipshape — Implementation Status

Tracks coverage of the requirements in [SPEC.md](./SPEC.md) against the single
in-repo implementation. Status vocabulary: **Covered** · **Partial** ·
**Missing** · **Contradicts**.

**Coverage: 115/115 requirements Covered (100%)**
**Evidence pointers:** file

Location holds the file. To find the spot inside it, grep for the requirement
id: every covering site carries a `covers:` marker naming the ids implemented
there, as an HTML comment under the heading in markdown and a `#` comment above
the block in shell. `grep -rn 'covers:.*RECON-08' skills hooks scripts` is the
lookup. Keeping the id in the source rather than restating each heading here
means an edit can't leave the two disagreeing.

## HARNESS — The entry point

| ID          | Status  | Location |
|-------------|---------|----------|
| HARNESS-01 | Covered | skills/maintain-harness/SKILL.md |
| HARNESS-02 | Covered | skills/maintain-harness/SKILL.md |
| HARNESS-03 | Covered | skills/maintain-harness/SKILL.md |
| HARNESS-04 | Covered | skills/maintain-harness/SKILL.md |
| HARNESS-05 | Covered | skills/maintain-harness/SKILL.md |
| HARNESS-06 | Covered | skills/maintain-harness/SKILL.md; scripts/maintenance-lock.sh |
| HARNESS-07 | Covered | skills/maintain-harness/SKILL.md; hooks/check-claude-code-version.sh |

## RECON — Reconciliation

| ID          | Status  | Location |
|-------------|---------|----------|
| RECON-01   | Covered | skills/maintain-harness/references/plugins.md; scripts/maintenance-lock.sh |
| RECON-02   | Covered | skills/maintain-harness/references/plugins.md |
| RECON-03   | Covered | skills/maintain-harness/references/plugins.md; scripts/maintenance-lock.sh |
| RECON-04   | Covered | skills/maintain-harness/references/plugins.md |
| RECON-05   | Covered | skills/maintain-harness/references/plugins.md |
| RECON-06   | Covered | skills/maintain-harness/references/plugins.md |
| RECON-07   | Covered | skills/maintain-harness/references/plugins.md |
| RECON-08   | Covered | skills/maintain-harness/references/plugins.md |
| RECON-09   | Covered | skills/maintain-harness/references/plugins.md |
| RECON-10   | Covered | skills/maintain-harness/references/plugins.md |
| RECON-11   | Covered | skills/maintain-harness/references/plugins.md |
| RECON-11a  | Covered | skills/maintain-harness/references/plugins.md |
| RECON-12   | Covered | skills/maintain-harness/references/plugins.md |
| RECON-13   | Covered | skills/maintain-harness/references/plugins.md |
| RECON-14   | Covered | skills/maintain-harness/references/plugins.md |
| RECON-15   | Covered | scripts/maintenance-lock.sh |
| RECON-16   | Covered | skills/maintain-harness/references/plugins.md; skills/maintain-harness/references/output-format.md; scripts/plugin-unmanaged.sh |

## GUARD — Guardrails

| ID          | Status  | Location |
|-------------|---------|----------|
| GUARD-01   | Covered | skills/maintain-harness/references/plugins.md |
| GUARD-02   | Covered | skills/maintain-harness/references/plugins.md |
| GUARD-03   | Covered | skills/maintain-harness/references/plugins.md |

## PRUNE — Pruning

| ID          | Status  | Location |
|-------------|---------|----------|
| PRUNE-01   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-scan.sh |
| PRUNE-02   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-scan.sh |
| PRUNE-03   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-scan.sh |
| PRUNE-04   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-scan.sh |
| PRUNE-05   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-scan.sh |
| PRUNE-06   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-prune.sh |
| PRUNE-07   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-in-use.sh |
| PRUNE-08   | Covered | skills/maintain-harness/references/plugins.md |
| PRUNE-09   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-prune.sh |
| PRUNE-10   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-prune.sh |
| PRUNE-11   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-prune.sh |
| PRUNE-12   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-scan.sh |
| PRUNE-13   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-prune.sh |
| PRUNE-14   | Covered | scripts/plugin-cache-prune.sh |
| PRUNE-15   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-prune.sh |
| PRUNE-16   | Covered | skills/maintain-harness/references/plugins.md; scripts/plugin-cache-scan.sh; scripts/plugin-cache-prune.sh |
| PRUNE-17   | Covered | scripts/plugin-cache-scan.sh |
| PRUNE-18   | Covered | scripts/plugin-cache-scan.sh |

## AUTO — Auto-update enforcement

| ID          | Status  | Location |
|-------------|---------|----------|
| AUTO-01    | Covered | hooks/enforce-autoupdate.sh |
| AUTO-02    | Covered | hooks/enforce-autoupdate.sh |
| AUTO-03    | Covered | hooks/enforce-autoupdate.sh |
| AUTO-04    | Covered | hooks/enforce-autoupdate.sh |
| AUTO-05    | Covered | hooks/enforce-autoupdate.sh |
| AUTO-06    | Covered | skills/maintain-harness/references/plugins.md |

## VERSION — Claude Code version changes

| ID          | Status  | Location |
|-------------|---------|----------|
| VERSION-01 | Covered | hooks/check-claude-code-version.sh |
| VERSION-02 | Covered | hooks/check-claude-code-version.sh |
| VERSION-03 | Covered | hooks/check-claude-code-version.sh |
| VERSION-04 | Covered | hooks/check-claude-code-version.sh |
| VERSION-05 | Covered | hooks/check-claude-code-version.sh |
| VERSION-06 | Covered | hooks/check-claude-code-version.sh |
| VERSION-07 | Covered | hooks/check-claude-code-version.sh |
| VERSION-08 | Covered | hooks/check-claude-code-version.sh |
| VERSION-09 | Covered | hooks/check-claude-code-version.sh |
| VERSION-10 | Covered | hooks/check-claude-code-version.sh |
| VERSION-11 | Covered | hooks/check-claude-code-version.sh |
| VERSION-12 | Covered | hooks/check-claude-code-version.sh |
| VERSION-13 | Covered | hooks/check-claude-code-version.sh |
| VERSION-14 | Covered | hooks/check-claude-code-version.sh |
| VERSION-15 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-16 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-17 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-18 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-19 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-20 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-21 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-22 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-23 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-24 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-25 | Covered | skills/maintain-harness/references/deep-scan-set.md; scripts/version-scan-targets.sh |
| VERSION-26 | Covered | scripts/version-scan-targets.sh; skills/maintain-harness/references/deep-scan-set.md |
| VERSION-27 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-28 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-29 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-30 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-31 | Covered | skills/maintain-harness/references/claude-code.md |
| VERSION-32 | Covered | skills/maintain-harness/references/claude-code.md; skills/maintain-harness/references/default-guide.md |
| VERSION-33 | Covered | skills/maintain-harness/references/default-guide.md |
| VERSION-34 | Covered | scripts/version-scan-targets.sh; skills/maintain-harness/references/deep-scan-set.md |
| VERSION-35 | Covered | scripts/version-scan-targets.sh; skills/maintain-harness/references/default-guide.md |
| VERSION-36 | Covered | skills/maintain-harness/references/claude-code.md; skills/maintain-harness/references/first-run.md |
| VERSION-37 | Covered | skills/maintain-harness/references/first-run.md |
| VERSION-38 | Covered | skills/maintain-harness/references/first-run.md |
| VERSION-39 | Covered | hooks/check-claude-code-version.sh; skills/maintain-harness/references/claude-code.md; skills/maintain-harness/references/first-run.md |
| VERSION-40 | Covered | scripts/version-scan-targets.sh; skills/maintain-harness/references/deep-scan-set.md |
| VERSION-41 | Covered | skills/maintain-harness/references/default-guide.md; skills/maintain-harness/references/claude-code.md |
| VERSION-42 | Covered | scripts/plugin-data-dir.sh; hooks/check-claude-code-version.sh; scripts/version-scan-targets.sh |
| VERSION-43 | Covered | scripts/version-scan-targets.sh |

## GUIDE — The harness maintenance guide

| ID          | Status  | Location |
|-------------|---------|----------|
| GUIDE-01   | Covered | scripts/harness-guide.sh |
| GUIDE-02   | Covered | scripts/harness-guide.sh |
| GUIDE-03   | Covered | scripts/harness-guide.sh |
| GUIDE-04   | Covered | scripts/harness-guide.sh; scripts/guide-content.sh |
| GUIDE-05   | Covered | scripts/harness-guide.sh |
| GUIDE-06   | Covered | scripts/harness-guide.sh |
| GUIDE-07   | Covered | skills/maintain-harness/references/guide.md; skills/maintain-harness/references/plugins.md |
| GUIDE-08   | Covered | skills/maintain-harness/references/guide.md |
| GUIDE-09   | Covered | skills/maintain-harness/references/plugins.md |
| GUIDE-10   | Covered | skills/maintain-harness/references/plugins.md |
| GUIDE-11   | Covered | skills/maintain-harness/references/plugins.md; skills/maintain-harness/references/output-format.md |
| GUIDE-12   | Covered | scripts/harness-guide.sh; skills/maintain-harness/references/guide.md |

## REPORT — Reporting & output model

| ID          | Status  | Location |
|-------------|---------|----------|
| REPORT-01  | Covered | skills/maintain-harness/references/output-format.md |
| REPORT-02  | Covered | skills/maintain-harness/references/output-format.md |
| REPORT-03  | Covered | skills/maintain-harness/references/output-format.md |
| REPORT-04  | Covered | skills/maintain-harness/references/output-format.md |
| REPORT-05  | Covered | skills/maintain-harness/references/plugins.md |
| REPORT-06  | Covered | skills/maintain-harness/references/plugins.md |
| REPORT-07  | Covered | skills/maintain-harness/references/plugins.md |
| REPORT-08  | Covered | scripts/offer-guard.sh; skills/maintain-harness/SKILL.md |
| REPORT-09  | Covered | scripts/offer-guard.sh |
