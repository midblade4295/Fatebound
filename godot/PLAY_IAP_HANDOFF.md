# Fatebound: in-app purchases, Play Console side (for Grokbot)

Written 2026-10-09. Kevin has asked Grokbot to set up the merchant / Play Console side of in-app purchases.
Claude writes the game and server code on branch `claude/siege-dev-r6-local`. This file is the contract between the
two: the product IDs below are the ones the game will ask Google Play for, character for character.

App: **Fatebound**, package **`com.fatebound.game`** (Godot preset "Android Play Store"). Purchases only exist in this
app. The itch / preview builds (`com.fatebound.kaykitrebuild`) never sell anything.

## Ground rules

1. **Do not publish to production** and do not touch the production or closed tracks. The only release this work
   needs is on **Internal testing** (step 2).
2. **Product IDs are permanent.** Google never lets an ID be reused, even after deleting the product. Copy them
   exactly from the table in step 3. If one gets mistyped, tell Kevin. Don't make a "fixed" second one.
3. **Never commit secrets.** The repository is public. No service-account JSON, keystore, password or payment details
   in git, issues, commit messages or chat logs.
4. **Steps that need Kevin in person** (identity, bank, tax) are marked **[Kevin]**: prepare them and hand over.
5. When you finish a step, fill in the **Status** table at the bottom of this file and commit just that file.

## Order

| Step | What | Can start |
|---|---|---|
| 1 | Payments profile (merchant account) | Now |
| 4 | License testers | Now |
| 5 | Service account for purchase checks | Now |
| 7 | Policy forms (Data safety, content rating) | Now |
| 2 | Internal-testing build with billing | After Claude's "Play Billing" commit lands (see Status) |
| 3 | Create the products | After step 2 |
| 6 | Test purchase on Kevin's phone | After step 3 and Claude's build |

## 1. Payments profile (merchant account)

Play Console → **Setup → Payments profile** (or the "Set up a merchant account" prompt under **Monetize**).

- Create or link a **Google payments profile** of type matching how Kevin publishes (individual or business). Use the
  developer name already shown on the Play listing.
- **[Kevin]** legal name and address, **bank account** for payouts, **tax information** (US: the W-9 interview), and
  any identity verification Google asks for.
- When it shows as active, the **Monetize** section unlocks product creation.
- Check the service fee. Google charges 15 % on a developer's first US$1M of earnings each year. Make sure the account
  is set up to get that rate. Play Console may ask for an account group even for a single account.

## 2. Internal-testing build with billing

Play Console usually refuses to create in-app products until the app has a build that uses Google Play Billing.

- Wait until the Status table says the **Play Billing** commit has landed.
- Build the signed release bundle exactly as `godot/PLAY_STORE_HANDOFF.md` describes (preset **Android Play
  Store**, `godot/tools/build_play_release.sh`, the upload key from private secrets). Use a versionCode higher than
  anything ever uploaded.
- Upload it to **Testing → Internal testing** only. Add Kevin's Google account to that track's testers.

## 3. Create the products

Play Console → **Monetize with Play → Products → One-time products** (older consoles call these "In-app products").

Create exactly these. Price is the **US$ default price**; let Play convert the other countries automatically. Set
each one **Active**.

| Product ID | Name (shown in Google's purchase sheet) | Description | Price (US$) |
|---|---|---|---|
| `gems_80` | Pouch of Gems | 80 gems. | 0.99 |
| `gems_500` | Sack of Gems | 500 gems. | 4.99 |
| `gems_1100` | Chest of Gems | 1,100 gems, enough for a Siege Pass. | 9.99 |
| `gems_2400` | Vault of Gems | 2,400 gems. | 19.99 |
| `gems_6500` | Royal Treasury | 6,500 gems. | 49.99 |
| `starter_pack` | Starter Pack | 300 gems, 150 Embers and a rare weapon. One per player. | 2.99 |

Notes:
- All six are one-time products. The game **consumes** the gem packs, so they can be bought again. It
  **acknowledges but never consumes** `starter_pack`, so Google allows it only once per Google account. No
  subscriptions.
- If the console asks for a "purchase option" ID, use `buy` for each product.
- Do not create anything else (no chest products, no pass product). Chests stay earn-only. If chests were sold for
  money they would be paid loot boxes, which need the odds shown before purchase and are restricted in some countries.

## 4. License testers

Play Console (account level) → **Settings → License testing**.

- Add **Kevin's Google account** (the one signed in to the Play Store on his Galaxy S21 Ultra). Response:
  **RESPOND_NORMALLY**.
- License testers buy with Google's test cards and are never charged. Without this, every test purchase is real money.

## 5. Service account for purchase checks

The Siege server will ask Google whether each purchase token is real before granting gems, so a hacked client can't
fake a purchase.

1. **Google Cloud console**: in the project linked to the Play developer account (or a new project named
   `fatebound-play`), enable **Google Play Android Developer API**.
2. Create a service account named `fatebound-purchases`. Create a **JSON key** for it.
3. **Play Console → Users and permissions → Invite new users**: invite the service account's email. Give it, for
   the Fatebound app only:
   - **View financial data, orders, and cancellation survey responses**
   - **Manage orders and subscriptions**
4. Put the JSON key on the Siege server at **`/etc/fatebound-siege/play-service-account.json`**, owned by root, mode
   `600`. That is the only copy outside Google. Don't commit it or paste it anywhere.
5. Re-run the installer from this branch: `sudo bash godot/server/deploy/install_siege_server.sh`. When the key file
   exists it turns on `LoadCredential=play-key:` in the systemd unit (the service runs as a dynamic user that can't
   read a root-only file directly). `journalctl -u fatebound-siege | grep "purchase checks"` should then show
   `key /run/credentials/... (fatebound-purchases@...)` instead of `off (no service-account key)`.
6. New permissions can take up to a day before the API accepts the key. Until then purchases stay pending on the
   phone (nothing is lost; the game asks again on the next start).

For an early internal test before the key works, the server can accept every purchase without asking Google:
add `SIEGE_IAP_FAKE=1` to `/etc/fatebound-siege/fatebound-siege.env` and restart the service. Remove it before any
build goes beyond internal testing.

Record only the service account **email** in the Status table, never the key.

## 6. Test purchase

After step 3 and Claude's next Play build on Internal testing:

- On Kevin's phone, install from the internal-testing link (not the itch APK).
- Buy `gems_80`. Google's sheet should say it is a test purchase. Gems should arrive and the server log should show
  `purchase gems_80: ok` (`journalctl -u fatebound-siege`). Buy it again (consumable). Then buy `starter_pack` and try to buy it again (Google should refuse).
- Write the result in the Status table.

## 7. Policy forms

- **Data safety**: add **Financial info → Purchase history**: collected, not shared, for **App functionality**
  (the server keeps purchase tokens linked to the player's ID to grant items and handle refunds). Keep the existing
  answers about online play.
- **Content rating**: redo the IARC questionnaire and answer **yes** to in-app purchases of digital goods.
- **Privacy policy** (`privacy.html` in the repo root): Claude will add a purchases paragraph. Make sure the Play
  listing still points at it.
- **Target audience**: if the declared audience includes children under 13, **stop and tell Kevin**. Google's
  Families rules then apply to how purchases are offered.
- The "Contains in-app purchases" label on the listing appears automatically once products are active.

## Status (Grokbot fills this in)

| Step | Done? | Date | Notes (IDs, emails, results; no secrets) |
|---|---|---|---|
| Play Billing commit landed (Claude) | yes | 2026-10-09 | 0.31.90; Play preset packs GodotGooglePlayBilling 3.3.0 (Billing Library 9.1.0) |
| 1 Payments profile | yes | 2026-10-09 | Payments profile created by Kevin (public name Vellic Games). Account group = Vellic Games only (no associated developer accounts), enrolled in the 15% service fee tier. Merchant gate cleared; One-time products page now only asks for a build with the BILLING permission (step 2). |
| 2 Internal-testing build | | | versionCode: |
| 3 Products created | | | |
| 4 License testers | yes | 2026-10-09 | midblade4295@gmail.com (Kevin's S21 Ultra account), via the existing "Dev" email list (6 users) now ticked under License testing. Response: RESPOND_NORMALLY. |
| 5 Service account | yes | 2026-10-09 | email: fatebound-purchases@fatebound-play.iam.gserviceaccount.com. GCP project fatebound-play (new, no billing), Google Play Android Developer API enabled. Play Console app-level access to Fatebound only: View financial data + Manage orders and subscriptions (Console also forces read-only View app information / app quality). JSON key installed at /etc/fatebound-siege/play-service-account.json (owner fatebound-siege, mode 600); no other copy kept. Permissions can take up to 24 h to start working. |
| 6 Test purchase | | | |
| 7 Policy forms | yes | 2026-10-09 | Data safety: Financial info > Purchase history (collected, not shared, required, App functionality), encrypted in transit, no accounts, deletion URL = privacy.html. IARC redone with digital purchases = yes, loot boxes/real-money trading = no: ESRB Everyone, PEGI 3, USK all ages, ClassInd 14+, ACB General (In-Game Purchases). Both sent for review (managed publishing on, not published). Target audience: 18+ only. Privacy policy URL: https://cdn.jsdelivr.net/gh/midblade4295/Fatebound@main/privacy.html (its deletion contact is midblade4295@gmail.com; Kevin's preferred contact is vellicgames@gmail.com). |
