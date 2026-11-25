# Drums of War: art slice

A three-minute, portrait card battler set in the black-powder era: Union blue against
Confederate crimson. This folder is a **new, separate Godot 4.7 project**. It shares the
toolchain with Fatebound Siege (`../godot`) and none of its code, assets, package or keys.

This is stage 2 of the concept. Stage 1 was a grey box that proved the rules; this stage shows
the same match in the chosen art style: a 3D battlefield, generated character and prop models,
smoke, sound, and card portraits. The rules engine is unchanged.

![The art slice: a match in progress](docs/artslice.png)

## Run and test

```bash
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64

$GODOT --path drums_of_war                      # play (desktop window, mouse = touch)
GODOT=$GODOT drums_of_war/tools/run_tests.sh    # all tests, headless, about 10 s

# Screenshots of a bot-versus-bot match on the real screen (needs a display):
xvfb-run -a $GODOT --rendering-method mobile --fixed-fps 30 --resolution 540x960 \
    --path drums_of_war -s tools/capture.gd

# Every generated model, fitted the way the game fits it (SHEET_NAMES=u_line,cannon to pick):
xvfb-run -a $GODOT --rendering-method mobile --resolution 540x960 \
    --path drums_of_war -s tools/model_sheet.gd
```

The test runner imports assets first when any are new; models, textures and sounds cannot be
loaded until Godot has imported them.

Android prototype APK (package `com.fatebound.drumsofwar.proto`, arm64, signed with a debug key
you supply; never the Fatebound preview key or the Play upload key):

```bash
GODOT=$GODOT ANDROID_HOME=/path/to/android-sdk KEYSTORE=/path/to/debug.keystore \
    drums_of_war/tools/build_preview.sh
```

Tests: `parse_all` (every script and scene loads), `rules_test` (73 checks of the rules below),
`bot_match_test` (24 full bot-versus-bot matches; `SEEDS=60` for more), `app_smoke_test`
(the real screen through real clicks: select, refused placement, deploy, a full match, rematch).

## How to play

Tap a card, then tap your half of the field (or tap a card and tap again to put it down).
Powder refills by itself, twice as fast in the last minute. Destroy the enemy Headquarters to
win outright; otherwise the side that has destroyed more redoubts wins on time, and a level
match goes to one minute of sudden-death overtime.

## What is in

| Rule | Where to look |
|---|---|
| Regiments fire in volleys, then reload. The first volley hits half again as hard. | `_fire_at_regiment`, `_volley_damage` |
| Hits in the same instant land together, so neither side gains from acting first. | `_deferring`, `_pending` |
| Nerve falls with losses, faster from flank fire and charges. At zero the regiment routs, runs for Headquarters and rallies there at half nerve. | `_damage`, `_update_rout` |
| Line Infantry forms square when cavalry closes. It takes 1.5 s, or 2.5 s if caught reloading. A formed square throws the charge back. | `_update_square`, `_melee` |
| Militia and Skirmishers cannot form square. | `can_square` in `data/cards.json` |
| The creek is crossed only at the bridge and two fords. Fords are 40% slower and nobody fires from the water. | `_waypoint`, `in_ford_water` |
| Field Gun roundshot ploughs through everything in its path and punishes columns and squares; grapeshot at close range. A gun runs out of ammunition after 35 s. | `_fire_gun` |
| A fallen enemy redoubt lets you deploy across the creek on that flank. | `deploy_depth` |
| Orders: Fire! (a regiment fires at once) and Rally (stop a rout, restore nerve). | `_play_order` |

## Layout

- `data/cards.json`: every card's numbers. Balancing is editing this file.
- `scripts/sim/battle_sim.gd`: the rules. Pure data at a fixed 20 steps a second with its own
  seeded random source, so the same seed and the same deploys always give the same battle.
- `scripts/sim/bot.gd`: the computer opponent. It plays through the same `deploy()` a player uses.
- `scripts/view/battle_screen.gd`: runs the match, takes input, plays sound, and draws the HUD
  over the 3D view: wood-and-brass bars, the clock plaque, framed cards with gold-coin costs,
  the Powder slots, health and nerve bars, and the outlined combat callouts. All of it is drawn
  in code; the wood grain is a generated noise texture.
- `scripts/view/battle_world.gd`: the 3D battlefield: structures, regiments in formation, smoke,
  flashes, lighting, and the camera that fits the field to whatever shape the screen is.
- `scripts/view/arena.gd`: the scenery, set in autumn: ground sculpted with a real creek channel,
  water, grass tufts and reeds, wheat, woods in fall colours, leaf litter and falling leaves,
  pumpkins and hay bales, drifting cloud shadow, sunbeams and motes, stepping stones. Units wade the fords and climb the
  bridge because the view asks it how high the ground is.
- `scripts/view/musket_drill.gd`: makes infantry hold their muskets. It moves the musket through
  drill positions (shoulder, port, aim, recoil, load, charge) and places both hands on it with
  two-bone inverse kinematics, after the body clip has played.
- `scripts/view/models.gd`: hands out figures and props. A generated model is used when
  `assets/models/<name>/<name>.glb` exists; otherwise a primitive stand-in is built, so any card
  can be played before its model is made.
- `assets/models/<name>/`: the model, the reference image it was generated from (`ref.png`),
  how it was made (`meta.json`), and for structures a crimson texture for the enemy's copy.
- `assets/audio/`: sound effects and the battle tune; `SOURCES.md` lists how each was made.
- `assets/cards/`: card portraits, made from the reference images by `tools/make_card_art.py`.
- `tests/`, `tools/`: headless tests, the test runner, screenshot and model-sheet tools, and
  `tools/prepare_model.py`, which shrinks a generated model's textures.

## How the art is made

1. A reference image per asset in the approved style: one subject on white, characters in an
   A-pose with empty hands.
2. Image-to-3D at a set triangle count, then auto-rigging for characters.
3. `tools/prepare_model.py` shrinks textures (and writes the crimson texture for structures);
   `models.gd` turns each model to face forward, scales it, and puts a musket in infantry hands.
4. Animation clips (idle, walk, run, fire, death) were made once, for the Union line
   infantryman. Every other rigged character borrows them, because the rigs share one skeleton.

Cavalry are single unrigged models. A vertex shader swings everything below the horse's belly
fore and aft and rocks the body, which reads as a gallop at game distance; a real gait needs a
quadruped rig, which this stage does not have.

The game fills the screen on any shape of display (`window/stretch/aspect="expand"`); the HUD
is pinned to the top and bottom, clear of a notch or gesture bar, and the camera refits the field.

## Not in yet

The other ten cards of the 18-card launch deck, smoke as a rule (it is a visual effect only),
deck building, a menu, and online play. Known rough edges in this stage: the sounds were chosen
by measurement and have not been listened to; the body clips under the musket drill are still
the first set (a wide-stance idle, a plain walk); every tree is the one tree model in different
sizes and fall colours (reference images for an oak, pine, birch, bush and log are in `assets/models/`
but their models have not been made); the HUD is still plain. The Android APK builds
and is signed, but has not been run on a physical phone, and nothing here has been profiled on
one. Balance is the stage 1 first pass, tuned on bot-versus-bot matches.
