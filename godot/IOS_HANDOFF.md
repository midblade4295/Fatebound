# Fatebound on iPhone — handoff for Kevin and Grok Bot

The code side of the iOS port (IOS_PORT_SPEC_FOR_CLAUDE.md) is on `claude/siege-dev-r6-local`; its Status table says
what each step did. What is left needs Apple accounts, keys and Kevin's approval — none of it is done by Claude.
**Rules:** never change or reuse a product id or achievement id (copy them character for character); never submit
for App Store review or release without Kevin; secrets only in GitHub secrets or on the server, never in git, logs or
chat. Game Center achievements can't be deleted once live: Kevin approves before they go live.

Apple account: **midblade4295@hotmail.com** (Individual, Kevin Petrie), Team ID **YBKRZRW845**. App Store app:
**Fatebound Siege** (Apple ID 6822556363, bundle `com.fatebound.game`; the name on the home screen stays "Fatebound").

## 1. Apple Developer: the app id, the certificate, the profile (no Mac needed)
1. developer.apple.com > Certificates, Identifiers & Profiles > **Identifiers** > App IDs > `com.fatebound.game`
   (team YBKRZRW845): capabilities **Game Center** and **In-App Purchase** on (push notifications not needed: the
   chest notifications are local).
2. **Certificate** (Apple Distribution), from any computer with openssl:
   ```
   openssl genrsa -out fatebound_dist.key 2048
   openssl req -new -key fatebound_dist.key -out fatebound_dist.csr -subj "/emailAddress=midblade4295@hotmail.com/CN=Kevin Petrie/C=US"
   ```
   Certificates > + > **Apple Distribution** > upload `fatebound_dist.csr` > download `distribution.cer`, then:
   ```
   openssl x509 -inform DER -in distribution.cer -out distribution.pem
   openssl pkcs12 -export -legacy -inkey fatebound_dist.key -in distribution.pem -out fatebound_dist.p12 -name "Apple Distribution"
   ```
   (choose an export password; `-legacy` keeps the .p12 readable by macOS's keychain). Keep the .key and .p12
   private, outside the repository.
3. **Profile**: Profiles > + > **App Store Connect** (distribution) > App ID `com.fatebound.game` > the certificate
   above > name it e.g. `Fatebound App Store` > download `.mobileprovision`.

## 2. App Store Connect: the app record, keys, products, achievements, privacy
1. Apps > + > New App: iOS, name **Fatebound Siege**, bundle id `com.fatebound.game`, SKU e.g. `fatebound-ios`. Done:
   the app's **Apple ID** is 6822556363, set in `godot/scripts/meta/platform.gd` `APPLE_APP_ID` (0.31.133)
   (the update screen's App Store link; until then it opens an App Store search for Fatebound).
2. Users and Access > Integrations > **App Store Connect API**: a Team key with the **App Manager** role (for the
   TestFlight upload). Download the `.p8` once; note its Key ID and the Issuer ID.
3. Users and Access > Integrations > **In-App Purchase**: generate an In-App Purchase key (for the server's purchase
   checks). Download its `.p8`; note its Key ID (the Issuer ID is the same page's).
4. Fatebound > Monetization > **In-App Purchases** — the same seven as Google Play, same ids, prices and types:

   | Product ID | Type | Reference name / display name | Description | Price (USD) |
   |---|---|---|---|---|
   | `gems_80` | Consumable | Pouch of Gems | 80 gems. | 0.99 |
   | `gems_500` | Consumable | Sack of Gems | 500 gems. | 4.99 |
   | `gems_1100` | Consumable | Chest of Gems | 1,100 gems, enough for a Siege Pass. | 9.99 |
   | `gems_2400` | Consumable | Vault of Gems | 2,400 gems. | 19.99 |
   | `gems_6500` | Consumable | Royal Treasury | 6,500 gems. | 49.99 |
   | `gems_14000` | Consumable | Dragon's Hoard | 14,000 gems. | 99.99 |
   | `starter_pack` | **Non-Consumable** | Starter Pack | 500 gems, 3,000 gold and an epic weapon. One per player. (0.31.184: was 300 Embers -- update the description if it was entered with Embers) | 2.99 |

   Each needs a review screenshot (the shop: `store-listing/graphics/phone_screenshots/`) and goes in with the first
   build submitted for review (Kevin's call). For TestFlight they work as soon as they are "Ready to Submit".
5. Fatebound's **Game Center** page (turn Game Center on for the app) > Achievements — the 18 of `PLAY_ACHIEVEMENTS_HANDOFF.md`, same names,
   descriptions, points and order, **not hidden**, not achievable more than once. **Achievement ID = `fatebound.<key>`**
   (e.g. `fatebound.welcome`; the list is `godot/scripts/meta/gc_achievement_ids.gd`). Image: the same 512x512 PNG
   (`store-listing/achievements/<key>.png`). Pre-earned description = the description; earned = the same. Points total
   570. **Kevin approves the list before they go live (they can't be deleted).**
6. **App Privacy** (match the Android Data safety): Data used to track you: none. Data linked to you: User Content
   (Other User Content: chat, player name — App Functionality), Identifiers (User ID: the game account id and the
   hashed Game Center player id — App Functionality), Purchases (Purchase History — App Functionality), Usage Data
   (Product Interaction — Analytics), Diagnostics (Crash Data — App Functionality and Analytics; Other Diagnostic
   Data — App Functionality). No data shared with third parties. Privacy Policy URL: the same privacy.html as Play.
7. Age rating questionnaire (same answers as Play's), category Games > Strategy (or Action), the description and
   screenshots (the iPhone size App Store Connect asks for, and the 13" iPad size while iPad stays allowed — the
   export allows iPhone and iPad; turn iPad off in the preset, `application/targeted_device_family=0`, to skip it).
8. TestFlight > Internal Testing: a group with the testers' Apple IDs (internal testers need no review).

## 3. GitHub: the secrets and the workflow
1. Repository > Settings > Secrets and variables > Actions > New repository secret (values from steps 1–2;
   base64 with `base64 -w0 file` on Linux, `base64 -i file` on a Mac):
   `IOS_DIST_CERT_P12_BASE64` (fatebound_dist.p12), `IOS_DIST_CERT_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`
   (the .mobileprovision), `IOS_KEYCHAIN_PASSWORD` (any random string), `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`,
   `ASC_API_KEY_P8_BASE64` (the App Store Connect API key's .p8 — not the In-App Purchase key).
2. The workflow `.github/workflows/ios-testflight.yml` must be on **main** to be runnable (GitHub only lists
   workflows from the default branch); it builds whatever branch you name. Kevin approved adding only that file to
   main. Actions > **iOS TestFlight** > Run workflow: `ref` = the branch, `version_name` = the Play versionName's
   number (e.g. `1.2.26`), `version_code` = the Play versionCode (e.g. `216`; App Store build numbers must only go
   up), `mode` = `testflight` (or `build-check`: an unsigned iPhone build, no secrets, to prove it compiles and links).
   It picks Xcode 26 (Godot 4.7.2's iOS template needs the iOS 26 SDK), fetches Godot 4.7.2 (SHA-512 checked), the
   pinned GodotApplePlugins (SHA-256 checked), builds the notification plugin, exports, checks (base pck, privacy manifest, bundle id, version, plugins), signs, uploads to TestFlight —
   and never submits for review. Public repository: macOS minutes are free; keep it manual anyway. A `build-check`
   run on 2026-10-14 (run 38520870076) built the whole app unsigned for iPhone: everything up to signing works.

## 4. The server (Kevin: `sudo bash godot/server/deploy/install_siege_server.sh` after these)
1. Copy the In-App Purchase `.p8` (step 2.3) to `/etc/fatebound-siege/appstore-key.p8` (`chmod 600`, root). The
   installer hands it to the service with LoadCredential, like the Play key.
2. In `/etc/fatebound-siege.env`: `SIEGE_APPSTORE_ISSUER=<issuer id>` and `SIEGE_APPSTORE_KEY_ID=<that key's id>`.
3. The server needs `python3` and `openssl` (the installer warns if either is missing). Then redeploy (the installer
   only adds the key's LoadCredential line when the file is there, so redeploy after copying it). The log says
   `purchase checks: Apple: key <id> (issuer ...)`. Without the key an iPhone purchase waits ("unconfigured") and is
   finished later, never lost.
   Check the key against Apple without a purchase (0.31.133):
   ```
   sudo bash -c 'set -a; . /etc/fatebound-siege.env; python3 /srv/fatebound-siege/server/apple_jws.py --api-check \
       --key /etc/fatebound-siege/appstore-key.p8 --issuer "$SIEGE_APPSTORE_ISSUER" --key-id "$SIEGE_APPSTORE_KEY_ID"'
   ```
   Both lines (production, sandbox) must say "key accepted -- Apple answered 404 ..." (or 400); 401 means the key id, the
   issuer id or the key type is wrong (it must be an **In-App Purchase** key, not an App Store Connect API key).
4. 0.31.132's account features (MOVE TO ANOTHER PHONE / ENTER A CODE, DELETE ACCOUNT, the Game Center link) need
   this redeploy too, on Android as well.

## 5. privacy.html
The branch's `privacy.html` has the iPhone lines (App Store purchases, Game Center and its hashed player id, moving to
another phone, account deletion, iOS notifications). The live page is main's copy: copy it over as usual
("privacy: ... (from <commit>)") before the first TestFlight build goes to external testers.

## 6. One shared minimum build
`/etc/fatebound-siege/min_build` applies to both stores. Raise it only when **both** Google Play and the App Store
have that build live (TestFlight doesn't count). There is no `min_build_ios`, on purpose.

## 7. What can't be tested without a device
StoreKit, Game Center and the notifications are only reachable on an iPhone. The Linux tests use doubles of the
plugins' classes (`tests/ios_port_test.gd`), a stand-in Apple for the server checks (`tests/apple_iap_test.gd`,
`tests/account_move_test.gd`), and the notification extension's own Linux build. The first TestFlight build should
check, on a phone: a sandbox purchase of `gems_80` (granted, then finished), RESTORE PURCHASES, Game Center sign-in
and an achievement, a chest notification, MOVE TO ANOTHER PHONE to an Android phone and back.
