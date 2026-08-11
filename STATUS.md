# shipshape — Implementation Status

Tracks coverage of the requirements in [SPEC.md](./SPEC.md) against the single
in-repo implementation. Status vocabulary: **Covered** · **Partial** ·
**Missing** · **Contradicts**.

**Coverage: 56/56 requirements Covered (100%)**

## RECON — Reconciliation

| ID          | Status  | Location |
|-------------|---------|----------|
| RECON-01    | Covered | skills/plugin-maintenance/SKILL.md:80; scripts/plugin-maintenance-lock.sh |
| RECON-02    | Covered | skills/plugin-maintenance/SKILL.md:84 |
| RECON-03    | Covered | skills/plugin-maintenance/SKILL.md:86; scripts/plugin-maintenance-lock.sh |
| RECON-04    | Covered | skills/plugin-maintenance/SKILL.md:226 |
| RECON-05    | Covered | skills/plugin-maintenance/SKILL.md:93 |
| RECON-06    | Covered | skills/plugin-maintenance/SKILL.md:100 |
| RECON-07    | Covered | skills/plugin-maintenance/SKILL.md:125 |
| RECON-08    | Covered | skills/plugin-maintenance/SKILL.md:131 |
| RECON-09    | Covered | skills/plugin-maintenance/SKILL.md:136 |
| RECON-10    | Covered | skills/plugin-maintenance/SKILL.md:147 |
| RECON-11    | Covered | skills/plugin-maintenance/SKILL.md:144 |
| RECON-12    | Covered | skills/plugin-maintenance/SKILL.md:234 |
| RECON-13    | Covered | skills/plugin-maintenance/SKILL.md:243 |

## GUARD — Guardrails

| ID          | Status  | Location |
|-------------|---------|----------|
| GUARD-01    | Covered | skills/plugin-maintenance/SKILL.md:145 |
| GUARD-02    | Covered | skills/plugin-maintenance/SKILL.md:143 |
| GUARD-03    | Covered | skills/plugin-maintenance/SKILL.md:30 |

## PRUNE — Pruning

| ID          | Status  | Location |
|-------------|---------|----------|
| PRUNE-01    | Covered | skills/plugin-maintenance/SKILL.md:153 |
| PRUNE-02    | Covered | skills/plugin-maintenance/SKILL.md:166 |
| PRUNE-03    | Covered | skills/plugin-maintenance/SKILL.md:167 |
| PRUNE-04    | Covered | skills/plugin-maintenance/SKILL.md:168 |
| PRUNE-05    | Covered | skills/plugin-maintenance/SKILL.md:169 |
| PRUNE-06    | Covered | skills/plugin-maintenance/SKILL.md:173 |
| PRUNE-07    | Covered | skills/plugin-maintenance/SKILL.md:181; scripts/plugin-cache-in-use.sh |
| PRUNE-08    | Covered | skills/plugin-maintenance/SKILL.md:177 |
| PRUNE-09    | Covered | skills/plugin-maintenance/SKILL.md:215 |
| PRUNE-10    | Covered | skills/plugin-maintenance/SKILL.md:216 |
| PRUNE-11    | Covered | skills/plugin-maintenance/SKILL.md:219 |

## AUTO — Auto-update enforcement

| ID          | Status  | Location |
|-------------|---------|----------|
| AUTO-01     | Covered | hooks/enforce-autoupdate.sh |
| AUTO-02     | Covered | hooks/enforce-autoupdate.sh |
| AUTO-03     | Covered | hooks/enforce-autoupdate.sh |
| AUTO-04     | Covered | hooks/enforce-autoupdate.sh |
| AUTO-05     | Covered | hooks/enforce-autoupdate.sh |
| AUTO-06     | Covered | skills/plugin-maintenance/SKILL.md:116 |

## VERSION — Claude Code version changes

| ID          | Status  | Location |
|-------------|---------|----------|
| VERSION-01  | Covered | hooks/claude-code-version.sh (`read_version`) |
| VERSION-02  | Covered | hooks/claude-code-version.sh (banner) |
| VERSION-03  | Covered | hooks/claude-code-version.sh (banner) |
| VERSION-04  | Covered | hooks/claude-code-version.sh (emit) |
| VERSION-05  | Covered | hooks/claude-code-version.sh (`content`, emit) |
| VERSION-06  | Covered | hooks/claude-code-version.sh (seed) |
| VERSION-07  | Covered | hooks/claude-code-version.sh (`content`) |
| VERSION-08  | Covered | hooks/claude-code-version.sh (banner) |
| VERSION-09  | Covered | hooks/claude-code-version.sh (ack mode) |
| VERSION-10  | Covered | hooks/claude-code-version.sh (emit) |
| VERSION-11  | Covered | hooks/claude-code-version.sh (marker read) |
| VERSION-12  | Covered | hooks/claude-code-version.sh (opt-out) |
| VERSION-13  | Covered | hooks/claude-code-version.sh (`read_version`) |
| VERSION-14  | Covered | hooks/claude-code-version.sh (`bail`) |
| VERSION-15  | Covered | hooks/claude-code-version.sh (`content` END) |
| VERSION-16  | Covered | hooks/claude-code-version.sh (`bail`) |

## REPORT — Reporting & output model

| ID          | Status  | Location |
|-------------|---------|----------|
| REPORT-01   | Covered | skills/plugin-maintenance/SKILL.md:59; skills/plugin-maintenance/references/output-format.md |
| REPORT-02   | Covered | skills/plugin-maintenance/SKILL.md:61 |
| REPORT-03   | Covered | skills/plugin-maintenance/references/output-format.md |
| REPORT-04   | Covered | skills/plugin-maintenance/SKILL.md:71 |
| REPORT-05   | Covered | skills/plugin-maintenance/SKILL.md:191 |
| REPORT-06   | Covered | skills/plugin-maintenance/SKILL.md:64 |
| REPORT-07   | Covered | skills/plugin-maintenance/SKILL.md:70 |
