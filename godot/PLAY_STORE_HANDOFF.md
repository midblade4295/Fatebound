# Fatebound Siege: Play Store handoff for Grokbot

Updated 2026-09-29. This is the current release preparation guide; it takes precedence over historical Play/build notes in the other handoffs.

## Source and current deployment

- Repository: `https://github.com/midblade4295/Fatebound`
- Start from `claude/siege-dev-r5`, sanitized R5 source commit `d05f5851f388ed2689298fd98298538770189323`, then include newer reviewed commits on that branch.
- Preview source is 0.19.1. The supplied APK uses `com.fatebound.kaykitrebuild` and preview signing. It is not an update for the existing Play app.
- R5's six dedicated server scripts were deployed and hash-verified on 2026-09-29. Service `fatebound-siege` is active; the public probe returned `PROBE_OK` with 3 snapshots. Recheck before a release.
- Public WebSocket: `wss://136-113-125-3.sslip.io/fatebound/siege/ws`.
- VM: `legionary-alpha`, Google Cloud project `shardfall-5f5de`, zone `us-central1-a`, SSH user `midblade4295`, public IP `136.113.125.3`.
- Remote Desktop Commander device: `fd04eb44-4a0f-4902-b90e-a80b03ab9638`.
- Runtime: `/opt/godot-4.7.2/godot`; live project: `/srv/fatebound-siege`; service port: `127.0.0.1:8082` behind existing Caddy.
- New deployments must include `siege_sim.gd`, `siege_net.gd`, `siege_land.gd`, `siege_castle.gd`, `siege_server.gd`, and `siege_probe.gd`. The old installer omits land/castle dependencies; correct that before using it. Preserve backups and verify the public probe afterward.

## Release identity and version

Use Godot preset **Android Play Store** in `godot/export_presets.cfg`:

| Setting | Required value |
| --- | --- |
| Application ID | `com.fatebound.game` |
| App name | `Fatebound` |
| Output | Signed release `.aab` |
| Engine/templates | Godot 4.7.2, matching Android templates |
| Renderer | Vulkan mobile; OpenGL fallback disabled |
| SDK settings currently in source | min SDK 24, target SDK 36; verify current Play requirements |

Check the existing app in Play Console, including all testing/production tracks and Latest releases and bundles. Select a new unused versionCode greater than the highest uploaded code. Do not infer the next Play code from preview code 40, the handoff's earlier code 24, the preset's current code 23, or workflow filenames containing vc22. Record the verified next code and user-facing versionName, and update the Play preset and validation expectations together.

## Signing: private credentials only

The signing-key file was removed from the entire R5 branch history. Older repository branches/history still contain previously exposed signing material. Never restore `android/keystore/upload.jks.b64`, retrieve a key from those old commits, or commit a private key/password/service-account JSON.

Use the upload key currently registered for **this app** in Play Console, supplied through private GitHub Actions secrets or an authorized private signing environment. If the exposed key is reset, use the replacement only after Play Console accepts it. Do not create a replacement key and assume Play will accept it.

Suggested private CI secrets (names to configure, not confirmed to exist):
`PLAY_UPLOAD_KEYSTORE_B64`, `PLAY_UPLOAD_KEY_ALIAS`, `PLAY_UPLOAD_STORE_PASSWORD`, and `PLAY_UPLOAD_KEY_PASSWORD`.
Decode the key into a restricted temporary file in CI, mask passwords, and exclude signing files from artifacts/logs. If separate store/key passwords are used, configure the signing tool correctly rather than assuming they are identical.

Compare the signed AAB certificate with the **current upload certificate** under Play Console's App integrity / App signing settings. The verifier's historical SHA-256 `6971a9123d610b397f6e9122c6cb241dbbe9c9c5fdbeb5a8751d5e2e80839084` is provenance only; verify it against the current Console certificate, especially after any key reset. The upload certificate and Google Play app-signing certificate serve different purposes.

## Required build setup corrections

Do not run `.github/workflows/build-native-play.yml` unchanged:

1. It still names vc22 outputs and targets a historical branch.
2. `godot/tools/ci_restore_play_signing.py` replays the old build-aab signing stage, which expects the removed repository key and legacy plaintext configuration. Replace that mechanism with private secrets before a Play build.
3. `godot/tools/verify_play_bundle.py` hardcodes Play code 24 / versionName `1.2.0-siege-online`, while the current preset is code 23 / `1.1.1`. Update expected values from the verified release settings; retain all substantive checks.
4. Exclude `server/*` as well as `tests/*`, `reports/*`, and `tools/*` from the client export. Verify the archive itself excludes private files and server scripts.
5. Set artifact names to the actual verified release code/version. Updating workflow files requires GitHub authentication with workflow-edit permission; the VM's existing OAuth token rejected workflow edits. Do not bypass that limitation.

Run `GODOT=/path/to/godot godot/tools/run_siege_tests.sh` on the exact release source. Use JDK 17+ and the configured Android SDK/build-tools. Import assets and install matching Android build templates. Once the Play preset, private signing, and verifier are corrected, export from the repository root:

```bash
# Supply these variables privately in the authorized build environment.
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PLAY_UPLOAD_KEYSTORE_PATH"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$PLAY_UPLOAD_KEY_ALIAS"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PLAY_UPLOAD_KEY_PASSWORD"
mkdir -p godot/build
"$GODOT" --headless --editor --path godot --import
"$GODOT" --headless --path godot --install-android-build-template \
  --export-release "Android Play Store" \
  "$PWD/godot/build/Fatebound-Siege-Play-release.aab"
```

This is a build recipe, not a claim that a Play-ready AAB already exists. Never substitute `build_siege_preview.sh`, a debug export, or the supplied preview keystore.

## Validate before upload

- Run the corrected `verify_play_bundle.py`, Google bundletool validation/manifest inspection, and `jarsigner -verify`.
- Verify the actual manifest: package, selected versionCode/versionName, release debuggable=false, Internet permission, min/target SDK, and required ABIs.
- Retain checks for Siege-only runtime, Vulkan/no OpenGL fallback, installation-time game assets, 64-bit native library alignment, and no tests/server/signing material.
- Record AAB SHA-256, upload certificate fingerprint, source commit, test results, and validation report. Do not describe headless tests as physical Android testing.
- Recheck `systemctl is-active fatebound-siege` and the public player probe:

```bash
SIEGE_PROBE_URL=wss://136-113-125-3.sslip.io/fatebound/siege/ws \
  /opt/godot-4.7.2/godot --headless --path /srv/fatebound-siege \
  -s res://server/siege_probe.gd
```

Healthy requires `active` plus `PROBE_OK` with snapshots. The libfontconfig warning alone is not a failure. Verify online play, tutorial, settings, and privacy URL on Android before claiming device QA.

## Upload in Play Console

Open the existing **Fatebound** app (`com.fatebound.game`), use the track Kevin has authorized, create/edit its release, and upload the validated signed AAB. Enter accurate release notes and resolve Console validation errors. Record acceptance, version code, track, and release status. Deliver the AAB and verification report to Kevin.

Uploading an AAB, saving a draft, submitting for review, and rolling out to users are separate actions. This handoff-document request does not itself authorize a Play rollout; follow Kevin's release/track instructions when he requests that work. Do not invent Google Play API credentials, upload permissions, successful submission, or approval. If account access, current upload signing material, or version history is missing, state exactly what is missing.

## Official references

- https://developer.android.com/studio/publish/upload-bundle
- https://support.google.com/googleplay/android-developer/answer/9859348
- https://support.google.com/googleplay/android-developer/answer/9842756
- https://support.google.com/googleplay/android-developer/answer/9859350
