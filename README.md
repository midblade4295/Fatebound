# Fatebound

Fatebound arena game plus an Android app bundle for Google Play.

## Current source of truth: v108

Use **`main` → `fatebound.html`**. This is the exact user-approved `fatebound-v108-season-pass-fix.html`, promoted after the input/menu freeze fixes and Season Pass update.

- HTML build: `108-season-pass-modal-copy-fix`
- Size: `36,175,422` bytes (full embedded-assets source)
- SHA-256: `91f84e86994701bcdaef6591c0b99ce43b92d99a73be1b283b03ada9068c04d8`
- Play Store name: **Fatebound**
- Android package: `com.fatebound.game`
- Save key: `fatebound-save`; battle-session compatibility: `106`

Read [GROKBOT_HANDOFF.md](GROKBOT_HANDOFF.md) and [AGENTS.md](AGENTS.md) before editing. Older branches, previous HTML attachments and the original restore checksum are not the current game. Start new work from freshly fetched `origin/main`; never replace this with a stripped debug file.

Verify the checked-out source with:

```bash
sha256sum -c fatebound-source.sha256
```

See [fatebound-source.json](fatebound-source.json), the [v108 runtime test report](docs/fatebound-v108-season-pass-test-report.md), and the [import verification](docs/v108-import-verification.json). The runtime report records prior Chromium/mobile-touch tests and their limitations. The promotion verifies exact bytes and parses the 18 inline scripts; it does not claim a new physical-phone test.

## Android builds

`.github/workflows/build-aab.yml` copies `fatebound.html` to `android/app/src/main/assets/index.html`, then builds the Android bundle. Edit the root source, not the generated asset.

HTML v108 and Android versionCode are separate. This source promotion does not change packaging or publish a Play release. Before the next release, check Play Console for the highest consumed versionCode and choose a larger one, updating the Android/version metadata together. A vc17 build already exists on an older-source branch; do not go back to that HTML to build a new release.

Use Actions → **Build Play Store AAB** for a requested build and the **fatebound-play-aab** artifact for its output. Keep the existing upload key; do not create a replacement key.

`SOURCE-RESTORE.md` is retained as historical provenance, not a current restore procedure.
