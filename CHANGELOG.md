# Changelog

## 0.2.1

### Other
- Trimmed the `plugin-maintenance` skill's `description` frontmatter to cut the always-resident context cost. Kept the "sync plugins" / "update my plugins" cues; dropped the name-echo and redundant trigger phrases.

## 0.2.0

### Features
- Plugin reconciliation now guards against uninstalling a plugin shared by two registered marketplaces. When `claude plugin list` shows two rows for one plugin but `installed_plugins.json` records a single shared install, the extra is skipped — surfaced with the manifest evidence for you to resolve — instead of being uninstalled and taking the enabled copy down with it. Real uninstalls are verified against the manifest afterward, since `claude plugin uninstall` reports success regardless of effect.

## 0.1.1

### Changed
- Sharpened the description ("all your AI plugins" → "your Claude Code plugins") and aligned the marketplace suite metadata with the bridge.ai schema: group slug, declared `activations`, and dropped the derived accent, the passive flag, and the spoke flag.

## 0.1.0

Initial entry.
