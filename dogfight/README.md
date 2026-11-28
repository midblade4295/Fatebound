# Squadron Skies 5v5 (working title)

Stylized 5v5 WWII dogfighting for landscape phones, built in Godot 4
(GDScript, Mobile renderer). It looks like a cartoon and flies like an
aeroplane: every plane is a rigid body in real gravity that can loop, roll,
stall and spin, in air that thins with height, on wheels that bounce, swing
and break. The Hurricane, the Spitfire and the Mustang are each modelled to
their real dimensions, and stand on their real undercarriage. Nothing flies
the take-off or the landing for the pilot.

It is played one life at a time. Every kill adds to a bounty, and none of it
is yours until you have landed on your own runway and cashed out. Get killed
and you leave with nothing, and without the aeroplane. Gold buys planes,
real weapons and aircraft components; there is no experience and there are
no levels.

This folder is a **stand-alone Godot project**. It shares nothing with the Siege
project in `../godot`; open `dogfight/project.godot` directly.

- Engine: written and tested on Godot **4.7.2**. Uses typed dictionaries and
  physics interpolation, so 4.4 is the practical minimum.
- Flow: `MainMenu` (Hangar) -> `MatchLobby` -> `DogfightArena5v5` -> Hangar.
- Offline today: 1 player + 9 bots. The scene/script split is laid out for
  `MultiplayerSpawner` / `MultiplayerSynchronizer`, but **no online session code
  exists yet and nothing has been tested with a second peer**.

Reference captures (software-rendered at 1280x720): `docs/coast_cliffs.png`,
`docs/coast_fields.png`, `docs/takeoff.png`, `docs/hangar.png`,
`docs/three_fighters.png`.

## Controls

| Action | Touch | Keyboard (desktop testing) |
| --- | --- | --- |
| Stick: sideways rolls (on the ground: steers), back pulls the nose up | left-thumb floating stick | WASD or arrows |
| Rudder pedals: swing the nose left / right | the two RUDDER buttons (hold) | Q / E or Z / C |
| Fire | FIRE button (hold) | Space |
| Throttle | lever beside the buttons (stays where you leave it) | R / F or PgUp / PgDn |
| Engine start / stop | ENGINE button (lamp = running) | I |
| Undercarriage up / down | GEAR button (lamp = down) | G |

It is a real stick. Sideways does not turn the plane, it rolls it: to turn,
roll into a bank and pull. Hold the stick over and it keeps rolling, right
round. Hold it back and it goes over the top in a loop. Let go and the plane
stays in whatever attitude it is in, trimmed for 1 g.

Full back stick is a pull **to the buffet**: all the lift the wing has at
that speed, and no further. A pilot holds a hard turn there by the feel of
the stick; a thumb on glass has no feel, so the pilot's hand stops there for
it (`FlightPilot.pull_to_the_buffet`). You cannot stall the wing by just
hauling back, at any speed. What you still can do is run out of speed (hold
it back in a climb and the nose comes down by itself), and ask for a stall
on purpose: stick back *and* a rudder pedal held is a flick into a spin. Left alone, the pedals
are worked for you (the pilot's feet keep turns tidy); touch one and it is
yours, for side-slips, for holding the nose straight on take-off, and for
getting out of a spin. The stick has a curve on it so that small movements
near the middle are fine ones (`PlayerController.STICK_CURVE`).

Stick up = nose up. `Profile.invert_pitch` flips it. Mouse clicks act as touches
on desktop (`emulate_touch_from_mouse`), so the on-screen controls work there too.
In the hangar the plane stands with its engine stopped. Drag with one finger
to move the camera round it, pinch to zoom, drag with two fingers to slide the
plane about the screen, double-tap to put the view back (mouse: drag, wheel,
right-drag). Touches that start on a panel do not move the camera.

In a match, drag a finger anywhere that is not a control to look around: the
chase camera swings round the plane (right round to look back over the tail,
and up to look down on it) without steering. Let go and after a moment the
view eases back behind the tail. The camera goes with the plane through
loops and rolls (`ChaseCamera.roll_follow`), and shakes as the wing nears the
stall: that buffet is the warning. The lens widens and the camera
drops back steadily as the speed builds, from a slow climb-out to flat out.

**Taking off.** Throttle open and keep it straight: the engine swings the nose
left and the stick (or right pedal) has to hold it. From a fast walk push the
stick forward to lift the tail, run on the main wheels with the nose level,
and at the speed the HUD gives ease back and let it fly off. Hauling it off
early gets a stall a few metres up.

**Landing.** Wheels down (the flaps come with them), about 1.3 times the
stalling speed, a little power, a shallow descent. Over the runway close the
throttle and ease the stick back to hold it just off the ground until it
stops flying and sits down. Flown onto the ground fast it bounces; pushed on
nose-first it stands on its propeller. Nothing flares it for you.

On the ground the stick's sideways travel is the rudder bar: it steers.
The pilot's hands and feet do there what a thumb cannot feel to do. His
hands hold the wings level against the engine's torque and the lean of a
turn (`FlightPilot.hold_wings_level`), and his feet turn as tightly as the
undercarriage will take and no tighter: the rudder is eased as the swing
builds toward the side load that would lift the inside wheel, and when that
wheel goes light (`FlightPilot.feet_within_the_wheels`). So the stick hard
over at any speed on the runway turns the plane without putting a wingtip
down. Rudder against a swing is never held back, and none of this is there
once the wheels are off the ground.

A closed throttle on the ground is also the wheel brakes. The GEAR lever is
locked while the plane is standing on its wheels, and the guns are safe on the
ground.

## Folder structure

```
dogfight/
├─ project.godot                 1920x1080, canvas_items + expand, sensor landscape, Mobile renderer
├─ assets/models/                hurricane.glb, spitfire.glb, mustang.glb (generated by tools/blender/warbirds.py)
├─ assets/audio/                 engine loops, gun shots, whiz, impacts ... (cut by tools/audio/)
├─ resources/
│  ├─ cards/*.tres               15 items: 3 guns and 12 components (ComponentCard)
│  ├─ planes/*.tres              Hurricane (free), Spitfire (1,500 gold), P-51 Mustang (4,000 gold)
│  └─ env/arena_environment.tres sky, ambient, fog, glow, tonemap
├─ scenes/
│  ├─ menu/MainMenu.tscn         Hangar
│  ├─ lobby/MatchLobby.tscn
│  ├─ arena/DogfightArena5v5.tscn
│  ├─ actors/PlaneActor.tscn
│  ├─ camera/ChaseCamera.tscn
│  └─ hud/HUD.tscn
├─ scripts/
│  ├─ core/      teams.gd, ballistics.gd, game_session.gd (autoload GameSession)
│  ├─ data/      component_card.gd, plane_data.gd, plane_stats.gd,
│  │             plane_mounts.gd, game_catalog.gd
│  ├─ meta/      player_profile.gd (autoload Profile)
│  ├─ actors/    plane_actor.gd, plane_input.gd, plane_visual.gd, plane_hitboxes.gd
│  ├─ combat/    bullet_system.gd, midair_collisions.gd
│  ├─ audio/     plane_audio.gd, battle_audio.gd, sound_tools.gd
│  ├─ camera/    chase_camera.gd
│  ├─ control/   player_controller.gd, squad_ai.gd, squad_blackboard.gd
│  ├─ match/     match_manager_5v5.gd, pilot_slot.gd, dogfight_arena.gd
│  ├─ world/     arena_builder.gd, airfield.gd, ground_map.gd
│  ├─ fx/        toon_materials.gd, explosion_fx.gd, debris.gd
│  ├─ ui/        hud.gd, hud_world_overlay.gd, radar.gd, touch_flight_stick.gd,
│  │             throttle_lever.gd, action_button.gd, ui_style.gd
│  └─ menu/      main_menu.gd, card_view.gd, match_lobby.gd
├─ shaders/      toon_plane.gdshader, toon_plane_damage.gdshader, bullet_trail.gdshader, bullet_hole.gdshader, coast_terrain.gdshader, coast_water.gdshader, coast_foliage.gdshader, cloud.gdshader
├─ tests/        headless test scenes (see "Tests")
└─ tools/        run_tests.sh, screenshot + model preview scenes, blender/
```

## Scene trees

```
MainMenu (Node3D)                         main_menu.gd
├─ WorldEnvironment, Sun, RimLight
├─ Stage ─ Turntable                      PlaneVisual preview is built here
├─ Camera3D
└─ UI (CanvasLayer) ─ Root (Control)
   ├─ CoinPanel                           gold, the insurance switch
   ├─ PlanePanel                          name, stats, < SELECT >
   ├─ LoadoutPanel ─ Slots                9 mount tiles: 4 gun stations, propeller, engine,
   │                                      wingtips, armour, undercarriage
   ├─ CollectionPanel ─ Scroll ─ Grid     one CardView per item
   ├─ DetailPanel                         selected item: this Mark and the next
   └─ ActionRow                           UPGRADE, EQUIP, BATTLE

MatchLobby (Control)                      match_lobby.gd
├─ Background, Title
├─ Teams ─ BluePanel/BlueList, VsLabel, RedPanel/RedList
├─ Status
└─ CancelButton

DogfightArena5v5 (Node3D)                 dogfight_arena.gd (wires camera + HUD)
├─ WorldEnvironment                       resources/env/arena_environment.tres
├─ Sun (DirectionalLight3D)               warm key light, 2-split shadows
├─ RimLight (DirectionalLight3D)          cool back light, no shadows
├─ World                                  arena_builder.gd: the coast (land, sea, trees, villages,
│  │                                      clouds) and an Airfield (airfield.gd) for each team
│  └─ Sea (StaticBody3D, WorldBoundary)
├─ SpawnPoints ─ Blue/Spawn1..5, Red/Spawn1..5   air starts, only used with GameSession.ground_start off
├─ Planes                                 every PlaneActor (the spawner's spawn path)
├─ PlaneSpawner (MultiplayerSpawner)
├─ BulletSystem                           bullet_system.gd
├─ MidairCollisions                       midair_collisions.gd
├─ BattleAudio                            battle_audio.gd: wind, near misses, impacts, collisions
├─ Controllers                            one PlayerController or SquadAIController per seat
├─ MatchManager                           match_manager_5v5.gd
├─ ChaseCamera (instance)
└─ HUD (instance)

PlaneActor (CharacterBody3D)              plane_actor.gd  (layer "planes", collides with "world")
├─ CollisionShape3D                       generous hit sphere
├─ VisualRoot                             plane_visual.gd: the Blender model's pieces, prop, smoke, debris
├─ PlaneInput                             plane_input.gd: the only thing a pilot writes to
│  └─ InputSync (MultiplayerSynchronizer) steer + firing, authority = owning peer
└─ StateSync (MultiplayerSynchronizer)    transform, speed, hp, flags, identity; authority = server

ChaseCamera (Node3D)                      chase_camera.gd
└─ Pivot ─ SpringArm3D ─ Camera3D

HUD (CanvasLayer)                         hud.gd
└─ Root (Control)
   ├─ WorldOverlay                        hud_world_overlay.gd: diamonds, threat arrows, gun pipper
   ├─ TopLeft                             level badge, XP bar, speed/altitude/fuel
   ├─ DamageDiagram                       damage_diagram.gd: state of every part
   ├─ ScoreBar                            BLUE | 5v5 + clock | RED
   ├─ KillFeed
   ├─ Radar                               radar.gd
   ├─ CenterMessage, SubMessage
   ├─ Joystick                            touch_flight_stick.gd
   ├─ FireButton, RollButton              action_button.gd
   ├─ EngineButton, GearButton            action_button.gd (with an on/off lamp)
   ├─ ThrottleLever                       throttle_lever.gd
   └─ Results                             victory/defeat, rewards, back to Hangar
```

## How the pieces fit

- **A plane does not know who flies it.** `PlaneActor` reads its `PlaneInput`
  child each physics tick. `PlayerController` and `SquadAIController` only write
  to that node, so the match manager can swap a seat between a human and a bot
  (`assign_human` / `release_to_ai`) without touching the plane.
- **Input goes through actions.** The touch stick and buttons press the same
  Input actions the keyboard does; `PlayerController` never references a widget.
- **The plane is a model made of parts.** `PlaneVisual` loads the plane's own
  Blender model (`PlaneData.model`: `assets/models/hurricane.glb`,
  `spitfire.glb` or `mustang.glb`), which is a tree of 19 separate
  pieces: fuselage, engine, propeller, canopy, two inner wing panels, two
  wingtips, flaps, ailerons, tail, stabilisers, elevators, fin and rudder.
  Control surfaces are cut out of the wing and tail and hinged; they follow the
  stick. Each model is the real aeroplane's size, in metres, with its origin
  at the centre of gravity, and is shown at that size (see The plane models).
  The game measures the wheels, the propeller, the wingtips and the hit boxes
  from it, so how a plane stands and what it can touch the ground with are
  the model's, and so the real aeroplane's.
- **There is no health.** `PlaneActor` has fifteen damageable parts and nothing
  else. Each part does a job and does it worse as it is damaged; a destroyed
  part comes off the model as falling debris, together with whatever is
  attached to it (a wing takes its tip, flap and aileron; the tail takes the
  fin, rudder and elevators).

  | Part | What damage does | When it is gone |
  | --- | --- | --- |
  | Inner wing panel | makes less lift: the plane rolls toward it and needs stick held against it | half the plane's lift gone with nothing to balance the other half: it rolls over and over and cannot be flown; its gun goes too |
  | Wingtip | a little less lift on that side | rolls toward it (it can be held level with the stick), stalls sooner, pulls less g; its aileron goes with it |
  | Aileron | weaker roll | rolls on the one that is left, or not at all |
  | Flap | less extra lift | with the flaps down the plane rolls toward the side with none |
  | Tail | less grip: sloppier in pitch | nothing holds the nose into the airflow: it tucks under and tumbles |
  | Fin / rudder | weaker in yaw; the pilot's feet have less to work with | the nose swings and skids |
  | Elevator | weaker pitch | almost no pitch control if both go |
  | Engine | less power | dead: on fire, a glider with a windmilling propeller |
  | Fuselage | stretched cables (weaker controls), drag, leaks fuel | tank ruptured: engine stops when the fuel is gone |

  None of that is scripted. `PlaneActor._apply_condition()` only tells the
  flight model what is left of each surface; a missing panel makes no lift, a
  dead elevator moves no air, and what the plane then does follows from the
  forces. The pilot keeps whatever control the remaining parts give, all the
  way to the ground.
- **Flight is a rigid body in real air** (`FlightDynamics`, one per plane).
  Real mass and inertia, real gravity (9.81 m/s^2), and the real aeroplanes'
  figures: weight, wing area, span, engine power, drag. Every tick each
  surface (four wing panels, two tailplane halves with their elevators, the
  fin and rudder, the fuselage) works out the air it meets, including what the
  plane's own rotation adds, and from that its own angle of attack, lift and
  drag. The sum of those forces, where they act, moves and turns the plane.
  There is no "stall rule", no "spin mode", no turn rate and no speed cap:
  - *Lift* goes with the square of airspeed and with angle of attack, up to
    the stalling angle. Past it the air lets go: lift collapses, drag soars.
    That is a matter of angle, not speed. The wing gives the most at about
    15 degrees and lets go near 20; the player's stick (like the bots')
    takes it to the first and stops, unless a rudder pedal is held as well.
    Easing the stick forward is what cures a stall.
  - *Spins.* A wing that stalls before the other drops, and with yaw the
    plane autorotates. Held in with stick and rudder it stays in; closing the
    throttle, stick forward and rudder against the turn brings it out.
    Under power a spin goes flat and is much slower to leave.
  - *Loops and rolls* are just more of the same: there is no pitch limit and
    no bank limit. The tips are twisted nose-down (washout) so the wing stalls
    from the root outward and the ailerons keep working into the stall.
  - *The tail* keeps the nose pointing into the airflow. The wing alone is
    unstable and its cambered section tries to tuck the nose under; shoot the
    tail off and that is what happens.
  - *The propeller* is modelled too. Thrust is power over speed, from a
    static limit, so there is far more push slow than fast. Torque rolls the
    airframe against the propeller; the slipstream's spiral and P-factor
    swing the nose; a spinning propeller precesses when it is tilted. All of
    it pulls left (the engines turn clockwise seen from the cockpit), most at
    low speed and high power: on the take-off run, at the top of a loop, when
    the throttle is slammed open.
  - *Trim.* The pilot trims the plane as real ones were trimmed
    (`FlightDynamics.update_trim`): the elevator tab follows the speed
    quickly, so stick centred is 1 g; the aileron and rudder tabs follow
    slowly, so torque is felt on every change of speed or power until they
    catch up. Nobody trims for speeds near the stall: slower than 1.3 times
    the stalling speed the nose has to be held up, and letting go lets it
    drop and the speed come back.
  - *Controls stiffen with speed*, and the pilot cannot hold the stick back
    against more than about 6 to 8 g, or forward past -2 to -3.
  - *Ground effect*: within 10 m of an airfield, more lift and less drag.
  - *The air* is the standard atmosphere (`FlightDynamics.altitude`):
    it cools 6.5 degrees per kilometre and thins as it does, to 82% of its
    sea-level density at 2,000 m and 54% at 6,000 m. Every force the air
    makes goes with that density. So the higher a plane is, the faster it
    has to go to stay up (a Spitfire stalls at 83 mph true at sea level and
    113 at 6,000 m), the wider it turns and the lazier its controls are at
    the same true speed, and the less drag it has. The airspeed indicator
    (the HUD's speed, `PlaneActor.indicated_speed`) shows what the wings
    feel, not how fast the ground goes by, so the stall and take-off numbers
    on it are the same at any height. Once the two differ the HUD gives the
    true speed beside it; that is the figure the books quote. Speeds are
    shown in miles an hour, as on these aeroplanes' own instruments.
  - *The engine breathes that air too.* A supercharger holds the boost up
    to the engine's critical altitude: 6,400 m (21,000 ft) for the
    Hurricane's Merlin XX, 6,100 m (20,000 ft) for the Spitfire's Merlin 45,
    7,600 m (25,000 ft) for the Mustang's Packard Merlin. Holding it costs
    power, more the higher it has to be held, so the engine gives a
    steadily smaller share on the way up (`altitude_power`: 90%, 76% and
    74% of sea-level power at those heights, about what the real engines
    gave). Thin air takes drag away faster than that takes power away, so
    each plane keeps getting faster up to its critical altitude. Above it
    the boost itself falls with the air and the plane gets slower again.
    The propeller also has less air to bite, so static thrust falls a
    little with height. Engines with a two-stage supercharger (Merlin 61,
    Griffon 65) hold on 1,000 to 1,500 m higher still.
  - *Exhaust thrust.* The backward-pointing exhaust stacks are a small jet
    (`EXHAUST_THRUST`): nothing much at take-off, about a tenth of the push
    at top speed.
  - *Compressibility.* Sound is slower in the cold (340 m/s at the sea,
    310 at 7,600 m). Past Mach 0.68, which is a steep dive from height and
    nothing else, drag climbs steeply and the controls lose their grip.

  What comes out, measured from the model rather than typed in
  (`PlaneData._finish_stats`, shown in the hangar), beside the real
  aeroplane's published figures:

  | | Top speed at sea level | Top speed at best height | Climb | Stalls at (indicated) | Weight | Power |
  | --- | --- | --- | --- | --- | --- | --- |
  | Hurricane II | 283 mph (real: about 283) | 340 mph at 6,400 m (real: 340 at 21,000 ft) | 13.9 m/s (real: 14.1) | 86 mph | 3,260 kg | 1,280 hp |
  | Spitfire V | 332 mph (real: about 332 on emergency boost, 298 on normal) | 371 mph at 6,100 m (real: 367 to 375 at 20,000 ft) | 19.1 m/s (real: 14.5 on normal boost) | 83 mph | 2,960 kg | 1,470 hp |
  | Mustang (P-51D) | 375 mph (real: 375 at war emergency power) | 437 mph at 7,600 m (real: 437 at 25,000 ft) | 16.0 m/s (real: 16.3 to 17.6) | 104 mph | 4,130 kg | 1,720 hp |

  Each plane's drag was set so the model does the real sea-level speed on
  the real power, and its `altitude_power` so it does the real speed at the
  real height; the drag coefficients that took (0.0237, 0.0182, 0.0153) are
  close to the ones measured for the real aeroplanes. The climb rates were
  not fitted: they are what the model then gives. The Spitfire and Hurricane
  sea-level speeds come from flight-simulator reference tables rather than
  from an original trial report, so treat those two as good to a few mph.
  Engines here always give their emergency rating at full throttle, with no
  time limit and no overheating.

  A Spitfire rolls at about 100 degrees a second, loops from top speed in 19
  seconds going 500 m up and over, glides about 1 in 9 with a dead engine and
  a windmilling propeller, and holds a 60-degree bank at 2 g, turning at
  g x tan(bank) / speed like anything else.

  The model is simple where being exact would not show: four wing panels
  rather than forty, thrust from a formula rather than blade elements, the
  troposphere only, no wind or turbulence, and an airfield that is perfectly
  flat. `tools/flight_lab.gd` flies the model on its own, in the air and on
  the ground, and prints what it does.
  The Spitfire's best sustained turn at sea level comes out at a circle in
  about 20 seconds (3.5 g at 237 mph), the Hurricane's 22 and the Mustang's
  19; the real ones took roughly 19, 20 and 22. The flaps are landing flaps
  and move only with the undercarriage: they do not drop in turns.
- **A plane is only lost when it hits something:** the sea, the land,
  or another aircraft hard enough. (A bot whose plane can no longer fly does
  not ride it down: after 4 to 9 seconds, sooner if it is burning, the pilot
  bails out and the plane is lost there and then. A human pilot is never
  thrown out; gliding a wreck home is their business.) Whoever crippled it is credited (the enemy
  who destroyed a part, else the last enemy to hit it within 45 s).
- **Bullets are data.** `BulletSystem` simulates every bullet in arrays and
  draws them all with one MultiMesh. Each tick a bullet's velocity is updated
  for gravity and drag (`Ballistics.step`) and its path for that tick is tested
  against the world (one physics ray) and against each enemy plane. Drag goes
  with the density of the air the bullet is in, so high up bullets keep their
  speed longer and drop less over the same distance.
- **Hits follow the bullet's path.** `PlaneHitboxes` is read from the model:
  one or more boxes per piece (long pieces are measured in slices, and a
  panel's box is cut short where its control surface begins), padded by 0.3 m
  for bullets. A path through none of them that still passes within 0.55 m
  is a graze, given to the one part it came to first: the planes are their
  real size, and a real fighter is a small target for a thumb. The bullet's
  path, relative to the target's own motion, is traced through them. The
  first box entered is the part that is hit, and the bullet carries on with
  reduced energy into whatever lies behind. A path that clears every box by
  more than the graze misses, and a part that has been shot off is no longer
  there to hit. Bullets are never tested against the shooter's own team.
- **Impact energy.** Damage scales with the square of the closing speed between
  bullet and target (clamped to 0.45x-1.5x), so head-on passes hit harder than
  tail chases and long-range hits are softer.
- **Unassisted gunnery.** The player gets a fixed gun pipper showing where
  bullets really are at convergence range (drop included) and nothing else:
  no lead-prediction reticle, and `PlayerController.aim_assist_enabled` is off
  by default. `Ballistics.lead_point` solves the same model the bullets fly
  (inherited plane velocity, drag, drop) and is what the bots aim with.
- **Planes can hit each other.** `MidairCollisions` tests nearby planes part
  against part with the true-size boxes, so a wingtip can clip a tail and
  nothing else is touched. Each part involved takes damage in proportion to
  the closing speed (about one bullet's worth at 10 m/s), both planes are
  shoved apart, and above 95 m/s a blow to the fuselage or engine destroys the
  plane outright. Team-mates can collide too. Bots steer away from anything
  they are about to hit.
- **The sortie** (`MatchManager5v5`). Five a side, one life each. A plane
  that is lost is gone and its pilot with it: nobody comes back, and the
  score bar counts the pilots each side has left. A plane cannot be hurt
  until it has left the ground (or 25 s have passed).
  - *The bounty.* Each kill the player makes is worth more than the one
    before: 100, 120, 150, 200, then 300 gold (`KILL_VALUE`,
    `KILL_MULTIPLIERS`), 870 for all five of the enemy. The HUD shows what
    is being carried and what the next kill would add. It is not the
    player's yet.
  - *Getting it home.* Stopped on their own airfield, the pilot gets a
    menu (`Hud._build_service_panel`): **REPAIR**, **REFUEL**, **BOTH**, or
    **CASH OUT**. Repairs cost 45 gold for each part's worth of damage, each
    collapsed leg, a smashed propeller and a plane on its belly; a full
    tank costs 60, less if it is part full. The bill is taken from the
    bounty first and the pilot's own gold after that, and work that cannot
    be paid for is not done. The ground crew then do what was ordered and
    no more, and the pilot can go up again. Cashing out banks the bounty
    and ends the sortie. Killing every enemy does not end it: the bounty
    still has to be landed.
  - *Fuel.* The player's engine burns it: a full tank is seven minutes at
    full throttle (`FUEL_ENDURANCE`), far longer throttled back, and a holed
    tank loses it faster. Out of fuel is a dead-stick landing. That, not a
    clock, is what limits a sortie.
  - *Killed.* The bounty is lost. So is the plane, which has to be bought
    again at full price, unless the sortie was insured. Whatever was fitted
    to it is kept. The Hurricane costs nothing, so there is always one to
    fly.
  - *Insurance* is a switch in the hangar: 15% of the plane's price, paid
    at the start of every sortie whether or not the plane comes back
    (`Profile.pay_insurance`). A pilot who cannot pay it flies uninsured.
  - A battle with no human in it ends when one side has nobody left, or
    after ten minutes.
- **Ground handling** (`PlaneActor`, `Airfield`). Each team has an airfield
  on a levelled stretch of the countryside, 2.3 km from the middle of the
  arena, laid out as a wartime RAF fighter station to real scale: a main
  runway of 1,600 yards (1,463 m) pointing at the middle, and two of 1,100
  yards (1,006 m) crossing it to make the classic triangle, all 50 yards
  (45.7 m) wide. The ground is dead level for 130 m either side of every
  runway and for 400 m off each end of the main one (grass, for landing
  short or running long), and kept level along that line for a kilometre
  more, so no approach is into a hillside. Beyond the level ground the land
  is solid and unforgiving. The battle area is 3.2 km in radius with a 9 km
  ceiling (no one gets near it in a short sortie: it is ten minutes' climb to
  where these planes are fastest). Everyone starts parked on their own
  runway: engine off, wheels down, throttle closed. Brakes have less to
  grip on grass than on the runway (`GRASS_BRAKE_SHARE`).
  - *Starting up.* The starter takes about two seconds before the engine
    answers the throttle. A dead engine will not start.
  - *On the ground it is the same rigid body*, standing on what touches
    (`FlightDynamics._ground_loads`). Each wheel is a sprung, damped leg
    with a tyre: it carries what the plane puts on it, rolls freely along
    its own line, grips sideways until it slides, and brakes. A main leg is
    squashed 14 cm by the standing plane and, like the air spring an oleo
    is, pushes back two and a half times harder for every centimetre past
    that, so the plane leans only a few degrees in a turn. The ground pushes
    on the squashed tyre, where the ground is. The tail wheel turns with the
    rudder bar, 24 degrees at a taxi and less the faster the plane rolls (it
    is steered through springs). The belly, the tip of the propeller, the
    wingtips and the tail are hard points that take over when a leg is up,
    gone, or the plane has gone over; once the propeller is broken the nose
    rests on the cowling instead. Nothing holds the heading, the attitude or
    the height: parked, it sits tail-down at about 12 degrees because that
    is where three springs balance its weight.
  - *How easily it goes over* is the real aeroplane's geometry. The wheels
    are where the model has them: the Spitfire's 1.73 m apart, the
    Hurricane's 2.36 m, the Mustang's 3.61 m, each under a centre of gravity
    about 1.8 m up. The inside wheel lifts at a side load of half the track
    over that height: about 0.49 g for the Spitfire, 0.63 g for the Hurricane
    and 0.98 g for the Mustang, so the Mustang slides before it will tip and
    the narrow Spitfire is the one to watch. A wingtip reaches the ground at
    18 to 24 degrees of lean. The propeller clears the ground by about a
    quarter of a metre with the tail up.
  - *The take-off run.* Real propeller thrust against real drag and rolling
    resistance (less on the runway than on the grass). The engine's torque
    presses the left wheel harder and the slipstream swings the tail, so it
    goes left unless held; the rudder does more as the speed comes up. Stick
    forward and the tailplane lifts the tail off at around 25 m/s; the wings
    then meet the air at a few degrees and the plane accelerates on its main
    wheels. Eased back at flying speed it leaves when the wings carry it. A
    Spitfire is off in about 11 seconds and 230 m. Left tail-down it leaves
    earlier, slower and right on the stall. Too much forward stick puts the
    propeller into the runway.
  - *There is no moment of "lift-off"* in the code: the wheels just carry
    less and less. `TestGroundOps` measures the largest tick-to-tick change
    in pitch, climb rate, acceleration and height through a take-off.
  - *Undercarriage.* Wheels down is drag, and the landing flaps are on the
    same lever: down with the wheels (more lift, more drag, a lower stalling
    speed) and up with them, whatever the speed. Raising them takes that
    lift away, so the plane sags a little as it cleans up. It takes two
    seconds to travel, and goes with the wing it is bolted to.
  - *Throttle.* It sets the power, and so the thrust. Closed, the plane is a
    glider. An approach is flown on the throttle: about 1.3 times the
    stalling speed, a little power, three degrees down.
  - *Close to the ground.* Ground effect helps. Nothing else does: there is
    no automatic flare. Checking the descent is the pilot's job.
  - *Landing.* What a landing does to the aeroplane is whatever the contact
    does, piece by piece, instead of blowing it up
    (`PlaneActor._read_the_ground`). A wheel that meets the ground at up to
    6 m/s is a landing, though anything firm bounces it back into the air on
    its springs, and a bounce at low speed comes down harder than the first
    arrival. 6 to 9.5 m/s strains the wings and fuselage. Above 9.5 that leg
    collapses; the plane drops onto the wingtip on that side and swings
    round it. Arriving on the belly (wheels up, or both legs gone) it slides
    to a stop, bending the propeller if the nose gets down to the ground.
    The nose touching at all smashes the propeller, which is what happens to
    a plane that is braked too hard with the tail up, or pushed onto the
    runway nose-first. A wingtip dragged along the ground is scraped; put
    down hard or at a steep bank it is torn off. Landing across the runway's
    line, or letting it swing, puts the tyres sideways-on: it ground-loops,
    and can go onto a wingtip. Only arriving at more than 22 m/s, more than
    30 degrees nose-down, or past 70 degrees of bank destroys the plane
    outright.
  - *Stopping and repairs.* Throttle closed is the wheel brakes (a quarter
    of a g at most, as drum brakes of the time gave): about 14 seconds and
    230 m from 30 m/s. Stopped on its own airfield with the
    engine at idle, a plane can be refuelled and repaired, including new legs,
    a new propeller and replacement parts; a wreck lying on its belly is
    jacked back onto its wheels first. The player pays for this (see The
    sortie); a fire is put out for nothing. Stopped on the enemy's airfield, or
    run off the airfield's level ground into the rough, it is lost.
  - *Bots* start up in turn from the front of the line and fly the same
    take-off a player has to: steer down their own lane with rudder, stick
    forward to get the tail up, ease back at flying speed, then raise the
    wheels and climb out before joining the fight. They do not attack planes on the ground. **They do not yet
    come home to repair**; only a human pilot does that.
- **HUD.** No health bars anywhere. The player has a diagram of their own
  plane showing each part's state (missing parts are drawn as outlines), a
  fuel readout once the tank is holed, and a message when a part is hit. The
  current target shows its name, range and what is already wrong with it.
- **Bots** fly the same aeroplane with the same stick. `FlightPilot` is their
  hands (and the hands that turn a player back into the battle area): it
  thinks in lift ("to bend my path that way and not fall, the wings must pull
  this hard in this direction"), rolls until the top of the plane faces that
  way, and pulls what is lined up, backing off near the stalling angle. For
  gunnery it aims the nose rather than the flight path and nudges it across
  with rudder. Bots can stall and spin, and have a recovery drill for it.
  They are tuned to fly like people: they aim at where the target was a
  reaction time ago (so jinking throws them off), their aim wanders, they
  misjudge lead, their stick movement is rate-limited, they pull between 3.4
  and 6.5 g depending on skill, and they fire in bursts. In bots-only test
  matches about 5% of their shots land. They pick targets by score (range,
  angle off the nose, coming up behind rather than meeting head-on, damage)
  with a penalty for targets team-mates already claimed, approach in personal
  lanes, push apart when close, will not dive lower than the room under them
  allows, pull up for the ground (measured from the land under and ahead of
  them, not from the sea), turn for cliffs and hangars, turn back at the edge, and
  break when shot from behind.

## Progression

Everything a player collects is a real weapon or a real aircraft component,
it is bolted to a particular place on the aeroplane, and it shows there.

- **Mounts.** Every plane has nine: four wing gun stations (left and right,
  inner and outer), propeller, engine, wingtips, armour and undercarriage
  (`PlaneMounts.MOUNT_*`). All of them are open on every plane.
- **Items** (`ComponentCard`, `resources/cards/`):

  | Mount | Items |
  | --- | --- |
  | Gun stations | Browning .303 (light, fast-firing), Browning M2 .50 (longer range, harder hitting), Hispano 20 mm (slow, heavy, devastating) |
  | Propeller | De Havilland 3-blade (standard), Rotol 4-blade (more pull at low speed and more power absorbed, for a little top speed) |
  | Engine | Merlin III (standard), Merlin 61 (more power and speed), Griffon 65 (more of both, heavier to roll) |
  | Wingtips | Standard, Clipped (shorter span: fast roll, a little faster, higher take-off and stalling speed), Extended (the reverse) |
  | Armour | none, Seat armour, Armoured cockpit and self-sealing tanks |
  | Undercarriage | Standard, Reinforced (stands a harder landing) |

- **One gun fitted is one gun.** Each gun station holds one gun or nothing.
  The plane shows, sounds like and fires exactly the guns that are fitted,
  each from its own muzzle at its own rate, damage, muzzle velocity and
  range. Stations can hold different guns. A wing that is shot off takes its
  guns with it.
- **It all shows on the model.** The model carries every alternative and
  `PlaneVisual.build()` strips out what is not fitted: the right kind of
  barrel at each station, three or four propeller blades, the chin intake
  and cowl bulges of the bigger engines, armour plate behind the seat and an
  armoured windscreen, clipped or extended wingtips (which also change the
  wing's hit boxes), and the fatter reinforced undercarriage (which changes
  how high the plane stands).
- **What an item does is physical.** Each one changes the aeroplane, and the
  flight model does the rest (`PlaneData._finish_stats`): weight is mass,
  engine power is watts, a propeller's bite is static thrust, wingtips are
  span and area, "top speed" is less drag, "wing lift" is a higher maximum
  lift coefficient, "roll" is aileron power. The hangar shows the results
  measured from the model: top speed, stalling speed, climb, weight, power.
- **Weight is the price.** Guns, armour and bigger engines add weight
  (`ComponentCard.weight`). Weight raises the stalling speed and the wing
  loading, lengthens the take-off run, and comes straight off the climb.
  Four cannon plus full armour is 23% heavier than a stock plane. Several
  components also carry their own drawback (the four-blade propeller costs
  top speed, clipped wings cost span).
- **Buying.** Everything is bought with gold in the hangar. An item is
  bought one unit at a time: one gun, one propeller. You can fit as many
  guns of a type as you have, up to four, and nobody can own more of an
  item than could be fitted. Common items cost 150 gold, rare 450, epic
  1,100 (`ComponentCard.PRICE_BY_RARITY`).
- **Upgrading.** Gold raises an item's Mark, Mk I to Mk V, as real weapons
  and engines were developed: 60, 250, 800 and 2,500 gold for a common item,
  twice that for a rare one and three times for an epic. Each Mark improves
  what the item is good at by 4% (16% at Mk V); its weight and drawbacks
  stay the same.
- **Planes.** The Hurricane is issued free. The Spitfire costs 1,500 gold
  and the Mustang 4,000 (`PlaneData.price`), and a plane lost on an
  uninsured sortie costs the same again.
- **No experience, no levels.** A pilot has what they have paid for.
- `PlaneData.build_stats()` = base stats x what is fitted, producing the
  `PlaneStats` a plane flies with (and the list of fittings `PlaneVisual`
  shows). An item in the wrong kind of mount is left off.
- `Profile` (autoload) holds gold, the planes bought, each item's units and
  Mark, what is fitted to each mount and whether sorties are insured, and
  saves them to `user://squadron_profile.json`. An older save keeps its
  coins as gold and any plane its experience had unlocked. Local only:
  there is no store and no real money yet. A new pilot starts with 500
  gold, a Hurricane, two .303s and the standard parts.
- Bots keep clear of the hills, look along the curve of their turn for
  obstacles, and are given two to four guns of one kind and, more often in the
  better planes, better components. They fly the player's plane or the one
  either side of it in the line-up. They burn no fuel and do not land, so
  they neither run dry nor cash out.
- **Gone:** the arcade gadgets (nitro, smoke screen, squad repair) and the
  stat-boost cards. Nothing a player owns is anything but a weapon or a part.

All tuning numbers (costs, XP, damage, turn rates) are first-pass values.

## Look

- `shaders/toon_plane.gdshader`: banded diffuse, hard specular blob, light-aware
  rim plus a small ambient rim. `ToonMaterials.standard_toon()` is the
  StandardMaterial3D equivalent (toon diffuse/specular + built-in rim) for
  meshes that need textures.
- `shaders/cloud.gdshader` is fragment-only and reads no screen or depth
  textures; nor does anything else here.
- Lighting: warm golden `Sun` with shadows, cool unshadowed `RimLight` from
  the opposite side, an azure sky for ambient, light-blue distance fog, mild
  glow, +20% saturation.
- Clouds are primitive meshes built in code (`arena_builder.gd`). Planes are
  the Blender model described below.

### The countryside

The battlefield is a stretch of chalk coast: rolling green hills, a
patchwork of fields, sheer white cliffs and a turquoise sea, with woods,
boulders and villages. `docs/coast_cliffs.png`, `docs/coast_fields.png`.

- **It is made in Blender by a script** (`tools/blender/coast_world.py`,
  Blender 4.x; run it and it rewrites `assets/models/coast/`). The land is
  one grid, 21 km across so that it has no edge to see, meshed at 25 m
  through the middle 8 km and more coarsely beyond. One column of the grid
  is laid along the wandering coast and the next 4 m out from it at sea
  level, which is what makes the cliffs sheer. The airfields are levelled
  into it and their runways laid on top. It also makes the tree, the
  boulder and the cottage, and writes the land's heights out as numbers.
- **Vertex colours say what the ground is:** R grass, G wheat, B chalk, and
  A farmland (where fields may be). `shaders/coast_terrain.gdshader` blends
  them and adds what vertex colours cannot: it draws every field itself,
  from the same grid and the same hash the Blender script used, so each has
  a crisp outline and a hedge whatever the mesh's resolution; wheat, plough
  and pasture in different fields; furrows; two-tone turf; beds and streaks
  in the chalk, which it finds from the slope of the surface itself. No
  textures.
- **The sea knows its own depth.** `ArenaBuilder._build_sea` builds the sea
  as a mesh that follows the coast and stores at each vertex how deep the
  water is there and how far it is from the cliffs.
  `shaders/coast_water.gdshader` colours it from that (turquoise shallows
  over the pale sea bed, deepening to blue) and breaks foam at the foot of
  the cliffs and in lines rolling in. The usual way, reading the depth
  buffer, would make the whole sea a transparent surface, which is costly
  on a phone; this one stays opaque.
- **Trees, boulders and cottages** are scattered at load from one seed
  (`ArenaBuilder._scatter_countryside`): about 2,500 trees, thick in the
  woods and thin elsewhere, never in a field, on steep ground, at the
  cliff's edge, near a runway or under an approach; boulders on the rough
  ground and the cliff tops; villages of a few cottages on level ground.
  They are drawn as MultiMeshes cut into 1.2 km squares, so squares out of
  view or too far off are not drawn. `shaders/coast_foliage.gdshader` shades
  the trees softly and lets the sun glow warmly through the canopy when it
  is behind them. **They are scenery: nothing collides with them.**
- **`GroundMap`** (`scripts/world/ground_map.gd`) is how the game asks how
  high the land is: the bots keep their height above the ground under and
  ahead of them, the HUD's approach guidance measures from it, and the
  scatter stands things on it. It reads the numbers the Blender script
  wrote, so it agrees with the mesh. The land and the airfields' level
  ground have triangle-mesh colliders; a plane that touches the land
  anywhere but its airfield's level ground is lost.

### What bullets leave behind

All of it is cosmetic and none of it uses a texture.

- **Smoke trails.** Every bullet draws a ribbon of grey smoke out behind it,
  from the muzzle to wherever it has got to. The ribbon stays where it is in
  the air when the bullet has gone, spreading (from 0.2 m to a couple of
  metres) and thinning for 1.6 s, the gun end first because it is the
  oldest. One stretched instance per bullet in a second MultiMesh
  (`BulletSystem._write_trails`, `shaders/bullet_trail.gdshader`); the
  shader makes it uneven along its length and fades it out close to the
  camera, so your own gun smoke streams past as haze rather than as bars
  across the screen.
- **Bullet holes.** A bullet that hits an aeroplane leaves a hole on the
  piece it hit, at the spot it went in. `BulletSystem` already knows the
  bullet's path as the plane saw it; `PlaneVisual.add_bullet_holes` follows
  that path through the actual triangles of the piece's mesh (the hit boxes
  are only boxes) and lays a small ragged-edged patch on the surface there:
  black hole, a ring of bare metal, a smudge of soot
  (`shaders/bullet_hole.gdshader`). Thin pieces (wings, tail, control
  surfaces) also get a larger hole where it came out; the fuselage and
  engine do not. A bullet that goes on through several pieces holes each.
  Cannon shells make bigger holes than rifle-calibre rounds. The holes are
  children of the piece, so they move with a control surface and leave with
  a wing that is shot off. Each piece keeps its latest 18. A repair on the
  airfield takes them away.
- **Marks in the ground.** A bullet into the land or an airfield leaves a
  scorched pock (the latest 160 are kept) and throws up dust; into the sea,
  a splash; into an aeroplane, a puff of paint and smoke.

### Damage you can see

`PlaneVisual._show_damage` tells every piece of the model how hurt its part
is, and the paint shows it (`shaders/toon_plane_damage.gdshader`, the toon
shader with damage added; planes still share materials, the damage is a
per-instance number):

- as a part is damaged, streaks of soot and oil spread back along it, with
  specks of bare metal where the paint has chipped off round them: a few
  streaks at first, about half the piece by the time it is done for;
- past about a third, thin skin starts to tear open in ragged holes you can
  see through, to the dark inside of the far skin;
- guns, wheels and armour bolted to a part get as dirty as it is;
- a part that has broken off leaves an open, dark stub, and the piece that
  falls away is as battered as it was;
- a damaged part trails thin grey smoke; a critical one, thick black smoke;
  a dead engine burns.

A repair cleans all of it off.

## Sound

- **Per-plane engines, per-gun guns.** Each `PlaneData` names its own engine
  loop (Hurricane and Spitfire a Merlin, Mustang a Packard Merlin) and each
  gun item names its own samples (.303 Browning, .50 Browning, 20 mm
  Hispano), so a plane sounds like whatever is fitted to it. `PlaneAudio`
  (one per plane) plays them.
- **Engine.** One seamless loop; its note follows the throttle and, less,
  the airspeed, and its level follows throttle and power. Starting up plays
  the starter turning and the engine catching, with the loop fading in under
  it. A damaged engine misfires, a dead one coughs, winds down and leaves
  only wind.
- **On the ground.** Wheels rumble with speed, tyres chirp on touchdown (metal
  scrapes instead on a belly landing), and the undercarriage whines and
  clunks home.
  Other planes are positional with Doppler, so a pass drops in pitch as it
  goes by; the player's own engine and guns are heard flat, from the cockpit.
- **Guns.** One short sample per round actually fired, chosen at random from
  that gun's three with a small pitch change, so bursts stay in step with the
  tracers and never sound looped.
- **Near misses.** `BulletSystem` reports any bullet (not the listener's own)
  that passes within 16 m without hitting; `BattleAudio` plays a crack-and-zip
  at the point it went by.
- **Also:** rounds striking your plane, a quiet tick when yours strike, parts
  tearing off, collisions, explosions, hitting the sea, fire, and wind that
  rises with speed. A limiter on the master bus stops a busy fight distorting.

Where the sounds come from: `assets/audio/*.wav` were made with ElevenLabs'
sound-effects model from descriptions of each real engine and weapon, then cut
by `tools/audio/process_sounds.py` (steadiest stretch crossfaded into a loop;
gunshots trimmed to their first transient and given more low end). They are
**generated, not recordings of the actual aircraft**, and none of it has been
judged by ear: `docs/sound_preview.mp3` plays every sound in turn for that.

## The plane models

`tools/blender/warbirds.py` is a Blender 4.x script that models all three
fighters and cuts each into the pieces the game breaks apart. It exports
`hurricane.glb`, `spitfire.glb` and `mustang.glb` into `assets/models/`:

```
blender --background --python tools/blender/warbirds.py -- assets/models hero=1
```

Each aeroplane is a table of numbers in `SPECS`, in metres, and the model's
origin is the aeroplane's centre of gravity. The script prints what it built:

| | Hurricane Mk II | Spitfire Mk V | P-51D Mustang |
| --- | --- | --- | --- |
| Span | 12.19 m (40 ft) | 11.23 m (36 ft 10 in) | 11.28 m (37 ft) |
| Length | 9.84 m | 9.12 m | 9.83 m |
| Wing | thick, straight centre section, tapered, rounded tips | ellipse | straight taper, square tips |
| Undercarriage track | 2.36 m, folds inward | 1.73 m, folds outward | 3.61 m, folds inward |
| Propeller | 3.43 m, three blades | 3.27 m, three blades | 3.40 m, four blades |
| Wheels below the centre of gravity | 1.88 m | 1.78 m | 1.85 m |
| Sits nose-up | 11.4 degrees | 12.0 degrees | 12.1 degrees |
| Tells | humped back, radiator bath under the centre | radiator under one wing, oil cooler under the other | bubble canopy, radiator scoop under the belly |

Span, length, track and propeller are the published figures and the models
match them to the centimetre (`TestAirframes` checks). Where the centre of
gravity is, how high it stands and the fuselage sections are worked out from
published drawings and dimensions, not taken from factory data, and the
shapes are simple: oval sections, plain planforms, the game's flat colours.
They are the right size and proportions, not scale replicas. (`PlaneData`
holds the weights, wing areas and engine powers the flight model uses.)

`hero=1` is the lighter in-game level of detail: 45 pieces, of which a plane
shows about 22 at a time. They include two undercarriage legs that fold
about their local forward axis (`PlaneData.gear_folds_inward` says which
way), a fixed tail wheel, and every alternative fitting
(`Gun<station>_<kind>` for each of four stations and three kinds,
`PropellerMesh4`, `EngineIntake`, `EngineBulges`, `ArmourSeat`,
`ArmourScreen`, `WingTip?_clipped`, `WingTipExt?`, `Gear?_heavy`); leave it
off for the smoother close-up version. The models face -Z.
Hinged pieces have their local X axis along the hinge line (local Y for the
rudder) with the origin on it. Surfaces are named `BodyPrimary`,
`WingAccent_TeamColor`, `CanopyGlass`, `MetalDark`, `PropellerWood`,
`PilotSkin` and `PilotLeather`; `PlaneVisual` swaps each for a toon material.
Node names are what tie a piece to a `PlaneActor.Part` (`PlaneVisual.PART_NODES`),
so a new model with the same node names drops straight in.

Preview one with `res://tools/ModelPreview.tscn` (`model=`; `explode=1` pulls
the pieces apart). `tools/blender/spitfire_stylized.py` is the earlier,
chunkier single model the generator grew from; the game no longer uses it.

## Android test build

```
GODOT=/path/to/godot ANDROID_HOME=/path/to/android-sdk tools/build_android.sh
```

Exports the "Android Preview" preset (`com.squadronskies.preview`, arm64-v8a +
armeabi-v7a, sensor landscape, no permissions) with the release template to
`build/SquadronSkies-preview.apk`. Pass `KEYSTORE`, `KS_ALIAS` and `KS_PASS` to
sign with a key you keep; otherwise a throwaway key is generated in `build/`
(git-ignored), and a build signed with a different key will not install over
it. This is a sideload build for testing, not a store build.

## Tests

```
GODOT=/path/to/godot tools/run_tests.sh            # add --strict to make typing warnings errors
```

| Test | What it checks |
| --- | --- |
| `TestHangar` | the hangar plane's propeller is stopped and stays stopped after a refit; touch gestures fed to the menu: one-finger drag orbits at the same distance and cannot go under the floor, spreading and pinching zoom between limits while the plane stays put on screen, two fingers slide it but not off the screen, a double tap resets; taking a gun off shows on the plane |
| `TestProgression` | there are no levels and every mount is open; prices of planes, items and upgrades; what each kill is worth; item tables (units, Marks), what each item does to the stats, weight and stalling speed, one gun fitted is one gun, mixed guns, buying items one at a time and no more than can be fitted, upgrading with gold, buying planes, insurance, losing a plane and buying it back with its fittings kept, loadout rules, **the model shows exactly what is fitted** (gun pieces counted, propeller, intake, armour, wingtips changing the hit boxes, bigger wheels), save/load including a save from before items were fittings (its coins become gold and the plane its experience had unlocked is kept), bullet drop and drag, less drag in thin air, lead solution checked against a simulated bullet at sea level and at 4,000 m |
| `TestFlight` | ten Spitfires each flown through one situation by a scripted hand: top speed, stalling speed and climb come out as real figures; hands off, a trimmed plane holds height at 1 g; flat out it holds the top speed for its height, which is faster than at sea level while the airspeed indicator reads lower; the air's density and the speed of sound follow the standard atmosphere; the engine holds full power to its critical altitude and loses it above, so there is a fastest height; the stalling speed is the same indicated and faster true; stick back takes it right round a loop; stick over rolls it right round at a fighter's rate; with the throttle closed and the stick held right back the wing is taken to the buffet and held there without letting go, the plane runs out of speed and its nose comes down by itself, and power flies it away; stick back with full rudder held on stalls it and it spins, going round and coming down fast, and stick forward with opposite rudder stops it; slamming the throttle open at low speed rolls and swings it left until trimmed out; a 60-degree bank held level is 2 g and turns at g x tan(bank) / speed without skidding; engine stopped, it glides; pushed to zero g it falls at 9.8 m/s^2 |
| `TestDamageModel` | every part has a hit box from the model; bullet paths through them; live bullets with drop, drag and pass-through; **each hit leaves its hole on the piece it struck** (one in a solid engine, in and out of thin skin, one on every piece a bullet passes through, none from a miss), the part is drawn as damaged as it is and a repair removes holes and damage; a round into the runway leaves a mark and one into the sea does not; every bullet draws a smoke trail that outlasts it and then clears; no health value exists; shot-off parts leave the model as debris and take their attachments; a lost wingtip rolls the plane toward it and can be held level with stick and rudder; a lost wing rolls it over and over whatever the pilot does; a lost tail leaves nothing holding the nose into the air; a plane flies and turns without its rudder; less wing pulls less g for the same speed and angle of attack; a damaged engine cannot hold top speed; with one flap gone, lowering the flaps rolls the plane; planes are only lost by hitting the surface, credited to whoever crippled them |
| `TestAudio` | every plane has its own engine loop and every kind of gun its own samples; the player's engine plays from the cockpit and the other nine in 3D; firing plays one of the fitted gun's samples; a bullet passing 6 m away is heard once and one 60 m away is not; the engine note rises in a dive; a dead engine falls silent and the fire is heard. It checks wiring, not how anything sounds |
| `TestGroundOps` | everyone starts parked on their own runway, standing on three wheels at rest; the guns and an open throttle do nothing with the engine off; the ENGINE and throttle keys work; left to itself the plane swings left under power; steered, with the tail lifted and the stick eased back at flying speed, it flies off after a believable length of runway and not before flying speed; nothing jumps as the wheels leave (pitch, climb rate, acceleration and height are measured tick by tick); wheels-down drag; throttling back slows it; landings flown by a pilot who flares: gentle, firm, wheels-up, and what they break; fourteen arrivals dropped onto the runway at set sink rates, nose angles and banks, judged by what the contact did (nothing, strained wings, one leg, both legs, propeller, wingtip scraped or torn off, destroyed); braking to a stop; repairs at home including new parts, legs and propeller, a wreck jacked back onto its wheels; a plane stopped on the enemy's airfield or run off the island is lost; bots left alone take off undamaged and raise their wheels |
| `TestAirframes` | each of the three planes, built from its own model as the game builds it: span, wheel track and propeller match the published figures to within 4 cm; shown at real size; the Mustang has four blades; the centre of gravity is 1.6 to 2.0 m above the wheels and they are a little ahead of it; it sits 10.5 to 13.5 degrees nose-up; the propeller clears the ground with the tail up; how far it must lean to touch a wingtip; the Spitfire's wheels fold outward and the others' inward; a full-power run-up on the brakes; then, with the hands and feet every plane has on the ground, the stick held hard over either way at 13, 22, 34, 49 and 67 mph: it turns, leans no more than a few degrees and never touches a wingtip or the propeller; and braked hard from a landing run with the tail up it stops without going on its nose |
| `TestCollisions` | box-overlap maths; a wingtip clip damages only the wingtips; a head-on destroys both; a pass three metres apart does nothing; team-mates can collide |
| `TestPlayerFlow` | 1 player + 9 bots through Input actions and touch events: both fitted guns fire, the stick rolls the plane and pulling turns it, the right pedal skids the nose and it straightens when let go, with one gun taken off one gun fires, a drag on open sky swings the view while the plane flies straight on and the view returns by itself, a finger on the stick does not turn the camera, a crash kills: no new plane, BLUE a pilot short, the sortie ends lost and the screen says so |
| `TestSortie` | three sorties by a scripted player with the bots stood down: five kills build a bounty of 100, 120, 150, 200 and 300; the sky is announced clear but the sortie goes on; shot up and short of fuel the plane is landed, the menu comes up with a price for repairs, for fuel and for both; REPAIR is paid from the bounty and only repairs are done, then fuel, neither twice; a bill that cannot be met is not run up, and the pilot's own gold pays when the bounty runs out; CASH OUT banks the bounty and ends the sortie. Then a Spitfire, uninsured: killed, the bounty and the Spitfire are lost and the fittings are not. Then insured: the premium is paid at take-off and the Spitfire survives its loss |
| `TestMatchSim` (3 seeds) | a bots-only battle under one-life rules, everyone taking off first: 10 planes, nobody gets a second one, the pilots left match the losses, at least four losses in five minutes, zero friendly-fire hits, no clumping, few uncaused losses, few collisions, bot accuracy stays in a human-like 2-25% band |
| hangar / lobby | scenes load and the lobby hands over to the arena without script errors |

Development tools, not tests: `tools/flight_lab.gd` (the flight model on its
own, in the air and on its wheels: `godot --headless --path . -s res://tools/flight_lab.gd -- air` or `-- ground`),
`tools/TakeoffTrace.tscn` (a scripted take-off or landing, printed tick by
tick) and `tools/CheckScripts.tscn` (loads every script to show parse
errors).

These run headless, so they prove rules and wiring, not feel. Screens were also
checked from software-rendered captures (`tools/ShotCapture.tscn`). **Not yet
tested:** a real phone (touch feel, frame rate, thermal; the APK builds and its
signature verifies, but it has not been run on a device) and anything networked.

`project.godot` makes untyped declarations a compile error.
