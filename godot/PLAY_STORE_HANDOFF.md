# Fatebound: Play Store handoff for Grokbot

Updated 2026-10-07 (replaces the 2026-09-29 version). This is the current release guide; it takes precedence over
historical Play/build notes in the other handoffs.

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
| **What a phone downloads from Play** (one ABI) | **~160 MB** (estimate: game data + one engine + ~3 MB other) |
| The `.aab` file you upload (all 4 ABIs) | ~230 MB (estimate) |
| Preview APK on itch (arm64 only, debug engine) | 162.6 MB |

Google Play's limits for app bundles: 500 MB per module (compressed download), 4 GB for everything delivered at
install (https://support.google.com/googleplay/android-developer/answer/9859372). The game is well inside them; no
asset packs or on-demand delivery are needed. Godot's Gradle export puts the game data in an install-time asset pack
(`assetPackInstallTime`), which the verifier accepts. Record the real AAB size and Play Console's reported download size.

## Release identity and version

Preset **Android Play Store** in `godot/export_presets.cfg`:

| Setting | Value |
| --- | --- |
| Application ID | `com.fatebound.game` |
| App name | `Fatebound` |
| Output | Signed release `.aab` (Gradle build) |
| ABIs | armeabi-v7a, arm64-v8a, x86, x86_64 |
| Engine/templates | Godot 4.7.2 + matching Android build template |
| Renderer | **Vulkan (mobile) by default, OpenGL fallback ON** -- see below. Do not turn the fallback off. |
| SDK | min 24, target 36; verify against current Play requirements |
| Export excludes | `tests/*, reports/*, tools/*, server/*, store-listing/*` (server and listing files are never shipped) |

The preset still says versionCode 23 / versionName 1.1.1. In Play Console, check every track and *Latest releases and
bundles*; choose a versionCode higher than anything ever uploaded and a versionName (e.g. `0.31.72`). Set both in the
preset AND in `godot/tools/verify_play_bundle.py` (it still expects 24 / `1.2.0-siege-online`). Don't infer the code
from preview codes (158), the old handoff's 24, or workflow file names.

## Renderer: Vulkan with OpenGL fallback (Kevin, 2026-10-07)

Testers on Mali-GPU phones (Pixel 7 Pro, vivo S30 mini, Redmi Note 15 Pro) froze on the splash on Vulkan. Kevin chose to
keep Vulkan as the default and add fallbacks (0.31.72):
- `rendering/rendering_device/fallback_to_opengl3` = true (Godot's own fallback for phones without usable Vulkan).
  It equals the engine default, so Godot leaves it **out** of `project.binary`: missing = on.
- `application/config/project_settings_override="user://renderer.cfg"` + the **BootGuard** autoload
  (`scripts/app/boot_guard.gd`): after a Vulkan start that never reached the menu, the next start switches that phone
  to OpenGL. Settings has a manual switch.
`verify_play_bundle.py` now checks exactly this (fallback on, the override path, BootGuard present).

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
  min/target SDK, the four ABIs, 64-bit library alignment.
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
is not yet confirmed fixed on a real phone (0.31.72 adds the OpenGL fallback). Use only the track Kevin authorizes;
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
