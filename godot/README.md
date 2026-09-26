# Fatebound Godot Preview 0.2 — original artwork and responsive layout

Separate Android package: `com.fatebound.godotpreview`; versionCode 2.
This updates preview 0.1 in place using the same debug certificate and user-data
paths. It does not update production Fatebound or Google Play.

This iteration replaces the M1 diagnostic-screen battle with the original v114
hex terrain, towers and baked character/weapon animations. All 45 hero/weapon
combinations have idle/attack/heavy/hit/KO frames. 1,170 frames were split into
225 lossless strips and verified pixel-for-pixel; no source HTML/art was changed.
The artwork remains 2D baked sprites, as in the existing game. Fully skinned 3D
models, the permanent Home/Shop/Guild/Raid shell and cross-client progression
transfer are NOT included.

Native layout gives ROLL/Rally, two spells and ALL-IN/Ultimate their own rows.
The oversized horizontal tower list becomes a separate scrollable selector.
No raw JSON or internal debug output appears in the ordinary battle HUD.
The battlefield pans independently to show crowded formations; a pan never
moves a hero to another tower. Server-positive HP is still required to respawn.

The original PCM cues are included locally as WAVs and routed through a bounded
native audio pool. Native audio was not listened to on an Android phone here.
No new requests fetch graphics/sounds during battle. The existing HTTPS API,
server authority, transport2 gzip/deltas, balance110 and 20-second/20-slot rule
remain unchanged.

Test evidence: reports/ART_PIXEL_VERIFICATION.json, ART_LAYOUT_TEST.json and
ART_FLOW_TEST.json. The screenshot native-art-battle.png is an actual Godot
OpenGL/Mesa render of a local fixture, not AI-generated imagery or a phone capture.
Tests cover six portrait/tablet sizes and eight real native-UI flow checks against
an isolated loopback server fixture. Test sources are excluded from APK exports.

Engine used: Godot 4.7.2 from the installed migration toolchain. Open project.godot
with matching export templates. Use the dedicated preview debug key from the VM;
do not generate a replacement key or use production signing secrets.
