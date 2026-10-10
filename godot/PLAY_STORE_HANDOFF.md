# Fatebound: Play Store handoff for Grokbot

Updated 2026-10-07 (replaces the 2026-09-29 version). This is the current release guide; it takes precedence over
historical Play/build notes in the other handoffs.

**In-app purchases (2026-10-09):** the merchant account, products, license testers and the purchase-check service
account are in `godot/PLAY_IAP_HANDOFF.md`.

## What to upload

**One file: a signed release Android App Bundle (`.aab`)** exported with the Godot preset **Android Play Store**, for
the existing app **Fatebound** (`com.fatebound.game`).

Do **not** upload:
- the itch.io / preview APKs (`Fatebound-0_31_*.apk`): package `com.fatebound.kaykitrebuild`, debug build, signed with
  the *preview* key (`fatebound-siege-preview.jks`, cert `10:11:FC:79...`). They are not an update for the Play app and
  Play would reject them;
- anything built by `godot/tools/build_siege_preview.sh`, a debug export, or anything signed with the preview key.

## Source

- Repository `https://github.com/midblade4295/Fatebound`, branch `main` (= `claude/siege-dev-r6`), commit `3bbc982` or
  newer reviewed commits. Game version 0.31.72 (preview versionCode 158; preview codes are unrelated to Play codes).
- Change log: `godot/SIEGE_PROGRESS.md`.

## Size (measured 2026-10-07)

| What | Size |
|---|---|
| Game data (models, textures, sounds, scripts) | 134.2 MB compressed, measured in the 0.31.72 build |
| Godot release engine, per ABI | ~23 MB compressed (4.7.2 release templates; arm64 22.9 + libc++ 0.4) |
| **What a phone downloads from Play** (one ABI) | **~35 MB** since 0.31.95 (engine, code, fonts), then ~181 MB of content packs from GitHub on first launch |
| The `.aab` file you upload (arm64 only since 2026-10-10) | ~35 MB since 0.31.95 (the art and sound are content packs) |
| Preview APK on itch (arm64 only, debug engine) | 162.6 MB |

Google Play's limits for app bundles: 500 MB per module (compressed download), 4 GB for everything delivered at
install (https://support.google.com/googleplay/android-developer/answer/9859372). The game is well inside them; no
asset packs or on-demand delivery are needed. Godot's Gradle export puts the game data in an install-time asset pack
(`assetPackInstallTime`), which the verifier accepts. Record the real AAB size and Play Console's reported download size.

## Content packs: the game's art and sound are downloaded on first launch (0.31.95)

Kevin (2026-10-10): "the main game installs a small file from the Play store and itch, then when they launch the
game after first install the game will say it's updating". The AAB now holds the engine, the scripts and scenes, the
fonts and the launcher art (~35 MB). The art and sound are 5 content packs (.pck, ~181 MB) on the repo's
`content-packs` branch, served by GitHub at `https://raw.githubusercontent.com/midblade4295/Fatebound/content-packs/`.
`godot/content/manifest.json` (in the build) lists each pack's file, size and SHA-256. On launch the loader
(`scenes/Boot.tscn`, `scripts/app/content_loader.gd`) shows "UPDATING", downloads what's missing (resumes, checks
the SHA-256), mounts the packs and starts the game. A code-only update downloads nothing.

- **Play policy**: the packs hold data only -- models, textures, sounds. No scripts or settings (the pack tool strips
  them and fails if any code is left); the downloaded files never replace the build's own. All code ships in the AAB.
- **Before building the AAB**: `python3 godot/tools/content_packs.py check` must print `CONTENT OK` (the packs this
  commit's manifest lists are on the branch, and the art hasn't changed since they were built). If it says a pack's
  files changed: `python3 godot/tools/content_packs.py build && python3 godot/tools/content_packs.py upload`, commit
  `godot/content/manifest.json`. `verify_play_bundle.py` runs `check` and `base` (no pack data in the bundle).
- **Data safety / privacy**: the app now downloads files from GitHub (no account, no data sent). privacy.html lists it
  (updated 10 October 2026); redeploy privacy.html with the build.
- The `content-packs` branch only grows (no force-push); old pack files stay for builds still installed.

## Release identity and version

Preset **Android Play Store** in `godot/export_presets.cfg`:

| Setting | Value |
| --- | --- |
| Application ID | `com.fatebound.game` |
| App name | `Fatebound` |
| Output | Signed release `.aab` (Gradle build) |
| ABIs | arm64-v8a only (32-bit ARM dropped 2026-10-10, Kevin: "Ok drop the 32bit"; x86 and x86_64 before) |
| Engine/templates | Godot 4.7.2 + matching Android build template |
| Renderer | **Vulkan (mobile) only, OpenGL fallback OFF** (0.31.92) -- see below. |
| SDK | min 29 (Android 10, Kevin 2026-10-09: Vulkan only), target 36; verify against current Play requirements |
| Export excludes | `tests/*, reports/*, tools/*, server/*, store-listing/*` (never shipped) and every content pack's folders (`tools/content_packs.py presets` writes them) |

The preset still says versionCode 23 / versionName 1.1.1. In Play Console, check every track and *Latest releases and
bundles*; choose a versionCode higher than anything ever uploaded and a versionName (e.g. `0.31.72`). Set both in the
preset AND in `godot/tools/verify_play_bundle.py` (it still expects 24 / `1.2.0-siege-online`). Don't infer the code
from preview codes (158), the old handoff's 24, or workflow file names.

## Renderer: Vulkan only (Kevin, 2026-10-09)

0.31.72 added an OpenGL fallback after testers' phones froze on the splash. Kevin's S21 then froze the same way on a
fresh Play install: a start-up deadlock in the game's background loading with an empty shader cache (fixed in 0.31.91),
very likely the testers' freeze too. With Vulkan working, Kevin removed OpenGL (0.31.92):
- `rendering/rendering_device/fallback_to_opengl3=false`. Godot then marks `android.hardware.vulkan.version` (1.1) as
  **required** in the manifest, so Play doesn't offer the game to phones without Vulkan 1.1.
- No `application/config/project_settings_override` (the old `user://renderer.cfg` OpenGL switch); BootGuard deletes
  that file on phones that still have it and keeps only its start-up log and safe start.
`verify_play_bundle.py` checks exactly this (fallback off, no override, the manifest requirement, BootGuard present).
Min SDK is 29 (Android 10), as Godot recommends for Vulkan: Kevin, 2026-10-09. Android 7-9 was ~8% of active devices
(Google, Dec 2025), mostly phones with old Vulkan drivers or none.

## Signing: private credentials only

Unchanged rules. The signing-key file was removed from the R5 branch history; older history still contains previously
exposed signing material. Never restore `android/keystore/upload.jks.b64`, take a key from old commits, or commit a
private key/password/service-account JSON.

Use the upload key currently registered for **this app** in Play Console, supplied through private GitHub Actions
secrets or an authorized private signing environment. If the exposed key was reset, use the replacement only once Play
Console has accepted it. Do not create a new key and assume Play accepts it. Suggested secret names (not confirmed to
exist): `PLAY_UPLOAD_KEYSTORE_B64`, `PLAY_UPLOAD_KEY_ALIAS`, `PLAY_UPLOAD_STORE_PASSWORD`, `PLAY_UPLOAD_KEY_PASSWORD`.

Compare the signed AAB's certificate with the **current upload certificate** in Play Console (App integrity / App
signing). `verify_play_bundle.py` hardcodes the historical SHA-256 `6971a912...84`; confirm it against the Console,
especially after a key reset, and update it if the Console's upload certificate differs.

## Build setup still to correct (not done here)

1. `.github/workflows/build-native-play.yml` names vc22 outputs and a historical branch; don't run it unchanged.
2. `godot/tools/ci_restore_play_signing.py` replays the old signing stage that expects the removed repository key.
   Replace it with private secrets.
3. Set the verified versionCode/versionName in the preset and the verifier (above), and artifact names to match.
   Editing workflow files needs GitHub auth with workflow permission; don't bypass that.

Done on 2026-10-07: the Play preset excludes `server/*` and `store-listing/*`; the verifier's renderer checks match
0.31.72 and it also rejects `store-listing` files.

## Build

On the exact release source, run `GODOT=/path/to/godot godot/tools/run_siege_tests.sh` (34 tests). JDK 17+, Android
SDK + build-tools 35, Godot 4.7.2 + Android build template. Then, from the repository root:

```bash
# Supply these privately in the authorized build environment.
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PLAY_UPLOAD_KEYSTORE_PATH"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$PLAY_UPLOAD_KEY_ALIAS"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PLAY_UPLOAD_KEY_PASSWORD"
mkdir -p godot/build
"$GODOT" --headless --editor --path godot --import
"$GODOT" --headless --path godot --install-android-build-template \
  --export-release "Android Play Store" \
  "$PWD/godot/build/Fatebound-Play-release.aab"
```

## Validate before upload

- `python3 godot/tools/verify_play_bundle.py godot/build/Fatebound-Play-release.aab` (after setting the version
  expectations), bundletool validation / manifest inspection, `jarsigner -verify`.
- Manifest: package `com.fatebound.game`, the chosen versionCode/versionName, debuggable=false, INTERNET permission,
  min/target SDK, arm64-v8a only, 64-bit library alignment.
- Record the AAB SHA-256, size, upload-certificate fingerprint, source commit, test results and the verifier report.
  Headless tests are not physical-phone testing.

## Online server: must be redeployed first

The client speaks **network protocol 35** (`Net.VERSION` in `scripts/siege/siege_net.gd`). Checked 2026-10-07: the
live server rejects it -- the probe from commit `3bbc982` got `PROBE_FAIL ... connection closed (code 4001)`, which is
`siege_server.gd`'s "version" rejection. Until the server is redeployed, online play from this build won't connect
(vs-bots and the tutorial are offline and unaffected).

- VM `legionary-alpha`, Google Cloud project `shardfall-5f5de`, zone `us-central1-a`, SSH user `midblade4295`,
  public IP `136.113.125.3`; service `fatebound-siege`; runtime `/opt/godot-4.7.2/godot`; live project
  `/srv/fatebound-siege`; port `127.0.0.1:8082` behind the existing Caddy. Public WebSocket
  `wss://136-113-125-3.sslip.io/fatebound/siege/ws`.
- Deploy exactly the files the server loads (checked 2026-10-07 by following its preloads):
  `server/siege_server.gd`, `server/siege_probe.gd`, `scripts/siege/siege_sim.gd`, `siege_land.gd`, `siege_castle.gd`,
  `siege_net.gd` -- from the same commit as the AAB. Back up first; `server/deploy/install_siege_server.sh` omitted
  land/castle in the past, so check it.
- Then: `systemctl is-active fatebound-siege` = active, and the probe prints `PROBE_OK` with snapshots:

```bash
SIEGE_PROBE_URL=wss://136-113-125-3.sslip.io/fatebound/siege/ws \
  /opt/godot-4.7.2/godot --headless --path /srv/fatebound-siege -s res://server/siege_probe.gd
```

## Store listing

`store-listing/README_FOR_AI.md`: en-US copy, eight phone screenshots, feature graphic, fastlane metadata. Listing
assets only (no app icon in the package). The screenshots predate 0.31.67's new shop buildings and 0.31.71's lighting;
ask Kevin whether to regenerate them.

## Upload in Play Console

Open the existing app **Fatebound** (`com.fatebound.game`). **Internal testing first**: the Mali-phone start-up freeze
is most likely the fresh-install deadlock fixed in 0.31.91; confirm on a tester's phone. Use only the track Kevin authorizes;
upload the validated AAB, write accurate release notes, resolve Console errors, and record acceptance, versionCode,
track and status. Uploading, saving a draft, submitting for review and rolling out are separate actions -- this
handoff authorizes none of them by itself. Don't invent credentials, upload permission, submission or approval; if
account access, the upload key or version history is missing, say exactly what is missing.

## Official references

- https://developer.android.com/studio/publish/upload-bundle
- https://support.google.com/googleplay/android-developer/answer/9859372 (size limits)
- https://support.google.com/googleplay/android-developer/answer/9859348
- https://support.google.com/googleplay/android-developer/answer/9842756
- https://support.google.com/googleplay/android-developer/answer/9859350
