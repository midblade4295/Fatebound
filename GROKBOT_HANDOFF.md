# Grokbot handoff — Fatebound v108 is the current baseline

Kevin explicitly requested that the approved `fatebound-v108-season-pass-fix.html` replace the older GitHub game as the most up-to-date version. After this promotion reaches `main`, use **`midblade4295/Fatebound`, branch `main`, file `fatebound.html`** as the source of truth.

## Exact approved source

- HTML build: `108-season-pass-modal-copy-fix`
- Bytes: `36175422`
- SHA-256: `91f84e86994701bcdaef6591c0b99ce43b92d99a73be1b283b03ada9068c04d8`
- Git blob SHA-1: `50f2d0a8bfb7fda523409aa224ff2351386609ad`
- Save key: `fatebound-save`
- Battle-session compatibility: `106` (intentionally not bumped by v108).
- Machine-readable reference: `fatebound-source.json`; checksum file: `fatebound-source.sha256`.

This is the full approximately 36 MB game with its embedded artwork, not a stripped test page. The imported `fatebound.html` must be byte-for-byte identical to the approved artifact. The earlier restore checksum beginning `2383c600`, old vc13/vc14 game source, touch-fix/vc17 branch source, and v94–v107 HTML copies are historical, not alternative current baselines. A newer Android versionCode on an old branch does not make its HTML newer than v108.

## Start work safely

```bash
git fetch origin
# Inspect the working tree first. Preserve uncommitted work; do not discard it.
git status --short
# With a clean tree, start a new, task-specific branch directly from current main:
git switch -c grok/<task-name> origin/main
sha256sum -c fatebound-source.sha256
wc -c fatebound.html
git log -1 --format='%H %s' -- fatebound.html
```

At this handoff the checksum must equal the v108 hash above. For later authorized work, compare the latest manifest and commit history before editing; never overwrite a newer main with this historical import. Do not continue an old feature branch without reconciling it with main. Do not force-push, hard-reset the user's work, blindly merge old whole-file replacements, or rerun historical restore/apply workflows. Use focused commits and report your branch, commit, source build and checksum. Do not edit the same branch concurrently with ChatGPT.

## Preserve these fixes and mechanics

Keep the v107 idempotent DOM-observer fix: moving the gift notification only when its position actually changes prevents the recursive callback/input freeze. Keep the hidden-Home layout fix so only the active menu occupies space, restored battle startup functions, usable ROLL/gift hit areas and unclipped Spell/Map controls.

Keep the dedicated five-minute match: Home/Shop/Hero/Guild/Friends navigation is hidden and locked during live battle, while the tower map remains available and the battlefield uses the freed space. Keep the existing four spells, Focus/ALL-IN, current training, rewards and artwork. Do not reintroduce document-wide click-swallowing tutorial gates or browser-history locks.

Keep the v108 Season Pass modal above Home and the other menus, with the level-up dialog above the pass; keep internal scrolling and accessible Close/Premium controls. Preserve the current Fate/Focus/spell-charge explanations, points-to-next-tier display, scroll retention and duplicate-claim protections. v108 changes pass presentation/copy, not the existing reward amounts, tier thresholds or Premium token cost.

Do not reset progress, season points, claimed rewards, Premium access, or save compatibility as part of this handoff. Do not replace the full file with a small mock/debug file. Do not change Legionary or its deployment.

## Verification and packaging

Read `docs/fatebound-v108-season-pass-test-report.md` for the existing 22-check report and its limits. It describes full-HTML Chromium tests with mobile/touch emulation, staged test saves and blocked external services, not physical-device or live multiplayer validation. `docs/v108-import-verification.json` records the promotion's separate checksum/size/JavaScript parsing checks; it does not claim those browser tests were rerun during import.

For future edits, test Home/menu navigation, pass open/scroll/claim/close including level-up rewards, battle start/roll/spell/map, battle completion/Claim & Home, and starting a second battle. Syntax checks alone are not proof that input works.

The Android workflow copies `fatebound.html` into `android/app/src/main/assets/index.html`; that asset is generated, not a second editable source. This promotion does not change Android packaging, the existing upload key, or publish to Google Play. HTML **v108 is not Android versionCode 108**. Main's packaging was vc14 / 1.0.13 at import, and the repository already contains an older-source vc17 build. Before the next Play release, check the highest versionCode actually used in Play Console and choose a strictly higher code (at least 18 based on the repository evidence), with matching version metadata. Do not reuse an older branch's HTML to get its packaging number.
