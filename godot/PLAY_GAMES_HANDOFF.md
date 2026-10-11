# Fatebound: Google Play Games sign-in and cloud save, Play Console side (for Grokbot)

Written 2026-10-11. Kevin: "Google play account linking to the game". Claude wrote the game code on branch
`claude/siege-dev-r6-local` (0.31.102). This file is what has to happen in Play Console / Google Cloud before it works,
and the order to do it in. Same rules as `godot/PLAY_IAP_HANDOFF.md`.

## What the game does (so you know what you're configuring)

- Uses **Google Play Games Services v2** (plugin `addons/GodotPlayGameServices`, play-services-games-v2 21.0.0).
- **Sign-in**: automatic at start when the phone has Play Games, or **SIGN IN WITH GOOGLE PLAY** in Settings.
- **Cloud save**: one **Saved Game** named `fatebound-profile` holds the player's whole profile. On sign-in the game
  reads it first. It restores it on a fresh install, uploads on the first link, and asks the player when both the
  phone and the account have different progress. After that it uploads every couple of minutes while progress
  changes, and when the app goes to the background.
- **Nothing reaches our server.** No server-side access, no OAuth web client, no new secrets.
- **Not used yet:** achievements, leaderboards, events. Don't create any.

## Ground rules

1. **Internal testing only.** Do not publish to production, closed or open tracks.
2. **The Game ID is not a secret** (it ends up in the app's manifest). Keystores, passwords and service-account
   JSON still never go in git.
3. **Steps that need Kevin in person** are marked **[Kevin]**.
4. **Fill in the Status table** at the bottom when you finish a step, and commit just this file.
5. **Never build without the Game ID and then ship it as "Play Games".** Without the Game ID the bundle simply has no
   Play Games. That is safe: Settings says it's unavailable. With the plugin but no ID, the Play Games SDK would stop
   the app at launch. The export plugin and `verify_play_bundle.py` both prevent that combination; don't work around them.

## 1. Create the Play Games Services project

Play Console → **Fatebound** → **Grow users → Play Games Services → Setup and management → Configuration**.

- Choose **"Yes, my game already uses Google APIs"** and pick the existing Cloud project **`fatebound-play`**, the one
  that holds the purchase-check service account. One project for everything is easier to manage.
  - If Console won't offer it, create a new one ("No, my game doesn't use Google APIs").
  - Write down which you did.
- Note the **Game ID** (also called the project ID). It's the 12-digit number shown at the top of the Play Games
  Services configuration page.

## 2. Properties

Configuration → **Properties**:
- **Display name**: Fatebound.
- **Default language**: English (US).
- **Saved games: ON.** This is required. Without it every save and load fails, and the game shows "Couldn't reach
  Google Play saves".

## 3. Credentials (the OAuth consent screen and the Android client)

Configuration → **Credentials → Add credential → Android**.

- Console first sends you to set up the **OAuth consent screen** in Google Cloud for that project:
  - User type **External**, app name **Fatebound**.
  - Support email: **[Kevin]** chooses: midblade4295@gmail.com, or vellicgames@gmail.com (his preferred contact).
  - App domain / privacy policy: the same URL as the store listing.
  - Scopes: none extra (Play Games adds its own).
  - Leave it in **Testing** with Kevin's account as a test user, or publish it. Publishing needs no review with
    only the default scopes.
- Then create the **Android** OAuth client:
  - Package **`com.fatebound.game`**.
  - SHA-1: the **app signing key certificate**, from Play Console → **Test and release → App integrity → App signing**.
    That is the certificate on every build installed from Play, internal testing included.
- Add a **second Android credential with the upload key's SHA-1** only if a locally built, upload-key-signed build will
  ever be sideloaded for testing. Builds from the internal-testing link don't need it.
- Leave **Authorization**, the "server" client and the other client types alone.

## 4. Testers

Configuration → **Testers**: add **midblade4295@gmail.com** (Kevin's S21 Ultra account), or the existing "Dev" list.
Until the Play Games configuration is published, only these accounts can sign in.

## 5. Put the Game ID in the build

Either (preferred, committed):

```
godot/export_presets.cfg, section [preset.0.options] ("Android Play Store"):
godot_play_game_services/game_id="<the 12-digit Game ID>"
```

or pass it per build: `PLAY_GAMES_APP_ID=<id> godot/tools/build_play_release.sh` (with the usual variables).

Check the export log for `[GodotPlayGameServices] Game ID <id> in res/values/play_games_ids.xml`. Also check that
`verify_play_bundle.py` reports `"play_games": true`. With `PLAY_GAMES_APP_ID` set, it fails if Play Games is missing.

## 6. Internal-testing build

Build and upload the next versionCode exactly as `godot/PLAY_STORE_HANDOFF.md` says, from this branch (0.31.102 or
newer). Content packs: `content_packs.py check` must print `CONTENT OK` (0.31.102 changed no art).

## 7. Test on Kevin's phone [Kevin, with you]

1. Install from the internal-testing link. Open **Settings**. The **GOOGLE PLAY** card should show "Signed in as
   <name>. Your progress is backed up to your Google account (just now)."
   - If it says "Not signed in", tap **SIGN IN WITH GOOGLE PLAY**.
   - If sign-in fails at once, the SHA-1 in step 3 or the tester list in step 4 is wrong. This is the usual cause.
2. Play a match, wait 2 minutes or press **BACK UP NOW**: "Backed up to Google Play".
3. Clear the app's storage (Android Settings → Apps → Fatebound → Storage → Clear storage) and open it again. After
   the content download it should sign in and toast "Progress restored from Google Play", with level, gold and gems as
   before.
4. (Optional, needs a second phone or an emulator signed in to the same account.) Play on both, then reopen one: it
   asks **WHICH PROGRESS?** with both sides listed.

Write down what happened in the Status table: which steps worked, and any toast text.

## 8. Policy forms

- **Data safety**: the app now sends the player's game progress to Google Play Games (Saved Games, in the player's
  own Google account) and reads their Play Games display name, only when they sign in.
  - Review the form against Google's current guidance for Play Games Services and declare what it asks for.
  - Our server still gets nothing new.
- **Privacy policy**: `privacy.html` (repo root) has a new "Google Play Games" section (updated 11 October 2026).
  Redeploy it with the build.
- Note: the policy's opening sections still describe the older dice-arena version and Firebase. Tell Kevin if that
  should be rewritten for Siege. Don't change it on your own.

## Status (Grokbot fills this in)

| Step | Done? | Date | Notes (IDs, results; no secrets) |
|---|---|---|---|
| Play Games code landed (Claude) | yes | 2026-10-11 | 0.31.102; plugin 3.4.0 built for Godot 4.7.2; throwaway-key Play export checked: with a test ID the AAB has the plugin, APP_ID meta-data and the ID resource; without one, none of it |
| 1 Play Games project | | | |
| 2 Properties (Saved games ON) | | | |
| 3 Credentials (consent screen, Android client, SHA-1) | | | |
| 4 Testers | | | |
| 5 Game ID in the build | | | |
| 6 Internal-testing build | | | |
| 7 Test on Kevin's phone | | | |
| 8 Policy forms | | | |
