# Fatebound — Google Play and App Store listing package (instructions for an AI agent)

Owner: **Kevin** (solo developer, GitHub `midblade4295`). Game repo: `github.com/midblade4295/Fatebound`,
branch `claude/siege-dev-r5` (sanitized R5 source `d05f585`; this package is now included under
`godot/store-listing/`). Read `godot/PLAY_STORE_HANDOFF.md` for current release build/signing instructions. Every image in this package
is a real render of the game. The screenshots and feature graphic are from **0.31.199 (versionCode 285)**, the 5v5
game, branch `claude/siege-dev-r6-local` (Kevin: "Need all new pics for app stores"): Google Play's phone set and
feature graphic, and the App Store's iPhone 6.9" and iPad 13" sets. The listing text and the app icon are 0.31.200's
(Kevin: "Yes make new game icon and store description").

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
   `game_facts` is the verified fact sheet (from the game code). Keep "Outfits are cosmetic only" true —
   if an outfit ever changes gameplay, remove that line. (Champions can be bought with gems as well as won with gold,
   so the text doesn't claim "no pay-to-win".)
4. **Don't alter the screenshots** except by regenerating them with `tools/` (section 5). Play forbids
   misleading screenshots; these show the real game with its real HUD.
5. If a step needs something that isn't here (Kevin's Play account decisions), stop and
   ask Kevin rather than guessing.

## 1. What's in the zip
| Path | What |
|---|---|
| `listing/STORE_LISTING.md` | Human-readable listing: name, short + full description, checklist |
| `listing/listing.json` | Same, machine-readable: text, lengths, screenshot order + captions, facts sheet |
| `graphics/phone_screenshots/01_teamfight.png … 08_tutorial.png` | Google Play: 8 captioned phone screenshots (1080×1920), upload in this order |
| `graphics/feature_graphic_1024x500.png` | Google Play feature graphic (required): the FATEBOUND title over a 5v5 fight |
| `graphics/app_store/iphone_6_9in/01_teamfight.jpg … 09_chest.jpg` | App Store iPhone 6.9" screenshots (1320×2868), in this order |
| `graphics/app_store/ipad_13in/01_teamfight.jpg … 09_chest.jpg` | App Store iPad 13" screenshots (2048×2732) -- needed while the export allows iPad |
| `graphics/raw_renders/*.webp` | The uncaptioned renders they were composed from (`<shot>_play` 16:9, `_phone` 19.5:9, `_ipad` 3:4, `feature`) |
| `fastlane/metadata/android/en-US/…` | The same text + Play images in fastlane `supply` layout |
| `godot/tools/store4_match.gd`, `store4_app.gd` | Godot scripts that render the raw screenshots (5v5 moments, the app's screens) |
| `godot/tools/store4_compose.py` | Adds captions and devices and builds the feature graphic (from the raw renders) |
| `tools/store_*` (here) | The 0.19 set's tools, kept for reference |
| `tools/fonts/` | The game's fonts as TTF (Cinzel Black, Nunito ExtraBold) + their SIL OFL licenses |

## 2. The listing (en-US)
- **App name** (≤30): `Fatebound: 5v5 Hero Battles` — 27 chars (the Play listing still says "Fatebound: Siege" until saved)
- **Short description** (≤80): 77 chars — see `listing/STORE_LISTING.md`
- **Full description** (≤4000): 2,238 chars — see `listing/STORE_LISTING.md`
- **App Store**: subtitle, promotional text and keywords — see `listing/STORE_LISTING.md` → App Store extras

Screenshot captions, in order (0.31.199): 5V5 HERO BATTLES · 18 CHAMPIONS · TOPPLE THEIR KING · SLAY THE GRAVE WYRM ·
36 OUTFITS · BUILD YOUR CLAN · SQUAD UP · LEARN FROM THE HERALD, and on the App Store also OPEN CHESTS (each with a
subline; `listing/listing.json` → `phone_screenshots`, `app_store_screenshots`).

## 3. Fill it in — Play Console (manual)
1. Play Console → the app (**`com.fatebound.game`**) → **Grow users → Store presence → Main store listing**.
2. **App details:** App name, Short description, Full description — paste from `listing/STORE_LISTING.md`.
3. **Graphics:**
   - App icon (512×512, 32-bit PNG) — `graphics/app_icon_512x512.png` (0.31.200: a Knight and a Barbarian clash over
     the logo's fire-and-ice rift; `ios/app_icon_1024.png` is the App Store's; `godot/tools/build_app_icon.py` makes all
     of them, and the app's launcher icons, from `art_sources/app_icon/icon.png`).
   - Feature graphic — `graphics/feature_graphic_1024x500.png`.
   - Phone screenshots — `graphics/phone_screenshots/01_teamfight.png` through `08_tutorial.png`, in that order.
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
Needs Godot 4.7.2 (Linux), Xvfb, Python 3 with Pillow. From the repo's `godot/` folder (each tool's header has the
details; a render takes a few minutes on a software renderer, and up to ~3 GB of memory):
```bash
Xvfb :97 -screen 0 2400x2900x24 &
G="$HOME/godot/Godot_v4.7.2-stable_linux.x86_64 --rendering-method mobile --fixed-fps 30 --path ."
# each shot at three sizes: R=play 1080x1920, phone 1080x2340, ipad 1536x2048 -> raw/<key>_<R>.png
SCENE=teamfight OUT=raw/teamfight_play.png FB_FORCE_HQ=1 DISPLAY=:97 $G --resolution 1080x1920 -s res://tools/store4_match.gd
SCENE=king CINE=1 OUT=raw/king_play.png FB_FORCE_HQ=1 DISPLAY=:97 $G --resolution 1080x1920 -s res://tools/store4_match.gd
SCENE=wyrm CINE=1 OUT=raw/wyrm_play.png DISPLAY=:97 $G --resolution 1080x1920 -s res://tools/store4_match.gd   # (no FB_FORCE_HQ: the Wyrm's shadows run lavapipe out of memory)
for P in champion outfit clan home tutorial chest; do PART=$P OUT=raw/${P}_play.png FB_FORCE_HQ=1 DISPLAY=:97 $G --resolution 1080x1920 -s res://tools/store4_app.gd; done
#   ... the same at 1080x2340 (_phone) and 1536x2048 (_ipad); chest only for the App Store
SCENE=feature CINE=1 OUT=raw/feature.png FB_FORCE_HQ=1 DISPLAY=:97 $G --resolution 2048x1000 -s res://tools/store4_match.gd
# captions, devices, feature graphic
python3 tools/store4_compose.py --raw raw --out out
```
Notes: each tool ends its own process once its picture is written; the match moments are staged (positions, levels,
casts; seeded), never on the live server (SIEGE_URL unreachable; the names, clan tags and the clan are sample data).
Look at every image before using it. Captions live in `SHOTS` in `tools/store4_compose.py` -- each checked against the
game's code. The App Store sets are kept here as JPEG (quality 95, no chroma subsampling; the App Store takes JPEG or
PNG) to keep the repository small; the Play set is PNG. (The 0.31.116 Siege set's store3 tools went with Siege in 0.31.169.)

## 6. Before Kevin publishes (checklist — his decisions, don't answer them yourself)
- **In-app purchases:** the text mentions no prices. If gems / the premium Siege Pass are sold for real
  money, Play labels the app automatically once billing products exist.
- **Ads:** declare truthfully in the Play Console (the text makes no claim).
- **Privacy policy + Data safety:** online play connects to Kevin's Siege server (player name, match
  inputs) — Play requires a privacy-policy URL and the Data safety form.
- **Content rating:** IARC questionnaire (cartoon fantasy violence).
- **App icon:** `graphics/app_icon_512x512.png` (also `fastlane/metadata/android/en-US/images/icon.png` for supply).
