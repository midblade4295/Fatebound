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
  Godot, fonts -> .bytes for the TrueType reader); .res/.scn/.tscn are baked separately (to do).
