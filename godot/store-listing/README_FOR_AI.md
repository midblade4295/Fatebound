# Fatebound — Google Play and App Store listing package (instructions for an AI agent)

Owner: **Kevin** (solo developer, GitHub `midblade4295`). Game repo: `github.com/midblade4295/Fatebound`,
branch `claude/siege-dev-r5` (sanitized R5 source `d05f585`; this package is now included under
`godot/store-listing/`). Read `godot/PLAY_STORE_HANDOFF.md` for current release build/signing instructions. Every image in this package
is made from real renders of the game. The screenshots are 0.31.212's (Kevin: "Now I want new higher quality app store
screenshots", Clash Royale's store page as the reference): landscape, a hero big in 3D, a two-line headline and the game
on a phone (the phone's renders, the feature graphic and the listing text are from 0.31.199-0.31.200, the 5v5 game,
branch `claude/siege-dev-r6-local`). The app icon is 0.31.211's (the King in front of his throne).

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
| `graphics/phone_screenshots/01_keyart.jpg … 08_squad.jpg` | Google Play: 8 phone screenshots (2560×1440, 16:9 landscape), upload in this order |
| `graphics/feature_graphic_1024x500.png` | Google Play feature graphic (required): the FATEBOUND title over a 5v5 fight |
| `graphics/app_store/iphone_6_9in/01_keyart.jpg … 08_squad.jpg` | App Store iPhone 6.9" screenshots (2868×1320 landscape), in this order |
| `graphics/app_store/ipad_13in/01_keyart.jpg … 08_squad.jpg` | App Store iPad 13" screenshots (2732×2048 landscape) -- needed while the export allows iPad |
| `graphics/raw_renders/*.webp` | The game's renders: `<shot>_play` (9:16, on the screenshots' phones), `_phone` 19.5:9, `_ipad` 3:4 (the 0.31.199 portrait set's), `feature` |
| `graphics/raw_renders/store5/` | The landscape set's other inputs: `art/store_<hero>_wide.webp` (the hero art) and `bg/<scene>.webp` (the backdrops) |
| `social/` | The social media kit: banners (X, YouTube, Facebook, Twitch, Discord, link previews, key art) and profile icons -- see `social/README.md`; made by `godot/tools/build_social_kit.py` |
| `muse_kit/` | The text of the social kit for Muse, Kevin's posting bot (rules, the game, the voice, profiles, links); `godot/tools/build_muse_kit.py` builds the whole kit and its zip (pictures, champion cards from `godot/tools/social_champions.gd`, posts, trailer 8's clips) -- the zip isn't kept in the repo |
| `fastlane/metadata/android/en-US/…` | The same text + Play images in fastlane `supply` layout |
| `godot/tools/store4_match.gd`, `store4_app.gd` | Godot scripts that render the raw screenshots (5v5 moments, the app's screens) |
| `godot/tools/store5_compose.py` | Builds the landscape screenshots (backdrop, hero, headline, the game on a phone) |
| `godot/tools/meshy_hd.py`, `render_app_icon.gd` | The heroes and the King rebuilt in high detail (Meshy, from views of the game's models; `art_sources/store_heroes`) and rendered for the art (`store_*` shots) |
| `godot/tools/store4_compose.py` | The 0.31.199 portrait set's captions and devices, and the feature graphic (from the raw renders) |
| `tools/store_*` (here) | The 0.19 set's tools, kept for reference |
| `tools/fonts/` | The game's fonts as TTF (Cinzel Black, Nunito ExtraBold) + their SIL OFL licenses |

## 2. The listing (en-US)
- **App name** (≤30): `Fatebound: 5v5 MOBA Battles` — 27 chars (0.31.212: the heycatch.ai listing audit's D1.1 -- the primary keyword in the title)
- **Short description** (≤80): 77 chars — see `listing/STORE_LISTING.md`
- **Full description** (≤4000): 3,186 chars — see `listing/STORE_LISTING.md` (0.31.212: a founder line after the opener and a SUPPORT THE GAME section -- what's sold and what gems buy -- from the audit's action plan)
- **App Store**: subtitle, promotional text and keywords — see `listing/STORE_LISTING.md` → App Store extras

Screenshot headlines, in order (0.31.212; the same 8 on both stores): FAST 5V5 MOBA BATTLES (the heroes together, no phone) · TEAM UP FOR
5V5 HERO BATTLES · PICK FROM 18 CHAMPIONS · PUSH THE LANES AND TOPPLE THEIR KING · SLAY THE GRAVE WYRM · DRESS UP IN
36 OUTFITS · BUILD YOUR CLAN · SQUAD UP WITH FRIENDS (`listing/listing.json` → `phone_screenshots`,
`app_store_screenshots`). Apple wants screenshots to show the app in use: if review objects to the key art (no phone),
drop it from the App Store set -- the other seven all show the game. (The heycatch.ai audit's D3.1: it had no headline;
since 0.31.212 it carries FAST 5V5 MOBA BATTLES in place of the title logo.)

## 3. Fill it in — Play Console (manual)
1. Play Console → the app (**`com.fatebound.game`**) → **Grow users → Store presence → Main store listing**.
2. **App details:** App name, Short description, Full description — paste from `listing/STORE_LISTING.md`.
3. **Graphics:**
   - App icon (512×512, 32-bit PNG) — `graphics/app_icon_512x512.png` (0.31.211: the King in 3D in front of his
     throne; `ios/app_icon_1024.png` is the App Store's; `godot/tools/build_app_icon.py` makes all of them, and the
     app's launcher icons, from `art_sources/app_icon/render`).
   - Feature graphic — `graphics/feature_graphic_1024x500.png`.
   - Phone screenshots — `graphics/phone_screenshots/01_keyart.jpg` through `08_squad.jpg`, in that order.
   - Tablet screenshots — none provided (optional; skip unless Kevin asks).
   - Promo video (the heycatch.ai audit's D3.5) — a YouTube URL: Kevin uploads `Fatebound-Promo-Video.mp4` (made by
     `godot/tools/promo_video.py`, 1920×1080, 29 s, gameplay from the first frame; not kept in the repo) to YouTube as
     Unlisted (not Private: Play can't show a private video) and pastes its link in the Promo video field.
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
Xvfb :97 -screen 0 3000x3000x24 &   # (the landscape backdrops are 2868 wide)
Xvfb :98 -screen 0 1080x1920x24 &
G="$HOME/godot/Godot_v4.7.2-stable_linux.x86_64 --rendering-method mobile --fixed-fps 30 --path ."
# each shot at three sizes: R=play 1080x1920, phone 1080x2340, ipad 1536x2048 -> raw/<key>_<R>.png
SCENE=teamfight OUT=raw/teamfight_play.png FB_FORCE_HQ=1 DISPLAY=:97 $G --resolution 1080x1920 -s res://tools/store4_match.gd
SCENE=king CINE=1 OUT=raw/king_play.png FB_FORCE_HQ=1 DISPLAY=:97 $G --resolution 1080x1920 -s res://tools/store4_match.gd
SCENE=wyrm CINE=1 OUT=raw/wyrm_play.png DISPLAY=:97 $G --resolution 1080x1920 -s res://tools/store4_match.gd   # (no FB_FORCE_HQ: the Wyrm's shadows run lavapipe out of memory)
for P in champion outfit clan home tutorial chest; do PART=$P OUT=raw/${P}_play.png FB_FORCE_HQ=1 DISPLAY=:97 $G --resolution 1080x1920 -s res://tools/store4_app.gd; done
#   ... the same at 1080x2340 (_phone) and 1536x2048 (_ipad); chest only for the App Store
SCENE=feature CINE=1 OUT=raw/feature.png FB_FORCE_HQ=1 DISPLAY=:97 $G --resolution 2048x1000 -s res://tools/store4_match.gd
# captions, devices, feature graphic (the 0.31.199 portrait set)
python3 tools/store4_compose.py --raw raw --out out
# the landscape set (0.31.212): the backdrops, landscape
for S in feature king tower; do SCENE=$S CINE=1 OUT=bg/$S.png FB_FORCE_HQ=1 DISPLAY=:97 $G --resolution 2868x1320 -s res://tools/store4_match.gd; done
SCENE=wyrm CINE=1 OUT=bg/wyrm.png DISPLAY=:97 $G --resolution 2868x1320 -s res://tools/store4_match.gd
# the hero art (needs the HD models: python3 tools/meshy_hd.py fetch ../art_sources/store_heroes/<hero> <hero>)
DISPLAY=:98 SIZE=2400 ONLY=store_knight,store_barbarian,store_mage,store_stormcaller,store_dragoon,store_king OUT_DIR=art \
  $HOME/godot/Godot_v4.7.2-stable_linux.x86_64 --rendering-method forward_plus --path . -s res://tools/render_app_icon.gd
python3 tools/store5_compose.py --art art --raw store-listing/graphics/raw_renders --bg bg --out out5
#   (or from the kept inputs: --art store-listing/graphics/raw_renders/store5/art --bg store-listing/graphics/raw_renders/store5/bg)
```
Notes: each tool ends its own process once its picture is written; the match moments are staged (positions, levels,
casts; seeded), never on the live server (SIEGE_URL unreachable; the names, clan tags and the clan are sample data).
Look at every image before using it. Captions live in `SHOTS` in `tools/store4_compose.py` -- each checked against the
game's code. The App Store sets are kept here as JPEG (quality 95, no chroma subsampling; the App Store takes JPEG or
PNG) to keep the repository small; the 0.31.212 Play set is JPEG too (Play takes JPEG or 24-bit PNG, up to 8 MB). (The 0.31.116 Siege set's store3 tools went with Siege in 0.31.169.)

## 6. Before Kevin publishes (checklist — his decisions, don't answer them yourself)
- **In-app purchases:** the text mentions no prices. If gems / the premium Siege Pass are sold for real
  money, Play labels the app automatically once billing products exist.
- **Ads:** declare truthfully in the Play Console (the text makes no claim).
- **Privacy policy + Data safety:** online play connects to Kevin's Siege server (player name, match
  inputs) — Play requires a privacy-policy URL and the Data safety form.
- **Content rating:** IARC questionnaire (cartoon fantasy violence).
- **App icon:** `graphics/app_icon_512x512.png` (also `fastlane/metadata/android/en-US/images/icon.png` for supply).
