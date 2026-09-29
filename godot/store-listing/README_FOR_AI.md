# Fatebound: Siege — Google Play store listing package (instructions for an AI agent)

Owner: **Kevin** (solo developer, GitHub `midblade4295`). Game repo: `github.com/midblade4295/Fatebound`,
branch `claude/siege-dev-r5` (sanitized R5 source `d05f585`; this package is now included under
`godot/store-listing/`). Read `godot/PLAY_STORE_HANDOFF.md` for current release build/signing instructions. Every image in this package
is a real render of game build **0.19.1-siege-tutorial (versionCode 40)**.

> Run the fastlane command from the repository root. Screenshot commands run from `godot/`.
> Archive store-listing tools/assets are development material: exclude `store-listing/*` from Android game exports.
> This upload to GitHub does not authorize changes to Play Console or publication.

## 0. Hard rules — read first
1. **Do not publish, roll out, or promote any release** on Google Play, and do not change a production
   track, without Kevin's explicit go-ahead. Filling in / saving the store listing draft is fine; sending
   the app for review or publishing is Kevin's call.
2. **Do not upload the preview APKs** (`Fatebound-Siege-*.apk`). They are package
   `com.fatebound.kaykitrebuild`, signed with a *preview* key — not the Play app. The Play app is
   `com.fatebound.game` (Godot export preset "Android Play Store"); a Play release needs an AAB from that
   preset signed with Kevin's upload key. Never create, move or use production signing keys.
3. **Don't invent claims.** Everything the listing says is true of the build; `listing/listing.json` →
   `game_facts` is the verified fact sheet (from the game code). Keep "Cosmetics only. No pay-to-win."
   true — if anything paid ever affects gameplay, remove that line and screenshot 7's caption.
4. **Don't alter the screenshots** except by regenerating them with `tools/` (section 5). Play forbids
   misleading screenshots; these show the real game with its real HUD.
5. If a step needs something that isn't here (the app icon, Kevin's Play account decisions), stop and
   ask Kevin rather than guessing.

## 1. What's in the zip
| Path | What |
|---|---|
| `listing/STORE_LISTING.md` | Human-readable listing: name, short + full description, checklist |
| `listing/listing.json` | Same, machine-readable: text, lengths, screenshot order + captions, facts sheet |
| `graphics/phone_screenshots/01_battle.png … 08_home.png` | 8 captioned phone screenshots, upload in this order |
| `graphics/feature_graphic_1024x500.png` | Feature graphic (required) |
| `graphics/raw_renders/store_*.png` | Uncaptioned 1080×1920 renders (+ 1600×782 `store_feature.png`) the images were made from |
| `fastlane/metadata/android/en-US/…` | The same text + images in fastlane `supply` layout |
| `tools/store_shots_match.gd`, `tools/store_shots_app.gd` | Godot scripts that render the raw screenshots |
| `tools/store_compose.py` | Adds captions/frames and builds the feature graphic (reproduces these files pixel for pixel) |
| `tools/fonts/` | The game's fonts as TTF (Cinzel Black, Nunito ExtraBold) + their SIL OFL licenses |

## 2. The listing (en-US)
- **App name** (≤30): `Fatebound: Siege` — 16 chars
- **Short description** (≤80): 73 chars — see `listing/STORE_LISTING.md`
- **Full description** (≤4000): 1,878 chars — see `listing/STORE_LISTING.md`

Screenshot captions, in order: STORM THE CASTLE · RESCUE YOUR ORACLE · THE HAT MAKES THE HERO ·
SPIN. SHIELD. SMASH. · FEED THEIR ORACLE CAKE · LEARN FROM THE HERALD · SKINS, WEAPONS & PACKS · SEVEN CLASSES

## 3. Fill it in — Play Console (manual)
1. Play Console → the app (**`com.fatebound.game`**) → **Grow users → Store presence → Main store listing**.
2. **App details:** App name, Short description, Full description — paste from `listing/STORE_LISTING.md`.
3. **Graphics:**
   - App icon (512×512, 32-bit PNG) — **not in this package**; ask Kevin.
   - Feature graphic — `graphics/feature_graphic_1024x500.png`.
   - Phone screenshots — `graphics/phone_screenshots/01_…` through `08_…`, in that order.
   - Tablet screenshots — none provided (optional; skip unless Kevin asks).
4. **Save** the draft. Do **not** send for review / publish (rule 1).

## 4. Fill it in — fastlane supply (automated, listing only)
```bash
fastlane supply --package_name com.fatebound.game \
  --json_key <Kevin's service-account JSON> \
  --metadata_path godot/store-listing/fastlane/metadata/android \
  --skip_upload_apk true --skip_upload_aab true --skip_upload_changelogs true \
  --validate_only true          # dry run first; drop it only with Kevin's OK
```
The service-account key and Play access are Kevin's; don't create or request credentials yourself.

## 5. Regenerate the images (after the game changes)
Needs: Godot 4.7.2 (Linux), Xvfb, Python 3 with Pillow (+ `fonttools brotli` only if the TTFs are
missing), the repo at `claude/siege-dev-r5`. From the repo's `godot/` folder:
```bash
Xvfb :95 -screen 0 1700x2000x24 & sleep 2
# in-match scenes (battle, rescue, hats, abilities, feed) -> /tmp/store_<name>.png
DISPLAY=:95 godot --rendering-method mobile --resolution 1080x1920 --path . -s res://store-listing/tools/store_shots_match.gd
# feature scene (wide, no HUD) -> /tmp/store_feature.png
DISPLAY=:95 SCENES=feature godot --rendering-method mobile --resolution 1600x782 --path . -s res://store-listing/tools/store_shots_match.gd
# home + shop -> /tmp/store_home.png, /tmp/store_shop.png ; tutorial -> /tmp/store_tutorial.png
DISPLAY=:95 godot --rendering-method mobile --resolution 1080x1920 --path . -s res://store-listing/tools/store_shots_app.gd
DISPLAY=:95 PART=tutorial godot --rendering-method mobile --resolution 1080x1920 --path . -s res://store-listing/tools/store_shots_app.gd
# captions, frames, feature graphic
python3 store-listing/tools/store_compose.py --raw /tmp --out store_out --fonts store-listing/tools/fonts
```
Notes: the scripts hide the dev fps line and switch off the game's heat guard (software rendering
looks like a hot phone and would show a "30 FPS mode" toast / lower the 3D resolution). Bot scenes are
seeded from the clock, so each render differs slightly — look at every image before using it. Captions
live in `SHOTS` in `tools/store_compose.py`.

## 6. Before Kevin publishes (checklist — his decisions, don't answer them yourself)
- **In-app purchases:** the text mentions no prices. If gems / the premium Siege Pass are sold for real
  money, Play labels the app automatically once billing products exist.
- **Ads:** declare truthfully in the Play Console (the text makes no claim).
- **Privacy policy + Data safety:** online play connects to Kevin's Siege server (player name, match
  inputs) — Play requires a privacy-policy URL and the Data safety form.
- **Content rating:** IARC questionnaire (cartoon fantasy violence).
- **App icon:** 512×512 needed (not included).
