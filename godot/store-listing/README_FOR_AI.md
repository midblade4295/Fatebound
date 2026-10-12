# Fatebound: Siege — Google Play store listing package (instructions for an AI agent)

Owner: **Kevin** (solo developer, GitHub `midblade4295`). Game repo: `github.com/midblade4295/Fatebound`,
branch `claude/siege-dev-r5` (sanitized R5 source `d05f585`; this package is now included under
`godot/store-listing/`). Read `godot/PLAY_STORE_HANDOFF.md` for current release build/signing instructions. Every image in this package
is a real render of the game. The screenshots and feature graphic are from **0.31.116 (versionCode 202)**,
branch `claude/siege-dev-r6-local` (Kevin, 0.31.116: "new playstore screenshots and banner ... a mix of cinematic action
screenshots along with gameplay screenshots along with some menu stuff like forge"); the text below is older.

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
5. If a step needs something that isn't here (Kevin's Play account decisions), stop and
   ask Kevin rather than guessing.

## 1. What's in the zip
| Path | What |
|---|---|
| `listing/STORE_LISTING.md` | Human-readable listing: name, short + full description, checklist |
| `listing/listing.json` | Same, machine-readable: text, lengths, screenshot order + captions, facts sheet |
| `graphics/phone_screenshots/01_meteor.png … 08_friends.png` | 8 captioned phone screenshots, upload in this order |
| `graphics/feature_graphic_1024x500.png` | Feature graphic (required): the All Tied Up title over a Villager running the bomb |
| `graphics/raw_renders/*.webp` | The uncaptioned renders they were composed from (cine_*, play_*, menu_*, feature) |
| `fastlane/metadata/android/en-US/…` | The same text + images in fastlane `supply` layout |
| `godot/tools/store3_shots.gd`, `store3_match.gd`, `store3_app.gd` | Godot scripts that render the raw screenshots (cinematic, gameplay, menus) |
| `godot/tools/store3_compose.py` | Adds captions, phones, close-up bubbles and builds the feature graphic (from `raw_renders/`) |
| `tools/store_*` (here) | The 0.19 set's tools, kept for reference |
| `tools/fonts/` | The game's fonts as TTF (Cinzel Black, Nunito ExtraBold) + their SIL OFL licenses |

## 2. The listing (en-US)
- **App name** (≤30): `Fatebound: Siege` — 16 chars
- **Short description** (≤80): 73 chars — see `listing/STORE_LISTING.md`
- **Full description** (≤4000): 1,878 chars — see `listing/STORE_LISTING.md`

Screenshot captions, in order (0.31.116): CALL DOWN THE METEOR · 16 VS 16 CASTLE SIEGES · STEAL THEIR KING.
SAVE YOURS. · ANYONE CAN CHANGE FATE · BLOW THEIR GATE SKY-HIGH · FORGE LEGENDARY WEAPONS · WIN CHESTS, CLAIM LOOT ·
SQUAD UP WITH FRIENDS (each with a subline; `listing/listing.json` → `phone_screenshots`). The listing text still says
"Oracle" in places -- the game now calls her the King; update the text before publishing.

## 3. Fill it in — Play Console (manual)
1. Play Console → the app (**`com.fatebound.game`**) → **Grow users → Store presence → Main store listing**.
2. **App details:** App name, Short description, Full description — paste from `listing/STORE_LISTING.md`.
3. **Graphics:**
   - App icon (512×512, 32-bit PNG) — `graphics/app_icon_512x512.png` (0.31.89, Kevin's pick "King Rescue").
   - Feature graphic — `graphics/feature_graphic_1024x500.png`.
   - Phone screenshots — `graphics/phone_screenshots/01_meteor.png` through `08_friends.png`, in that order.
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
details; renders take minutes each on a software renderer):
```bash
Xvfb :98 -screen 0 1280x1024x24 &
G="$HOME/godot/Godot_v4.7.2-stable_linux.x86_64 --rendering-method mobile --fixed-fps 30 --path ."
# cinematic stills (trailer 6's staged runs, portrait cameras) -> cine_*.png, and the feature picture
RUN=fall PRESET=meteor AT=3.95 ROCK=1 EYE_Y=2.8 LOOK_Y=4.4 NOHATS=1 WARM=0.15 OUT=raw/cine_meteor.png FB_FORCE_HQ=1 DISPLAY=:98 $G --resolution 1080x1920 -s res://tools/store3_shots.gd
RUN=charge PRESET=rally AT=1.9 NOHATS=1 OUT=raw/cine_rally.png FB_FORCE_HQ=1 DISPLAY=:98 $G --resolution 1080x1920 -s res://tools/store3_shots.gd
RUN=charge PRESET=gate_blast AT=7.62 BACK=6.8 EYE_Y=3.2 LOOK_Y=3.3 NOHATS=1 WARM=0.2 OUT=raw/cine_gate_blast.png FB_FORCE_HQ=1 DISPLAY=:98 $G --resolution 1080x1920 -s res://tools/store3_shots.gd
RUN=charge PRESET=rally AT=1.9 NOHATS=1 PAN=-2.2 FOV=44 OUT=raw/feature.png FB_FORCE_HQ=1 DISPLAY=:98 $G --resolution 2048x1000 -s res://tools/store3_shots.gd
# matches with the real HUD (+ close-ups for the bubbles) -> store3_battle(_close).png, store3_rescue(_close).png
CLOSE=1 SCENES=battle,rescue OUT_DIR=raw FB_FORCE_HQ=1 DISPLAY=:98 $G --resolution 1080x2400 -s res://tools/store3_match.gd
#   (rename them play_battle.png, play_battle_close.png, play_rescue.png, play_rescue_close.png)
# menus -> menu_forge.png, menu_chest.png, menu_friends.png
for P in forge chest friends; do PART=$P OUT_DIR=raw SIEGE_URL=ws://127.0.0.1:1 DISPLAY=:98 $G --resolution 1080x2400 -s res://tools/store3_app.gd; done
# captions, phones, bubbles, feature graphic
python3 tools/store3_compose.py --raw raw --out out
```
Notes: each tool ends its own process once its files are written (Godot can hang on exit after these runs); blasts are seeded (SEED) so a still repeats; the menu
shots never reach the live server (sample names on the Friends window). Look at every image before using it.
Captions live in `SHOTS` in `tools/store3_compose.py` -- each checked against the game's code.

## 6. Before Kevin publishes (checklist — his decisions, don't answer them yourself)
- **In-app purchases:** the text mentions no prices. If gems / the premium Siege Pass are sold for real
  money, Play labels the app automatically once billing products exist.
- **Ads:** declare truthfully in the Play Console (the text makes no claim).
- **Privacy policy + Data safety:** online play connects to Kevin's Siege server (player name, match
  inputs) — Play requires a privacy-policy URL and the Data safety form.
- **Content rating:** IARC questionnaire (cartoon fantasy violence).
- **App icon:** `graphics/app_icon_512x512.png` (also `fastlane/metadata/android/en-US/images/icon.png` for supply).
