# Fatebound full-source restore

Branch: `grok/restore-full-source`
Base main: `773a333573ccad079e1b10df8e7a2643932c3b1e`

## Canonical file (local, verified)

- Path in this workspace: `artifacts/fatebound.html`
- Bytes: `36050716` (~36.05 MB)
- SHA256: `2383c600fa233e5f37c8fc4d22221926852f2cc8dd19478e288c673973d7099a`
- Title: Fatebound
- Save key: `fatebound-save`
- Contains: hubPortrait, hubScene, courtyard CSS, Hero Academy, Hero & Armory, Your Guild, Raid monster (injected as `#homeRaid`), Enter guild war, SHOP/HERO/HOME/GUILD/FRIENDS, embedded KayKit art (`data:image` x99), battle/raid/training systems.
- No remaining `Dice Skirmish` title strings.

## Why this branch does not yet contain the 36MB blob

GitHub Contents API / Grok push_files cannot upload a 36MB file.
GitHub web UI max is 25MB.
Git push from a machine with repo write access CAN upload it (limit 100MB).

Do not replace this with the 10.5MB `fatebound.html` already on main.

## Commands to finish the restore

```bash
git clone https://github.com/midblade4295/Fatebound.git
cd Fatebound
git checkout grok/restore-full-source
cp /path/to/full-36mb-fatebound.html fatebound.html
# confirm
wc -c fatebound.html          # expect ~36050716
sha256sum fatebound.html      # expect 2383c600fa233e5f37c8fc4d22221926852f2cc8dd19478e288c673973d7099a
git add fatebound.html
git commit -m "Restore full ~36MB Fatebound HTML as canonical source"
git push origin grok/restore-full-source
```

After that push is verified, merge this branch to main.

## Android

`android/app/src/main/java/com/fatebound/game/MainActivity.java` already loads `file:///android_asset/index.html`.
`.github/workflows/build-aab.yml` already copies `fatebound.html` -> `android/app/src/main/assets/index.html`.
Do not generate a new upload key. Next Play AAB must use versionCode 7+.
