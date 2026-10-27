# Fatebound -> Unity port: progress log

Kevin (Oct 2026): "I want you to rebuild the entire game in unity" -- everything at once, the Godot game frozen at
0.31.222 -- "Can you build and put on repo then grokbot can make it". Claude writes the Unity project here (no Unity
editor in its workspace); grokbot opens it in Unity 6000.3.27f1 and builds the APK (UNITY_HANDOFF.md).

## Step 1 -- the simulation, ported and verified
- `Assets/Fatebound/Sim/` (namespace Fatebound.Sim, no engine references -- shared with a future .NET server):
  the match sim (siege_sim.gd -> SiegeSim.cs), the 5v5 (moba.gd -> Moba.cs + MobaData.cs), the kits
  (moba_kits.gd -> MobaKits.cs), the fog of war (moba_vision.gd -> MobaVision.cs), the Rift and the keeps
  (siege_land.gd / keep.gd -> Land.cs / Keep.cs), and Godot's own math the sim leans on, reproduced exactly:
  Vector2 (float components), RandomNumberGenerator (PCG32), String.hash, AStarGrid2D, Geometry2D's
  point-in-polygon, Array.sort_custom's introsort, Dictionary's insertion order (Core/).
- The unit dictionary is a typed class generated from a field table (tools/gen_unit.py -> Unit.g.cs) with
  Get/Set/Erase by key for the online snapshots.
- Parity: tools/parity/godot_trace.gd prints a digest of every unit's exact bits each tick from the GDScript sim;
  `dotnet run --project tools/simtest -- trace <seed> <hero> <ticks>` prints the same from C#. Five whole matches
  (seeds 1-4 and 7; all-bot and with the Knight, Golem, Druid; 19-36 thousand ticks each, two ending on the King)
  are identical tick for tick.
- Found on the way, kept for parity (flag SiegeSim.FIX_SEPARATE): the GDScript sim's unit separation never pushed
  two units in the same 0.9 m cell apart (`(lst as PackedInt32Array).append(i)` appended to a copy).

## Step 2a -- the GUI framework (Godot's UI, in C#)
- `Assets/Fatebound/GUI/` (namespace Fatebound.GUI, no engine references): the ~25 thousand lines of code-built Godot
  UI port onto Godot's own semantics instead of being redesigned for uGUI. Ported from the engine source (4.7.2):
  Node/SceneTree (enter-tree pre-order, ready post-order, deferred calls, queue_free, timers, process order),
  CanvasItem (draw API tessellated like RendererCanvasCull: polyline miters, AA feathers, 64-segment ellipses,
  ear-clipped polygons; z index, show-behind-parent, top level, clip_contents, modulate, CanvasLayer),
  Control (anchors/offsets, _size_changed with grow directions, presets, deferred minimum size, theme lookup with
  Godot's default theme), the containers (Box stretch with its error pixel, Grid, Center, Margin, Panel, Scroll with
  touch drag), Label (shaping, Godot's line breaking, ellipsis, line metrics, shadow/outline/fill), Button/BaseButton
  (state machine, styleboxes, icons), TextureRect, ProgressBar, HSlider, LineEdit, a [color] RichTextLabel,
  StyleBoxFlat (style_box_flat.cpp's draw), Tween (steps, easing equations), input routing (viewport.cpp: mouse
  focus, touch focus, STOP/PASS bubbling, hover, emulated mouse from touch), CPUParticles2D.
- Text: a TrueType reader + signed distance field atlas (Text/). Metrics follow TextServerAdvanced: ascent ceiled /
  descent floored, 26.6 advances, whole pixels above size 20 with carried remainders, ceil'd line sizes, the MSDF
  default font measured at 48 px. tools/parity/godot_fonts.gd vs `guitest fonts`: 1198 of 1200 string widths equal.
- Layout parity: tools/parity/uiparity.sh builds a JSON UI spec in Godot (godot_ui.gd) and in C# (guitest ui) and
  compares every control's rect and minimum size: ui/basic.json, 25 controls, all equal. `guitest uirender` draws a
  spec with a software rasteriser (the same shading the Unity shader does); side by side with Godot's render the two
  are near pixel-identical.
- Assets: tools/sync_assets.py mirrors godot/assets + content into Assets/Resources/res/ (webp -> png, svg -> png via
  Godot, fonts -> .bytes for the TrueType reader). The scenes and resources (.glb .gltf .scn .tscn .res .tres) are
  baked by tools/bake/bake.sh (Godot headless: what load()/instantiate() give, as data) into <path>.bytes and rebuilt
  by GUI/Scene3D/BakedLoader.cs; tools/parity/bake.sh diffs Godot's and the port's view of them.
- Unity side of the GUI: Client/GUI/GuiCanvas.cs runs the SceneTree each frame (Update -> Iterate, LateUpdate ->
  Render) and draws its batches on a Screen Space Overlay canvas, one CanvasRenderer per batch;
  Client/GUI/UnityGuiHost.cs loads res:// files from Resources; Shaders/Resources/Shaders/FateboundGUI.shader shades
  the batches (clip rect, SDF text, hairlines). Touch feeds Godot's emulated mouse, Escape/back goes to
  NOTIFICATION_WM_GO_BACK_REQUEST (the tree never quits on back; the game handles it).

## Step 2b -- the GDScript runtime (commit 480bea2)
- `Sim/Script/`: Var (Godot's Variant semantics: int/float distinct, cross-type ==, deep container equality, Godot
  truthiness), GDict (ordered), GArray, str()/%/sprintf exact, Godot's hash(), JSON (key order, float parsing),
  String methods. tools/parity/runtime.sh: 512 lines identical to Godot.

## Step 3 -- the engine services, Godot's math, skeletal animation, the 3D facade, the renderer
- Math (Sim/Core: Vec2/2i/3/3i/4/4i, Basis, Quat, Xform3, Aabb, Plane, Projection; GUI/Core/Math2DGodot.cs: Rect2,
  Color, Transform2D additions + OKHSL): tools/parity/math.sh, 18,093 lines identical.
- Services (GUI/Services: OS, Engine, Time, FileAccess/DirAccess (user:// = the app's files dir), ConfigFile,
  PackedByteArray encode/compress (zlib/gzip/zstd -- vendored ZstdSharp in Assets/Plugins), Crypto/hashing, RegEx,
  threads, WebSocketPeer, HTTPRequest; Sim/Script/GMarshal.cs var_to_bytes/bytes_to_var/var_to_str):
  tools/parity/services.sh, 1128 lines identical. The device answers come from an IPlatform host (PlatformHost.Init):
  Client/Core/UnityPlatform.cs answers as Godot's Android build (getFilesDir, Build.MODEL, ANDROID_ID, locale).
- Audio (GUI/Services/Audio.cs + Client/Core/UnityAudio.cs): AudioStream (.wav/.ogg/.mp3) and AudioStreamPlayer with
  Godot's playback rules (polyphony 1, finished from internal process, paused outside the tree), AudioSources.
- Skeletal animation (GUI/Scene3D: Skeleton3D + SkeletonModifier3D, BoneAttachment3D, Animation, AnimationLibrary,
  AnimationMixer/Player): tools/parity/anim.sh, 5057 lines identical (synthetic rig + the Meshy knight's real clips).
- The 3D scene facade (GUI/Scene3D, under the FB3D define -- set for Fatebound.GUI by its csc.rsp): Node3D with
  Godot's dirty-flag transforms, MeshInstance3D/MultiMesh/Sprite3D/lights/Camera3D (camera_3d.cpp's projection,
  unproject), Environment, meshes (ArrayMesh, primitives, SurfaceTool, ImmediateMesh), StandardMaterial3D,
  ParticleProcessMaterial, textures (curves, gradients, noise), GPUParticles3D simulated on the CPU (a port of
  particles.glsl + the ParticleProcessMaterial shader).
- The Unity renderer (Client/Render3D): a pull model -- facade nodes mark themselves dirty, UnityRenderer3D.Frame()
  syncs GameObjects once a frame; Godot -> Unity mirrors X (Conv.cs); meshes/materials cached and rebuilt on change;
  skinned meshes driven by the skeleton's skin transforms; MultiMesh and particles drawn instanced; each World3D on
  its own layer; each 3D viewport a camera into an HDR texture (32-bit float RGB like Godot Mobile's RGB10A2)
  followed by Godot Mobile's post chain (PostChain + Fatebound/Post: glow gather/down/up, filmic/ACES/Reinhard
  tonemap, glow blend modes, adjustments, the [0, 2] range of Godot's buffer) into the sRGB texture the GUI shows.
  Shaders: FateboundCommon3D.hlsl (Godot's forward lighting, omni falloff, fog, billboards) and
  FateboundStandard3D (BaseMaterial3D as uniforms).
- The GUI now draws in Godot's 2D colour space: batches go into a raw RGBA8 texture through a command buffer when the
  screen camera starts (after the viewport cameras), blended on sRGB values like Godot's 2D renderer, and one overlay
  quad (Fatebound/GUIComposite) puts it on the screen.
- Unity project setup: Editor/BuildScript.cs (URP asset, player settings -- Vulkan, IL2CPP ARM64, linear, sensor
  landscape -- and the Android build, `-executeMethod Fatebound.EditorTools.BuildScript.BuildAndroid`),
  Editor/AssetImport.cs (texture/audio import settings from Godot's .import sidecars), link.xml.

## Step 4 -- the game translated, compiling, and run headless
- All of the game's GDScript outside the sim (godot/scripts/app, meta, ui, siege -- the sim was already C#) is in
  `Assets/Fatebound/Game` (Fatebound.Game, engine-free), with what it needed from the engine added to the facade
  (GUI/Missing, Sim/Missing: one file per area, each saying what it adds). The last pieces: siege_mode.gd's sound
  (SiegeMode.Sound.cs), Node.duplicate (a ragdoll's dropped weapons), reload_current_scene with the two scenes built in
  code (GameMain registers scenes/Boot.tscn and scenes/Main.tscn), RichTextLabel.visible_characters, Land.bake_key
  (Godot's own value for the frozen land: 633754923, the key in the baked cache.res).
- Every assembly compiles against Unity 6000.3's references (tools/compilecheck: Sim, GUI, Game, Client, Editor).
- tools/gametest runs the whole game off the device (no renderer, no physics backend, the network cut off) from a
  script of taps, with screenshots of the 2D layers. Runs so far, no exception in any: the first start (title, the
  Herald's naming, the tutorial offer, the training picker, training 1 for a minute, training 2 -- a full offline 5v5
  -- for 12 game minutes), and Home -> daily reward -> PLAY -> an online 5v5 against godot/server/siege_server.gd run
  on loopback. The game's work per frame there (sim, view, HUD, on a desktop CPU): about 1 ms, plus about 1.3 ms
  building the 2D draw lists.
- Found on the way, the same in Godot 0.31.222 (the port matches it): on a 20:9 phone the Herald's SHOW ME HOW button
  sits half off the top of the screen (herald_intro.gd puts the choice above the art, which is 102 px from the top).
- The match log's render numbers come from Unity now (Client/Core/UnityRenderStats.cs): gpu3d is the frame's GPU time
  (FrameTimingManager), draw calls and triangles the frame's (ProfilerRecorder), the adapter SystemInfo's.

## Step 5 -- the first builds on Kevin's phone (S21 Ultra, Adreno 660, Vulkan)
- Upside down: the GUI's projection was flipped twice (CommandBuffer.SetViewProjectionMatrices adapts it itself).
- Grey matches: the match's sky had no shader (an exception in URP's camera setup every frame); the match viewport's
  MSAA needs URP's own MSAA on (the asset's 2, the screen kept at 1).
- Dark matches, pink spell effects: FXC (Unity's first compiler stage for Vulkan) crashed on the post shader's
  tonemap pass; fx_beam/ground/scorch/shell had a property named 'color', a ShaderLab keyword. tools/shadercheck now
  compiles with FXC itself (FBFXC=1, Wine) and lints property names: all 41 shaders run on the phone.
- Ragdolls: a ragdoll's bones don't collide with each other (PhysX fought the overlapping capsules at the joints).
- The river didn't react: a material's parameters set after its mesh was built never reached Unity (the wave
  texture rip_tex, and every fade or tint done through a material) -- materials are now refreshed in place each frame.
- Unity's own errors reach the match log, and the boot log lists any shader the GPU can't run, by file.

## Step 6 -- frame rate: the 30 fps ceiling, an on-screen counter, the draw step split in the log
Kevin's first match log on the port (a training 5v5, 68-115 units): 27.6 fps (19-30) -- never over 30, in either
match that session, quiet stretches included (Godot 0.31.220/221: 34.7 and 40.2 fps, peaks to 56). The graphics chip
~22 ms a frame (Godot ~23, the same 1600x720); the game's code far lighter than in Godot (sim 1.0 ms vs 8.2, view 3.5
vs 6.9); ph_draw ~20 ms (Godot ~10) and the worst frame each second ~58 ms (Godot ~45).
- The ceiling: Optimized Frame Pacing (Swappy) was on in the build script -- it holds a frame that misses 60's 16.7 ms
  to 30, and Unity can report a 30 Hz display under it (and UnityPlatform clamped the 60 cap to the reported rate).
  Off now; Application.targetFrameRate is the cap itself (60; no cap: the display's fastest mode, as Android's
  default target is 30), set again if anything resets it.
- FpsCounter (Game/App): the frame rate over everything, top right (left of a match's pause button), each half
  second, green from 55 / amber from 30 / red below.
- The match log's STAT lines: the port's draw step in parts (d_sync, d_mat, d_skin, d_mm, d_cam, d_part, d_sweep,
  d_gui, d_rec), URP's own rendering on the main thread (u_urp: after LateUpdate, so in ph_other), Unity's main-thread
  frame and its wait for the present (u_main, u_wait), the display (hz, modes, target), and the garbage collector
  (gc: collections that second; alloc: KB a frame, where the player counts it) -- RenderingServer.HostFrameTimes /
  HostStatText, from Client/Core/UnityRenderStats.cs.
