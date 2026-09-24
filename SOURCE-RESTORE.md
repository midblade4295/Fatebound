# Historical Fatebound full-source restore

> **Superseded by the user-approved v108 promotion.** The current source is `main:fatebound.html`, HTML build `108-season-pass-modal-copy-fix`, 36,175,422 bytes, SHA-256 `91f84e86994701bcdaef6591c0b99ce43b92d99a73be1b283b03ada9068c04d8`. Read `GROKBOT_HANDOFF.md` and `fatebound-source.json`. Do not rerun the old restore commands below or replace current main with the older source/checksum. The old versionCode advice below is also historical; verify Play Console before a new release.

The original restoration notes are retained below for provenance only.

---

Branch: `grok/restore-full-source`
Base main: `773a333573ccad079e1b10df8e7a2643932c3b1e`

## Original canonical file (historical)

- Path in that workspace: `artifacts/fatebound.html`
- Bytes: `36050716` (~36.05 MB)
- SHA256: `2383c600fa233e5f37c8fc4d22221926852f2cc8dd19478e288c673973d7099a`
- Title: Fatebound
- Save key: `fatebound-save`
- Contains: hubPortrait, hubScene, courtyard CSS, Hero Academy, Hero & Armory, Your Guild, Raid monster (injected as `#homeRaid`), Enter guild war, SHOP/HERO/HOME/GUILD/FRIENDS, embedded KayKit art (`data:image` x99), battle/raid/training systems.
- No remaining `Dice Skirmish` title strings.

## Original restore context (not current status)

The original branch did not yet contain the 36MB blob. Those notes discussed a 10.5MB incomplete file, a web-upload size limit, and restoring the full file using git. That restoration is not the current task; the later v108 source has superseded it.

## Old commands — do not execute against current main

```bash
git clone https://github.com/midblade4295/Fatebound.git
cd Fatebound
git checkout grok/restore-full-source
cp /path/to/full-36mb-fatebound.html fatebound.html
wc -c fatebound.html
sha256sum fatebound.html
git add fatebound.html
git commit -m "Restore full ~36MB Fatebound HTML as canonical source"
git push origin grok/restore-full-source
```

## Android context

`android/app/src/main/java/com/fatebound/game/MainActivity.java` loads `file:///android_asset/index.html`.
`.github/workflows/build-aab.yml` copies `fatebound.html` to `android/app/src/main/assets/index.html`.
Do not generate a new upload key. The original note's "versionCode 7+" guidance is obsolete; read the current handoff and check actual Play release history.
