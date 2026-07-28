# shipshape — Implementation Status

Tracks coverage of the requirements in [SPEC.md](./SPEC.md) against the single
in-repo implementation. Status vocabulary: **Covered** · **Partial** ·
**Missing** · **Contradicts**.

**Coverage: 66/66 requirements Covered (100%)**

## RCON — Reconciliation

| ID      | Status  | Location |
|---------|---------|----------|
| RCON-01 | Covered | skills/plugin-maintenance/SKILL.md:80; scripts/plugin-maintenance-lock.sh |
| RCON-02 | Covered | skills/plugin-maintenance/SKILL.md:84 |
| RCON-03 | Covered | skills/plugin-maintenance/SKILL.md:86; scripts/plugin-maintenance-lock.sh |
| RCON-04 | Covered | skills/plugin-maintenance/SKILL.md:226 |
| RCON-05 | Covered | skills/plugin-maintenance/SKILL.md:93 |
| RCON-06 | Covered | skills/plugin-maintenance/SKILL.md:100 |
| RCON-07 | Covered | skills/plugin-maintenance/SKILL.md:125 |
| RCON-08 | Covered | skills/plugin-maintenance/SKILL.md:131 |
| RCON-09 | Covered | skills/plugin-maintenance/SKILL.md:136 |
| RCON-10 | Covered | skills/plugin-maintenance/SKILL.md:147 |
| RCON-11 | Covered | skills/plugin-maintenance/SKILL.md:144 |
| RCON-12 | Covered | skills/plugin-maintenance/SKILL.md:234 |
| RCON-13 | Covered | skills/plugin-maintenance/SKILL.md:243 |

## GARD — Guardrails

| ID      | Status  | Location |
|---------|---------|----------|
| GARD-01 | Covered | skills/plugin-maintenance/SKILL.md:145 |
| GARD-02 | Covered | skills/plugin-maintenance/SKILL.md:143 |
| GARD-03 | Covered | skills/plugin-maintenance/SKILL.md:30 |

## PRUN — Pruning

| ID      | Status  | Location |
|---------|---------|----------|
| PRUN-01 | Covered | skills/plugin-maintenance/SKILL.md:153 |
| PRUN-02 | Covered | skills/plugin-maintenance/SKILL.md:166 |
| PRUN-03 | Covered | skills/plugin-maintenance/SKILL.md:167 |
| PRUN-04 | Covered | skills/plugin-maintenance/SKILL.md:168 |
| PRUN-05 | Covered | skills/plugin-maintenance/SKILL.md:169 |
| PRUN-06 | Covered | skills/plugin-maintenance/SKILL.md:173 |
| PRUN-07 | Covered | skills/plugin-maintenance/SKILL.md:181; scripts/plugin-cache-in-use.sh |
| PRUN-08 | Covered | skills/plugin-maintenance/SKILL.md:177 |
| PRUN-09 | Covered | skills/plugin-maintenance/SKILL.md:215 |
| PRUN-10 | Covered | skills/plugin-maintenance/SKILL.md:216 |
| PRUN-11 | Covered | skills/plugin-maintenance/SKILL.md:219 |

## AUTO — Auto-update enforcement

| ID      | Status  | Location |
|---------|---------|----------|
| AUTO-01 | Covered | hooks/enforce-autoupdate.sh |
| AUTO-02 | Covered | hooks/enforce-autoupdate.sh |
| AUTO-03 | Covered | hooks/enforce-autoupdate.sh |
| AUTO-04 | Covered | hooks/enforce-autoupdate.sh |
| AUTO-05 | Covered | hooks/enforce-autoupdate.sh |
| AUTO-06 | Covered | skills/plugin-maintenance/SKILL.md:116 |

## PIN — Local-checkout pins

| ID      | Status  | Location |
|---------|---------|----------|
| PIN-01  | Covered | scripts/pin-plugin (`cmd_pin`) |
| PIN-02  | Covered | scripts/pin-plugin (`validate_checkout`) |
| PIN-03  | Covered | scripts/pin-plugin (`cmd_pin`) |
| PIN-04  | Covered | scripts/pin-plugin (`cmd_pin`) |
| PIN-05  | Covered | scripts/pin-plugin (`assert_repointable`) |
| PIN-06  | Covered | scripts/pin-plugin (`resolve_one`) |
| PIN-07  | Covered | scripts/pin-plugin (`cmd_pin`) |
| PIN-08  | Covered | scripts/pin-plugin (`cmd_pin`) |
| PIN-09  | Covered | scripts/pin-plugin (`repoint`) |
| PIN-10  | Covered | scripts/pin-plugin (`cmd_unpin`) |
| PIN-11  | Covered | scripts/pin-plugin (`cmd_unpin`) |
| PIN-12  | Covered | scripts/pin-plugin (`cmd_list`, `cmd_is_pinned`) |
| PIN-13  | Covered | scripts/pin-plugin (`cmd_reconcile`) |
| PIN-14  | Covered | scripts/pin-plugin (`cmd_reconcile`) |
| PIN-15  | Covered | scripts/pin-plugin (`take_lock`) |
| PIN-16  | Covered | scripts/pin-plugin (`write_json`) |
| PIN-17  | Covered | skills/plugin-maintenance/SKILL.md (Step 2) |
| PIN-18  | Covered | skills/plugin-maintenance/SKILL.md (Steps 4-5) |
| PIN-19  | Covered | skills/plugin-maintenance/SKILL.md (Step 3) |
| PIN-20  | Covered | docs/README.md (Pinning a plugin to a local checkout) |
| PIN-21  | Covered | scripts/pin-plugin (header); docs/README.md |
| PIN-22  | Covered | scripts/pin-plugin (`validate_checkout`) |
| PIN-23  | Covered | scripts/pin-plugin (`assert_repointable`) |
| PIN-24  | Covered | scripts/pin-plugin (`assert_pins_readable`) |
| PIN-25  | Covered | scripts/pin-plugin (`cmd_is_pinned`) |
| PIN-26  | Covered | scripts/pin-plugin (`PLUGIN_MAINT_OWNER`); scripts/plugin-maintenance-lock.sh |

## RPRT — Reporting & output model

| ID      | Status  | Location |
|---------|---------|----------|
| RPRT-01 | Covered | skills/plugin-maintenance/SKILL.md:59; skills/plugin-maintenance/references/output-format.md |
| RPRT-02 | Covered | skills/plugin-maintenance/SKILL.md:61 |
| RPRT-03 | Covered | skills/plugin-maintenance/references/output-format.md |
| RPRT-04 | Covered | skills/plugin-maintenance/SKILL.md:71 |
| RPRT-05 | Covered | skills/plugin-maintenance/SKILL.md:191 |
| RPRT-06 | Covered | skills/plugin-maintenance/SKILL.md:64 |
| RPRT-07 | Covered | skills/plugin-maintenance/SKILL.md:70 |
