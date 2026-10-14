# Fatebound: iOS port (App Store / TestFlight), spec for Claude

Branch: `claude/siege-dev-r6-local` (read at grok/siege-play-local-r27 9e50ee3 = tip 628bd44, 1.2.25-siege-0.31.128, vc214).
Goal: the same game on iPhone through TestFlight first, then the App Store, with **the Android build byte-for-byte unchanged
in behaviour**, and **iOS matching Android exactly** (shared min_build, full IAP + achievements, chest-ready notifications,
Game Center id on server parallel to Play Games). Apple account: Individual, Kevin Petrie, Team ID `YBKRZRW845`, bundle ID `com.fatebound.game`.
Nobody on the team has a Mac or an iPhone: everything builds on a GitHub Actions macOS runner, and testing is TestFlight
testers + the iOS Simulator only.

## 0. Ground truth (current code this fits)
- Engine: Godot **4.7.2.stable** (`tools/content_packs.py` `GODOT_VERSION`). Renderer `rendering_method="mobile"`,
  `rendering_device/fallback_to_opengl3=false` (Vulkan-only on Android), `textures/vram_compression/import_etc2_astc=true`.
- `export_presets.cfg`: preset.0 "Android Play Store" (Gradle, AAB, arm64-v8a only, minSdk 29 / target 36, vc 214,
  `godot_play_game_services/game_id="1022979193240"`, permissions internet + vibrate, icons `res://assets/branding/*`),
  preset.1 "Android Visual Preview" (APK). Base presets' `exclude_filter` is written by `content_packs.py presets`
  (`BASE_PRESETS = ["Android Play Store", "Android KayKit Rebuild"]`).
- Android-only plugins (`godot/addons/`): `GodotGooglePlayBilling`, `GodotPlayGameServices`, `FateboundNotify`
  (own plugin, `android_plugins/fatebound_notify`, chest-ready local notifications). All found via `Engine.has_singleton`,
  so on any other platform they are simply absent (`Billing.supported()`, `PlayGames.active()`, `notify.gd` no-op).
- Purchases: `scripts/meta/billing.gd` -> socket msg `{"t":"iap","v":35,"product","token","order","pkg"}` ->
  `server/iap_verify.gd` (service-account JWT -> `androidpublisher/v3/.../purchases/products/<p>/tokens/<t>`) ->
  `server/eco_accounts.gd grant_purchase(id,key,product,token,consumed)` (once per `token_hash(token)`, tokens map
  token->account) -> `Profile.grant_iap`. Catalog `Net.IAP` in `scripts/siege/siege_net.gd`.
- Play Games: `scripts/meta/play_games.gd` (auto sign-in, one Saved Game slot `fatebound-profile`, `FB1:` gzip+b64 copy,
  conflict choice USE GOOGLE PLAY'S / KEEP THIS PHONE'S), `scripts/meta/achievements.gd` + `play_achievement_ids.gd`.
- Server accounts are our own (20-hex id + key, `server/eco_accounts.gd`); Play Games is **not** the account, it is
  only a cloud copy of the profile. Keep it that way on iOS.
- Content packs: `tools/content_packs.py` + `scripts/app/content_loader.gd`, packs on the `content-packs` branch served by
  raw.githubusercontent.com with byte ranges; pack file names are hashes of inputs.
- Analytics: `scripts/meta/analytics.gd` + `server/analytics.gd` (self-hosted, `"an"` msg; see ANALYTICS_SPEC_FOR_CLAUDE.md).
- Vibration: `Input.vibrate_handheld(ms, strength)` in `siege_mode.gd:333` and `screens.gd:2379` (Settings toggle).
- `OS.get_name() == "Android"` checks: `update_screen.gd:26` (store link), `boot_guard.gd:35` (tracking), `siege_diag.gd:220`.
- Protocol `Net.VERSION` = 35; `min_build` gate on the server (`/etc/fatebound-siege/min_build`) applies to every platform.

## 1. Platform abstraction (do this first; Android must not change)
- New `scripts/meta/platform.gd` (RefCounted, static): `is_android()`, `is_ios()`, `store()` -> `"play"|"appstore"|"none"`,
  `store_url()`, `has_iap()`, `has_cloud_save()`, `has_achievements()`.
- New facades, chosen at setup by `Platform.store()`:
  - `scripts/meta/store_billing.gd`: picks `billing.gd` (Play, unchanged) or new `billing_ios.gd`. Same signals
    (`changed`, `granted`, `note`), same `prices`, `busy`, `buy(product)`. The shop talks only to the facade.
  - `scripts/meta/game_services.gd`: picks `play_games.gd` (unchanged) or new `game_center.gd`. Same API for
    `achievements.gd` (unlock/increment by **key**, the platform maps key -> its own id).
- Replace the three `OS.get_name() == "Android"` checks with `Platform` calls that return exactly what they return now
  on Android (update screen: Play link on Android, App Store link on iOS; BootGuard tracking also on iOS).
- **Rule:** no edit to `billing.gd`, `play_games.gd`, `iap_verify.gd` logic. A diff of the Android AAB built before/after
  must pass `verify_play_bundle` (BASE OK, CONTENT OK, play_games true) and `run_siege_tests --quick` unchanged.

## 2. iOS export preset (preset "iOS App Store", add to export_presets.cfg; never touch preset.0)
- `application/bundle_identifier="com.fatebound.game"`, `application/app_store_team_id="YBKRZRW845"`,
  `application/short_version` = the Android `version/name` numeric part (e.g. `1.2.25`), `application/version` = the
  Android versionCode (same number, App Store build numbers must only go up), display name "Fatebound".
- Export method App Store (`application/export_method_release=0` / app-store), automatic signing off; the CI provides
  the distribution certificate + provisioning profile (section 8). `application/export_project_only=false`.
- Architectures arm64 only. **Minimum iOS 15.0** (Metal 2 / MoltenVK-friendly devices, ~A9+; StoreKit 2 needs 15).
  Devices: iPhone required, iPad allowed (stretch `expand` already copes); orientation portrait (`window/handheld/orientation=1`).
- Renderer: keep `rendering_method="mobile"`. On iOS Godot 4.7 uses **Metal natively** (Godot 4.4+ has a Metal driver);
  use `rendering_device/driver.ios="metal"`. Keep `fallback_to_opengl3=false` (there is no GL fallback worth having).
  Do not use MoltenVK unless a Metal-driver bug shows up; note it in Status if so.
- Textures: ASTC is already imported (`import_etc2_astc=true`); iOS uses ASTC, so no re-import needed.
- Icons: 1024x1024 App Store icon from `assets/branding/icon.png` (no alpha, no rounded corners: make
  `assets/branding/ios_icon_1024.png` flattened on the background colour) + Godot's generated sizes; launch screen =
  the same splash colour + logo (storyboard, Godot's default `launch_screen` options).
- Capabilities / entitlements: Game Center, In-App Purchase. `Info.plist`: `ITSAppUsesNonExemptEncryption=false`
  (only standard HTTPS/WSS; confirm), no camera/mic/location/tracking strings (none used). Haptics need no permission.
- Exclude filter: same as the Android base (`content_packs.py presets` must add the iOS preset name to `BASE_PRESETS`).

## 3. StoreKit 2 in-app purchases
### Product IDs (copy EXACTLY; IDs can never be reused or renamed, on either store)
| Product ID | Gems | Other | USD | Type on App Store |
|---|---|---|---|---|
| `gems_80` | 80 | | 0.99 | Consumable |
| `gems_500` | 500 | | 4.99 | Consumable |
| `gems_1100` | 1100 | tag "A SIEGE PASS" | 9.99 | Consumable |
| `gems_2400` | 2400 | | 19.99 | Consumable |
| `gems_6500` | 6500 | tag "BEST VALUE" | 49.99 | Consumable |
| `gems_14000` | 14000 | shown only when the store returns a price | 99.99 | Consumable (create on Apple; already live on Play since 2026-10-12) |
| `starter_pack` | 500 | 300 Embers + epic weapon, `once:true` | 2.99 | **Non-Consumable** |
Source: `Net.IAP` in `scripts/siege/siege_net.gd`. Play Console already has the full set: the five gem packs +
`gems_14000` (created 2026-10-12) + `starter_pack` (PLAY_IAP_HANDOFF.md Status row 3). Create the **same full set**
on App Store Connect (same IDs, same prices, same types). Same IDs on Apple keep one catalog and one ledger.
Treat `play_only` as "shown only when the current store returns a price" (rename the flag only in comments, keep
the key or treat it as `store_only`; behaviour on Android unchanged).

### Client (`billing_ios.gd` + a native plugin)
- Godot has no built-in StoreKit 2. Options: (a) the official `godot-ios-plugins` "inappstore" is StoreKit 1 and old;
  (b) write a small Swift GDExtension/iOS plugin `addons/FateboundStoreKit` (StoreKit 2: `Product.products(for:)`,
  `product.purchase(options: [.appAccountToken(uuid)])`, `Transaction.updates`, `Transaction.currentEntitlements`,
  `transaction.finish()`), exposing signals mirroring BillingClient (`products(details)`, `purchase_updated(jws, product,
  txn_id, original_txn_id)`, `error`). Recommendation: (b), built on the CI Mac. Check first whether a maintained
  Godot 4.7 StoreKit 2 plugin exists (e.g. community "godot-storekit2"); if so pin a version and note it.
- `appAccountToken`: a UUID derived from our account id (UUIDv5 of `acct`), so Apple's transaction carries which
  Fatebound account bought it.
- Flow mirrors Play exactly: sheet -> JWS `signedTransaction` -> server `iap` msg -> grant -> **then** `finish()`.
  Unfinished transactions come back on `Transaction.updates`/`unfinished` on the next start (like `query_purchases`).
  Never `finish()` before the server granted it.
- Message: `{"t":"iap","v":35,"store":"apple","product","jws","pkg":"com.fatebound.game","acct","key"}`.
  `store` missing = `"google"` (old clients unchanged).

### Server (`server/iap_verify_apple.gd`, new; `iap_verify.gd` untouched)
- Verify the JWS locally: header `x5c` chain -> must chain to **Apple Root CA - G3** (bundle the public root cert in
  `server/certs/AppleRootCA-G3.cer`; public, fine in git), ES256 signature, `bundleId == com.fatebound.game`,
  `productId` in `Net.IAP`, `environment` (Sandbox/Production -> `test` flag like Google's), `revocationDate` absent,
  `appAccountToken` == UUIDv5(acct) (refuse mismatch).
- Then confirm with the **App Store Server API** `GET /inApps/v1/transactions/{transactionId}` (prod
  `api.storekit.itunes.apple.com`, sandbox `api.storekit-sandbox.itunes.apple.com`), auth = ES256 JWT signed with an
  In-App Purchase key (`iss` issuer id, `kid` key id, `aud "appstoreconnect-v1"`, `bid com.fatebound.game`). Godot's
  `Crypto` lacks ES256/x509 chain checks: do the crypto in a small helper (Python `cryptography` or `openssl` CLI)
  called by the server, or a GDExtension; document which.
- Grant via the existing `grant_purchase(id, key, product, token, consumed)` with `token = "apple:" + originalTransactionId`
  for `starter_pack` and `"apple:" + transactionId` for gem packs, so the token ledger keeps "granted once, never to
  another account" and Google tokens can never collide.
- Refunds: optional App Store Server Notifications V2 endpoint (`REFUND`) -> log only for now (Google flow has no
  revocation either). Note in Status.
- Key: `$CREDENTIALS_DIRECTORY/appstore-key` (systemd LoadCredential, same pattern as `play-key`), plus env
  `SIEGE_APPSTORE_ISSUER`, `SIEGE_APPSTORE_KEY_ID`. Never in git, never in logs. `describe()` line like Google's.
- Analytics `purchase_verified` gets `store` prop. Ledger lines unchanged format + `store`.

## 4. Game Center (sign-in, achievements, cloud copy)
- Plugin: Godot's official iOS `gamecenter` plugin (godot-ios-plugins) or the same Swift plugin as StoreKit
  (`GKLocalPlayer.local.authenticateHandler`, `GKAchievement.report`, `GKAccessPoint`). Pin it.
- Sign-in: automatic at start (Apple shows its own banner); Settings shows "Game Center: signed in as <alias>" or
  "Sign in from iOS Settings > Game Center" (there is no in-app sign-in after a decline; Apple's rule).
- Achievements: 18 in App Store Connect, mirroring `out/achievements/LIST.md` **names, descriptions, points, order,
  all visible (not hidden)**. Apple's IDs are our own strings: use `fatebound.<key>` (e.g. `fatebound.welcome` …
  `fatebound.legend`), add `scripts/meta/gc_achievement_ids.gd` (key -> id) next to `play_achievement_ids.gd`.
  Apple has no "incremental" type: report `percentComplete = 100 * progress / steps` with the same steps as Play
  (many_hats 7, fattening 25, lumberjack 500, gatecrasher 100, heavy_lifting 50, centurion 100, bodyguard 25,
  seasoned 20, siege_lord 50, slayer 1000, legend 250). Total 570 points ≤ Apple's 1000 cap; each ≤ 100. Each needs a
  512x512 or 1024x1024 image (scale `out/achievements/*.png`). Once live, Game Center achievements also cannot be
  deleted: Kevin approves before they go live.
- Cloud copy: Play's Saved Game has no direct twin. Use **GameKit saved games** (`GKLocalPlayer.saveGameData` /
  `fetchSavedGames`, needs iCloud capability) with the same `FB1:` payload and the same conflict rules, or skip cloud
  copy on iOS v1 and rely on the server account. Recommendation: v1 = server account + Game Center id link (below)
  + transfer code; GameKit Saved Games later if needed for conflict UX parity.
- **Account linking implications:** the server account (id+key in `profile.d.account`) is the real progress
  (gems, purchases, weapons). Today a new Android phone gets it back only via the Play Games copy (which carries
  `account.id/key`). An iPhone can't read Google's copy. So:
  - add a server-side **transfer code**: Settings > "Move to another phone" -> `{"t":"eco","op":"link_new"}` returns a
    one-time 8-character code (10 min, single use, rate-limited); the other phone enters it and receives id+key.
    Works Android<->iOS both ways, no Google/Apple identity on our server.
  - **Store** the Game Center `teamPlayerID` hash on the account (parallel to the Play Games player id), verified
    with `fetchItems(forIdentityVerification)` signature server-side, so a reinstall on iOS restores the account like
    Play Games does. Never store raw ids in analytics. Add a matching line to `privacy.html` (Game Center player id
    stored for account restore, same treatment as Play Games).
  - Purchases are bound to our account (appAccountToken / Google token), so moving the account moves the gems; restoring
    `starter_pack` on a new Apple ID is Apple's "Restore Purchases" button (required by review for non-consumables).

## 5. Content packs on iOS
- Packs are platform-specific exports (`content_packs.py build` exports with `CONTENT_PACK_PRESET`). iOS uses ASTC like
  Android, but Godot pck exports per platform: build packs with the iOS preset and check whether the stripped data is
  identical to the Android packs (hash compare). If identical, reuse; if not, manifest gets per-platform entries
  (`packs.<name>.ios`), names still input-hashed, on the same `content-packs` branch (it only grows, no force-push).
- Loader on iOS: `user://` is in the app's Application Support (backed up to iCloud by default); mark the packs dir
  excluded from backup or use Caches-like location; re-download if purged. Downloads over HTTPS from
  raw.githubusercontent.com are ATS-compliant.
- **App Review risk:** guideline 2.5.2 forbids downloading executable code. Packs must stay data-only (`KEEP_IN_PACK`
  already strips code/settings; `content_packs.py base` check enforces it) - keep that check in the iOS build.
- `base X` check: add support for an `.ipa` (zip, `Payload/Fatebound.app/*.pck`).

## 6. Other platform bits
- Vibration: `Input.vibrate_handheld(ms, strength)` works on iOS (Core Haptics on 13+; duration short). Keep the toggle;
  test it does nothing harmful on iPad.
- Notifications: port chest-ready local notifications in v1 with `UNUserNotificationCenter` in the same Swift
  plugin (parity with `FateboundNotify` on Android). Settings keeps the same toggle; request notification permission
  the first time a chest is armed (or at Settings opt-in). Required for feature parity, not optional for TestFlight.
- Update screen: App Store link `https://apps.apple.com/app/id<APPLE_ID>` (Apple ID number from App Store Connect).
  **One shared `min_build`** for both stores (`/etc/fatebound-siege/min_build`). Raise it only when **both** Play and
  App Store have that build live; never split into `min_build_ios`.
- Diagnostics: `siege_diag.gd` should log `iOS` + model; `COPY DIAGNOSTICS` works (clipboard).
- Analytics: add `plat` ("android"/"ios") to `session_start` props; reports split DAU by platform. No IDFA, no ATT prompt.
- Chat/UGC: Apple 1.2 requires report + block + filter for user content. Check social.gd has block/report; add if missing.
- Account deletion in-app (Apple 5.1.1(v)): required since accounts are created. Add Settings > "Delete account" ->
  server deletes the account files (or confirm one exists already).

## 7. Privacy manifest and App Privacy (match Android Data safety)
`PrivacyInfo.xcprivacy` (add to the export via the plugin or `application/additional_plist_content` / bundle file):
- `NSPrivacyTracking = false`, `NSPrivacyTrackingDomains = []`.
- `NSPrivacyAccessedAPITypes`: Godot itself uses UserDefaults (`CA92.1`), file timestamps (`C617.1`), system boot time
  (`35F9.1`), disk space (`E174.1`) - confirm against Godot 4.7's shipped manifest (Godot ≥4.3 ships one; merge, don't drop).
- `NSPrivacyCollectedDataTypes` (all: Linked to user = yes for account-bound, Tracking = no, purpose App Functionality /
  Analytics):
  | Data type | Why |
  |---|---|
  | Other User Content (chat messages, player name) | App Functionality |
  | User ID (our account id; Game Center id if stored) | App Functionality |
  | Purchase History | App Functionality |
  | Product Interaction (gameplay events) | Analytics |
  | Crash Data | App Functionality / Analytics (BootGuard, error events) |
  | Other Diagnostic Data (performance, device model, OS) | App Functionality |
App Store Connect "App Privacy" answers = the same list; **no data shared with third parties, none used for tracking**;
analytics opt-out exists. Privacy policy URL = the same privacy.html (**must** add an iOS/Game Center player-id line; see §4).

## 8. Cloud Mac build -> TestFlight (GitHub Actions)
Workflow `.github/workflows/ios-testflight.yml` (manual `workflow_dispatch` only; never on push):
1. `runs-on: macos-15` (Xcode 16+, iOS 18 SDK; Apple requires a current SDK).
2. Download Godot 4.7.2.stable macOS editor + export templates (pin URLs + SHA-256).
3. Build the Swift plugins (StoreKit/GameCenter) with `xcodebuild`.
4. Import keychain: create temp keychain, import the distribution `.p12`, install the provisioning profile.
5. `godot --headless --export-release "iOS App Store" build/ios/Fatebound.ipa` (or export project, then
   `xcodebuild archive` + `-exportArchive` with `ExportOptions.plist` method app-store, team YBKRZRW845).
6. Checks: `content_packs.py base build/ios/Fatebound.ipa`, privacy manifest present, bundle id / version.
7. Upload: `xcrun altool --upload-app` or `fastlane pilot` with an App Store Connect API key. **Upload to TestFlight
   only; never submit for App Store review or release from CI.** Kevin decides store submission.
8. Delete keychain + key files in an `always()` step. Artifacts: the .ipa + log, not the secrets.
Secrets (GitHub repo secrets, names only, values never in git/logs/chat):
`IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_KEYCHAIN_PASSWORD`,
`ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`, `ASC_API_KEY_P8_BASE64`. Server (not GitHub): `appstore-key` credential +
`SIEGE_APPSTORE_ISSUER`, `SIEGE_APPSTORE_KEY_ID`. Certificates/profile can be created by the CI with the ASC API key
(fastlane `match`-less `cert`/`sigh`) since nobody has a Mac; document the one used.
Free-tier note: macOS minutes count 10x on private repos; keep the workflow manual.

## 9. Tests
- `run_siege_tests --quick` passes with `Platform` faked to ios (fake StoreKit/Game Center doubles like the billing test double).
- Server tests: valid sandbox JWS granted once; same transaction twice -> "already yours"; other account -> `used`;
  wrong bundle id / unknown product / bad chain / revoked / appAccountToken mismatch -> refused; Google path unchanged.
- Android AAB from the branch: `verify_play_bundle` BASE OK, CONTENT OK, play_games true; versionCode > previous.

## 10. Decisions (Kevin, 2026-10-13) — iOS must match Android exactly
| Topic | Decision |
|---|---|
| Feature parity | Full set of products, achievements, and features; same behaviour as Android everywhere |
| `min_build` | **One shared** value for both stores; raise only when both Play and App Store have the build |
| Chest-ready notifications | **Included in v1**, ported with `UNUserNotificationCenter` (parity with FateboundNotify) |
| Game Center id on server | **Yes**, store `teamPlayerID` hash parallel to Play Games id; add matching line to `privacy.html` |
| `gems_14000` | Already live on Play (created 2026-10-12); **create on Apple too** with the same ID/price/type |
| Products / achievements | Full catalog on App Store Connect (all gem packs + starter_pack; all 18 achievements) |

## 11. Status (fill as you go; commit only this file + code, never secrets)
| # | Step | Done | Date | Notes |
|---|---|---|---|---|
| 1 | Platform abstraction, Android unchanged (tests + verify_play_bundle) | yes | 2026-10-13 | 0.31.130. `platform.gd`, `store_billing.gd`/`game_services.gd` (factories handing back one of two scripts with the same face), `billing_ios.gd`, `game_center.gd`, `apple_token.gd`, `gc_achievement_ids.gd`; achievements.gd counts once, each service sends its own way. billing.gd / play_games.gd / iap_verify.gd untouched. Play AAB from HEAD and from this change (throwaway key, preset.0 untouched): both BASE OK, CONTENT OK, play_games true, bundletool valid; only script files differ. Quick suite 84/84 (new `ios_port_test`). **Deviation (Kevin approved): GodotApplePlugins, so minimum iOS 17, not 15.** |
| 2 | iOS export preset (bundle id, team, iOS 15, Metal, icons) | yes | 2026-10-13 | preset.5 "iOS App Store"; **iOS 17.0** (plugin); Metal = Godot's iOS default (project.godot untouched); A12 floor (Godot adds it for the mobile renderer). Icon `store-listing/ios/app_icon_1024.png` (B4 source at 1024, RGB) instead of `assets/branding/` so the Android bundle doesn't grow. Privacy manifest from the preset (§7 list + Godot's reasons + CA92.1). `short_version`/`version` placeholders; the workflow writes Play's values. Xcode project export checked on Linux. |
| 3 | StoreKit 2 plugin + billing_ios.gd (full Net.IAP catalog incl. gems_14000) | code | 2026-10-13 | Plugin: **GodotApplePlugins v1.11** (migueldeicaza, MIT; release `build-a6d667dda4d4f7b008009d3704f679b06f81424f`, zip SHA-256 `a5c48a99…8166`), StoreKit + GameCenter + Runtime addons only, fetched by `tools/ios_plugins.sh` before an iOS export and **never committed** (gitignored) so Android/desktop never carry it. `billing_ios.gd` asks for all 7 `Net.IAP` ids; a pack shows only when Apple returns it (`play_only` = store-only). Device test waits for the first TestFlight build. |
| 4 | Server Apple verification (JWS + App Store Server API) + tests | | | |
| 5 | Game Center sign-in + 18 achievements mapping (gc_achievement_ids.gd) | code | 2026-10-13 | Same plugin (GameCenterManager, GKAchievement.report_achievement, GKGameCenterViewController). Ids `fatebound.<key>` (18), percent = 100·steps/goal with Play's goals, 570 points. Settings: "Game Center: signed in as <alias>" + ACHIEVEMENTS, or "Sign in from iOS Settings > Game Center". The achievements still have to be made in App Store Connect (row 11). |
| 6 | Account transfer code + **required** Game Center `teamPlayerID` hash link + privacy.html line | | | |
| 7 | Chest-ready local notifications (UNUserNotificationCenter) + Settings toggle parity | code | 2026-10-13 | Own GDExtension `ios_plugins/fatebound_notify` (Objective-C++ + godot-cpp `godot-4.5-stable` e83fd09, static xcframeworks) with the Android plugin's four calls (`hasPermission`, `requestPermission`, `schedule`, `cancelAll`), so `notify.gd` (question, toggle, scheduling) is unchanged; built on the Mac by `ios_plugins/fatebound_notify/build_ios.sh`. Binding checked on Linux with the stand-in build (class, calls). |
| 8 | Content packs on iOS (reuse or per-platform) + .ipa base check | | | |
| 9 | PrivacyInfo.xcprivacy + account deletion + UGC report/block | | | |
| 10 | GitHub Actions macOS workflow -> TestFlight (secrets named only) | | | |
| 11 | Grok Bot: App Store Connect products (full set incl. gems_14000), achievements, App Privacy (Kevin approves) | | | |
| 12 | Shared `min_build` policy documented; raise only when both stores live | | | |
| 13 | First TestFlight build installed by a tester | | | |

## Rules
- Never change or reuse product IDs; copy them character for character. Never publish to production / submit for review
  without Kevin. Never force-push. Never commit secrets (service-account JSON, .p8, .p12, profiles, passwords,
  override.cfg). Android release flow and preset.0 unchanged.
