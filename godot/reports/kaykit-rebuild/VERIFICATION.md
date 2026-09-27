# KayKit 3D rebuild — verification (2026-09-27)

Base: public `codex/fatebound-visual-rebuild` at `d43282a` (the local-only 0.5.1 bundle from the
previous session was not available, so this is an independent rebuild on the public base).
Engine: Godot 4.7.2 stable, Compatibility renderer. Visual target: the live browser v114 battle
screen (`fatebound.html`, SHA-256 `84697859…f3b4e9`), rendered in Playwright at 420×936.

## What changed (presentation only)

- `scripts/kaykit_stage.gd` (new): real-time 3D battlefield — hex terrain batched in MultiMeshes,
  flanking blue/red castles, a contested tower whose banner follows the tower lead, forest props,
  drifting clouds, filmic lighting with shadows and depth fog. Skinned KayKit heroes with attached
  weapons and per-class animation sets (idle / attack / big / hit / death), lunge and recoil motion,
  3D rings and sparks for spells and hits. Raid mode stages the boss at 2.3× scale facing the clan;
  portrait mode puts the hero on a lit hex plinth for Home/Hero/Raid pages.
- `scripts/battlefield.gd`: hosts the stage in a SubViewport rendered at physical pixel density
  (crisp on high-DPI phones), draws garrison panels, tower title and reference-style nameplates
  (level hex, name, ATK, HP bar, shield pips) at projected head positions. Public API unchanged.
- `scripts/dice_strip.gd`: three real 3D golden d12 dice (generated mesh + engraved face atlas),
  tumbling while a roll is pending and settling so the server-confirmed face points at the camera.
- `scripts/ui/tactile_style.gd` (new) + `scripts/ui/visual_theme.gd`: dimensional button faces
  (drop shadow, physical lip, gradient body, gloss, rim, optional glow; pressed state sinks into
  the lip). Palettes: primary (ROLL / Enter Battle), gold, secondary, active, arcane, disabled.
- `scripts/main.gd`: battle HUD relaid out like v114 (your crowns / clock / enemy crowns, map +
  menu strip, tall arena, results box, ×mult · ROLL · RALLY row), ROLL focus-cost subtitle,
  light-sweep shimmer, squash-and-spring press animation on every button, reduced-motion aware.
- Gameplay, rules, rewards, save schema, network protocol and online identity: untouched.

## Checks run here

| Check | Result |
| --- | --- |
| `tests/full_layouts.gd` (72 menu layouts + battle at 6 resolutions, real pointer nav) | pass, 0 failures |
| full_core_smoke, full_ui_smoke, hold_roll, training_full_flow, legacy_and_campaign, progression_parity, arena_parity, all_modules_parse, wire_smoke | pass |
| api_smoke, art_flow_smoke, art_layout_smoke, transport_smoke, visual_smoke | fail — identical failures on the untouched base (need the live server or test the retired 0.2 home) |
| Rendered battle, roll, gift, raid, home, hero screens at 420×936 and 2× device scale (llvmpipe) | reviewed |
| Android export (arm64, package `com.fatebound.kaykitrebuild`, 0.6.0-kaykit-rebuild) | built, zipalign + APK signature v2/v3 verified |

## Not verified

Physical Android look, touch feel, frame rate, heat and audio. The renderer used here is software
OpenGL (llvmpipe), not a phone GPU.
