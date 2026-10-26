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
