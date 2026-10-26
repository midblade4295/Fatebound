# Porting the GDScript to C# (Fatebound Unity port)

The Unity build runs the game's own code, translated file by file from `godot/scripts/**.gd` to C#, on a C#
re-implementation of the Godot APIs it uses (engine-free: it also runs headless in .NET for tests). A ported file
should read line for line against its .gd: same structure, same names, same comments (keep the comments -- they carry
Kevin's requests and the version history). Translate, don't redesign. When the .gd does something odd, keep it.

## Where things are
| Assembly / folder | Namespace | What |
|---|---|---|
| `Assets/Fatebound/Sim/` | `Fatebound.Sim` | the match simulation (already ported, verified) + `Sim/Script/` the GDScript runtime: `Var`, `GDict`, `GArray`, `GD`, `GStr`, `GFormat`, `JSON`, `GMarshal` + `Sim/Core/` math: `Vec2`, `Vec2i`, `Vec3`, `Basis`, `Quat`, `Xform3`, `Aabb`, `Plane`, `Projection`, `Vec4` |
| `Assets/Fatebound/GUI/` | `Fatebound.GUI` | Godot's engine in C#: `Node`, `SceneTree`, `Viewport`, `Control` + every control, `Tween`, `Input`, text, `Resource`s, `Col` (Color), `Rect2`, `Xform2` (Transform2D); `Scene3D/` the 3D nodes and resources; `Services/` OS, Time, FileAccess, networking... |
| `Assets/Fatebound/Game/` | `Fatebound.Game` | **the ported game code** (engine-free asmdef `Fatebound.Game`) -- mirrors `godot/scripts/`: `Game/App/`, `Game/Meta/`, `Game/Siege/`, `Game/UI/` |
| `Assets/Fatebound/Client/` | `Fatebound.Client` | Unity glue: renders the GUI and the 3D, feeds input, platform plugins. Game code never references it. |

Compile check (Unity's own reference assemblies, .NET Standard 2.1, C# 9 -- what Unity compiles with):
`cd unity/tools/compilecheck && dotnet build Game.csproj -nologo -v q`. C# 9 means: no file-scoped namespaces, no
global usings, no `record struct`, no raw string literals, no `required`.

## One .gd file = one C# file and class
- `godot/scripts/app/siege_app.gd` -> `Assets/Fatebound/Game/App/SiegeApp.cs`, `class SiegeApp` (file name PascalCased).
  `class_name Foo` in the .gd: still use the file-derived name (and add `// class_name Foo` if it differs).
- `extends Control` -> `public class SiegeApp : Control`; `extends RefCounted` / `extends Object` -> a plain class
  (`public class Profile`); `extends Resource` -> `: Resource`. A script with only consts and static funcs ->
  `public static class`. Inner `class X:` -> a nested class.
- `const UI = preload("res://scripts/app/ui.gd")` -> a using alias at the top of the file:
  `using UI = Fatebound.Game.Ui;` (then `UI.Label(...)` reads as in the .gd). Same for every script preload.
- `preload("res://x.png")` / `load(...)` of a resource -> `ResourceLoader.Load<Texture2D>("res://x.png")` (const ->
  `static readonly`). Scenes: `ResourceLoader.Load<PackedScene>(...)` then `.Instantiate()`.

### The standard header
```csharp
// Ported from godot/scripts/app/screens.gd (Fatebound <version of the .gd>).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using Transform2D = Fatebound.GUI.Xform2;
using Quaternion = Fatebound.Sim.Quat;
using AABB = Fatebound.Sim.Aabb;
using Material = Fatebound.GUI.GMaterial;
using Environment = Fatebound.GUI.Environment;   // (System.Environment otherwise)
using UI = Fatebound.Game.Ui;                    // the file's own script preloads
...
namespace Fatebound.Game
{
    public class Screens { ... }
}
```
Only the aliases a file needs; unused ones are harmless.

## Names
- **Methods**: PascalCase, a leading underscore kept: `chests_row` -> `ChestsRow`, `_on_pressed` -> `_OnPressed`,
  `get_value` -> `GetValue`. The rule is mechanical so other files can call yours before they're ported. Godot's
  virtuals: `_ready` -> `protected override void _Ready()`, `_process(delta)` -> `protected override void
  _Process(double delta)`, `_physics_process` -> `_PhysicsProcess`, `_input(e)` -> `protected override void
  _Input(InputEvent e)`, `_unhandled_input` -> `_UnhandledInput`, `_gui_input` -> `protected override void
  _GuiInput(InputEvent e)`, `_draw` -> `protected override void _Draw()`, `_notification(what)` -> `public override void
  _Notification(int what)`, `_enter_tree`/`_exit_tree` -> `_EnterTree`/`_ExitTree`, `_get_minimum_size` -> `public
  override Vector2 _GetMinimumSize()` (check the base class for the exact signature), `_init(...)` -> constructor.
  If a name collides with a C# keyword or a base member, append `_` (`Equals_`) and note it.
- **Fields, constants, enum values, dictionary keys**: exactly the GDScript names (`var player_name` ->
  `public string player_name`; `const MAX_HP := 10` -> `public const int MAX_HP = 10`). Make members `public` unless
  the .gd name starts with `_` (then `internal`/`public` too if other files touch it -- GDScript has no privacy; when
  in doubt, public).
- **Signals**: `signal changed` -> `public event Action Changed;`, `signal picked(id: String)` -> `public event
  Action<string> Picked;`. `changed.emit()` -> `Changed?.Invoke()`. `x.changed.connect(f)` -> `x.Changed += f`;
  disconnect -> `-=` (keep the delegate in a field if the .gd disconnects it). `is_connected` -> keep a bool.
  `connect(..., CONNECT_ONE_SHOT)` -> a handler that removes itself. Godot's own signals are C# events on the
  framework classes (`button.Pressed += ...`, `timer.Timeout += ...`, `tween.Finished += ...`,
  `tree.ProcessFrame += ...`).
- **Godot API**: the Godot name PascalCased (`add_child` -> `AddChild`, `queue_free` -> `QueueFree`,
  `add_theme_stylebox_override` -> `AddThemeStyleboxOverride`, `set_anchors_and_offsets_preset` ->
  `SetAnchorsAndOffsetsPreset`). Properties are C# properties (`l.text = "x"` -> `l.Text = "x"`,
  `p.custom_minimum_size` -> `p.CustomMinimumSize`). Constants keep Godot's spelling on their class
  (`Control.PRESET_FULL_RECT`, `Control.SIZE_EXPAND_FILL`, `TextServer.AUTOWRAP_WORD_SMART`,
  `BaseMaterial3D.SHADING_MODE_UNSHADED`, `Mesh.ARRAY_VERTEX`, `Tween.TRANS_SINE`, `Color.WHITE`, `Vector3.UP`).
  If a member you need doesn't exist in the facade, don't work around it: list it in your report (or, if it's small and
  you're sure of Godot's behaviour from /home/claude/godot-src, add it to the facade and say so).

## Types
| GDScript | C# |
|---|---|
| `int` | `int` (`long` for big values: `Time.get_ticks_usec/msec`, unix time in ms, hashes, 64-bit ids) |
| `float` | `double` (Vector components are `float`, as Godot's) |
| `bool`, `String` | `bool`, `string` |
| `Vector2/3/2i`, `Color`, `Rect2`, `Transform3D`... | the aliases above (structs, value semantics like Godot) |
| `Dictionary` | `GDict` (ordered, shared by reference) |
| `Array` (untyped) | `GArray` |
| `Array[Dictionary]`, `Array[String]`, `Array[int]`... | `List<GDict>`, `List<string>`, `List<int>` when it stays local; `GArray` when it's stored in a dictionary, sent, saved or passed to code taking `Array` |
| `PackedStringArray` | `string[]` (`List<string>` if appended to) |
| `PackedVector2Array`, `PackedVector3Array`, `PackedColorArray` | `List<Vector2>` / `Vector2[]` etc. |
| `PackedFloat32Array`, `PackedInt32Array` | `List<float>` / `float[]`, `List<int>` / `int[]` |
| `PackedByteArray` | `byte[]` |
| `Variant` / untyped `var` / untyped parameter | `Var` -- but if the value always has one type, use that type (an untyped `app` parameter that is always the SiegeApp -> `SiegeApp app`) |
| `Callable` | `Action`, `Action<T>`, `Func<...>` (or `Delegate` stored in a Var) |
| `Object`, `Node` typed or untyped | the real class when known |

Typed GDScript (`var x: int = ...`, `:=`) keeps its type. `:=` -> `var` in C# is fine when the type is obvious.

## The runtime: Var / GDict / GArray (Sim/Script, read Var.cs once)
- `d.a.b` (dictionary attribute access) -> `d["a"]["b"]`; `d.get("k", 0)` -> `d.Get("k", 0)`;
  `d.has("k")` / `"k" in d` -> `d.Has("k")`; `d.erase("k")` -> `d.Erase("k")`; `d.keys()` -> `d.Keys()` (a GArray).
  A missing key reads as Nil (Godot would error; the code never relies on that).
- **Writes**: `d.a = 1` -> `d["a"] = 1` (GDict indexer). A write through a chain needs the last container as itself:
  `d.chests.slots[i].id = 5` -> `d["chests"]["slots"][i].D["id"] = 5` (`.D` = the GDict, `.A` = the GArray). The
  compiler tells you (CS1612) when you forget. `d.stats.kills += 1` -> `d["stats"].D["kills"] += 1`.
- Literals: `{"ok": false, "error": "x"}` -> `new GDict { { "ok", false }, { "error", "x" } }` or
  `GDict.Of("ok", false, "error", "x")`; `[1, "a"]` -> `GArray.Of(1, "a")`; `[]` -> `new GArray()`.
- Conversions (GDScript's constructors, exact): `int(x)` -> `(int)x` or `GD.Int(x)`; `float(x)` -> `(double)x` /
  `GD.Float(x)`; `str(x)` -> `GD.Str(x)` (also `GD.Str(a, b, c)`); `bool(x)` -> `(bool)x`; `String(x)` -> `GD.Str(x)`.
  `x as String` on a Var -> `x.AsString()`; `(x as Array)` -> `x.A`; `(x as Dictionary)` -> `x.D`.
- Type tests: `x is int` -> `x.IsInt`, `is float` -> `IsFloat`, `is String` -> `IsString`, `is Dictionary` ->
  `IsDict`, `is Array` -> `IsArr`, `is Vector2` -> `IsVec2`, `is Node` / any class -> `x.Is<Node>()`;
  `typeof(x) == TYPE_INT` -> `GD.TypeOf(x) == GD.TYPE_INT`. `x == null` -> `x.IsNull` (Var) / `x == null` (class).
  `is_instance_valid(n)` -> `GD.IsInstanceValid(n)`.
- Truthiness: `if x:` on a Var -> `if (x)` (Var has Godot's truthiness: 0, "", empty, null are false). On a typed
  int/string/array write it out: `if (n != 0)`, `if (s != "")`, `if (!a.IsEmpty())` -- GDScript's `if some_array:`
  means "not empty".
- `==` on Vars is GDScript's (1 == 1.0 true). Operators `+ - * / %` on Vars follow Godot (int/int is integer
  division). Comparing Var to a C# literal works (`v == "x"`, `v > 3`).
- `for k in d:` -> `foreach (var k in d)` (keys, in order); `for x in arr:` -> `foreach (var x in arr)`;
  `for i in n:` / `range(n)` -> `for (int i = 0; i < n; i++)`; `range(a, b, s)` -> a for loop.
  `for i in d.size()` style loops: plain for.
- `len(x)` -> `GD.Len(x)` / `.Size()` / `.Length`; `x.size()` -> `x.Size()`; `x.is_empty()` -> `x.IsEmpty()`
  (string: `s.Length == 0` or `s.IsEmpty()`).
- `arr.sort_custom(func(a, b): return a.x < b.x)` -> `arr.SortCustom((a, b) => a["x"] < b["x"])` -- Godot's exact sort
  (ties land where Godot puts them). For a `List<T>`: `GSort.Sort(list, (a, b) => ...)`, never `List.Sort` (unstable
  in a different way). `arr.sort()` -> `arr.Sort()`.
- `x.duplicate(true)` -> `.Duplicate(true)`. `arr.filter/map/any/all/reduce` -> same names with lambdas.
- Strings: `"%d gold" % n` -> `GD.Fmt("%d gold", n)`; `"%s/%s" % [a, b]` -> `GD.Fmt("%s/%s", a, b)` -- never C#
  interpolation for anything with a float (Godot's float text differs from .NET's). `str(1.0)` is "1.0".
  String methods are extensions with Godot's behaviour: `s.begins_with` -> `s.BeginsWith`, `substr` -> `Substr`,
  `left/right` -> `Left/Right`, `find` -> `Find`, `split(",")` -> `s.Split(",")` (C#'s, same result) /
  `split(",", false)` -> `s.Split(",", false)`, `strip_edges` -> `StripEdges`, `capitalize` -> `Capitalize`,
  `to_upper/lower` -> `ToUpperInvariant/ToLowerInvariant`, `to_int` -> `ToInt` (long), `to_float` -> `ToFloat`,
  `is_valid_int` -> `IsValidInt`, `pad_zeros` -> `PadZeros`, `", ".join(arr)` -> `GStr.Join(", ", arr)`,
  `replace`/`contains` -> C#'s `Replace`/`Contains`, `length()` -> `.Length`, `s[i]` -> `s.Substring(i, 1)`,
  `md5_text`/`sha256_text` -> `Md5Text`/`Sha256Text`, `to_utf8_buffer` -> `ToUtf8Buffer`. See Sim/Script/GStr.cs.
- JSON: `JSON.stringify(d)` -> `JSON.Stringify(d)`; `JSON.parse_string(s)` -> `JSON.ParseString(s)` (a Var; numbers
  are floats, as in Godot). `var_to_bytes`/`bytes_to_var` -> `GMarshal`.
- Math: `clampf/clampi/maxf/mini/absf/lerpf/sign/floori/roundi/snappedf/wrapf/ease/smoothstep/move_toward/
  lerp_angle/deg_to_rad/...` -> `GD.Clampf` ... (same names PascalCased, on doubles; `*i` versions return int).
  `PI`/`TAU`/`INF` -> `GD.PI`/`GD.TAU`/`GD.INF`. `randf/randi/randf_range/randi_range/randomize/seed` ->
  `GD.Randf()` ...; `RandomNumberGenerator.new()` -> `new Rng()` (`rng.seed = x` -> `rng.Seed = (ulong)x`,
  `rng.randf_range` -> `rng.RandfRange`, `rng.randi_range` -> `rng.RandiRange`). `hash(x)` -> `GD.Hash(x)` (Godot's
  exact numbers: seeds and picks match the Godot build and the server).
- Vectors: methods PascalCased (`v.distance_to(w)` -> `v.DistanceTo(w)`, `v.normalized()` -> `v.Normalized()`,
  `Vector2.from_angle(a)` -> `Vector2.FromAngle(a)`). Components: `v.x`. Struct members of a property can't be
  assigned in C#: `node.position.y = 2` -> `var p = node.Position; p.y = 2; node.Position = p;`.

## GDScript constructs
- `match x:` -> `switch` (strings and ints work; a Var: switch on `x.AsString()` / `(int)x`); `match` with arrays,
  bindings or guards -> if/else chains.
- Default arguments that aren't C# constants (`fill := CARD` where CARD is a Color, `[]`, `{}`) -> a nullable or
  `default` parameter and `fill ??= CARD;` inside (`Color? fill = null`), or an overload.
- `@onready var x = $A` -> a field assigned at the top of `_Ready()`; `$A/B` / `get_node("A/B")` ->
  `GetNode<T>("A/B")`; `@export var` -> a public field.
- Properties with `set(v):`/`get:` -> C# properties. `static var` -> `static` field. `enum E {A, B}` -> `public enum
  E { A, B }` plus, if the .gd uses the values as ints, `public const int A = 0` or casts.
- Lambdas -> C# lambdas; a lambda capturing a loop variable: copy it to a local first (C# `for` captures the
  variable, GDScript captures the value).
- `await get_tree().process_frame` -> `await Await.ProcessFrame();`; `await get_tree().create_timer(t).timeout` ->
  `await Await.Timer(t);`; awaiting a signal -> `await Await.Signal(h => x.Done += h, h => x.Done -= h);` -- inside an
  `async void` (or `async Task` if a caller awaits it) method. Only a few places do this. Wrap an `async void` body in
  `try { ... } catch (Exception e) { GD.PushError(e.ToString()); }` (an exception escaping one would end the process).
- `super.f()` / `super()` -> `base.F()`; `self` -> `this`.
- `assert(...)` -> drop it (release builds drop them) or `GD.PushError` if it guards something.
- `print(...)` -> `GD.Print(...)`, `push_error/push_warning` -> `GD.PushError/PushWarning`.
- Errors: a GDScript runtime error aborts the current function and the game goes on. C# exceptions go up to the
  frame loop's handler for that callback (the same effect). Don't add try/catch the .gd doesn't have.
- `call_deferred("f")` / `f.call_deferred()` -> `CallDeferred(F)`; `set_deferred("p", v)` -> `CallDeferred(() => P = v)`.
- `has_method("x")` on something you've typed -> just call it (or `is` check); `callv(name, args)` -> a `switch` on
  the name.
- `Engine.has_singleton("Plugin")` / platform plugins -> keep the call (the facade has a registry the Unity client
  fills); don't remove features.

## Godot classes
Everything the game instantiates exists in Fatebound.GUI with Godot's name (`Label`, `Button`, `TextureRect`,
`StyleBoxFlat`, `Tween`, `MeshInstance3D`, `StandardMaterial3D`, `GPUParticles3D`, `SubViewport`, `Camera3D`,
`AnimationPlayer`, `Skeleton3D`, `HTTPRequest`, `WebSocketPeer`, `FileAccess`, `Time`, `OS`...). `X.new()` ->
`new X()`. Read the facade class when unsure of a member's C# name.

## Checklist per file
1. Header, aliases, namespace, class with the right base.
2. Every const / var / signal / func translated in order, comments kept.
3. Compiles in `tools/compilecheck/Game.csproj` together with the rest (calls into files not ported yet are fine if
   you follow the naming rule -- they'll resolve when those land; note them in your report).
4. Report: what you couldn't translate faithfully, facade members you needed and didn't find, and anything the .gd
   does that looks platform-specific.

## Pitfalls found so far
- **Struct defaults**: `new Basis()`, `new Quat()`, `new Xform3()`, `new Projection()`, `new Xform2()`, `new Col()`
  are all zeros in C#, unlike Godot's `Basis()` (identity), `Quaternion()` (0,0,0,1), `Transform3D()` (identity),
  `Color()` (0,0,0,1). Translate `Transform3D()` as `Transform3D.IDENTITY`, `Basis()` as `Basis.IDENTITY`,
  `Quaternion()` as `Quaternion.IDENTITY`, `Color()` as `new Color(0, 0, 0, 1)`.
- **Names that clash**: the game's own `meta/platform.gd` is `Fatebound.Game.Platform`; the engine's device layer is
  `Fatebound.GUI.PlatformHost` / `IPlatform` (the game never calls it directly; OS/DisplayServer/Time do).
  `Fatebound.GUI.Time` (Godot's Time singleton) and `Fatebound.GUI.Environment` hide the .NET/Unity names inside the
  game: write `System.Environment` explicitly if you ever need .NET's.
- **Math checks**: `GD.MathChecks` (default true) reproduces Godot's debug-build errors/fallbacks for e.g.
  `normalized()` of a zero vector. It stays on in the Unity build: the game always shipped as a Godot debug export.
- **Members that differ from Godot on the old 2D structs** (kept for the GUI): `Vec3.Normalized` (no finite check:
  `NormalizedChecked` is Godot's), `Xform2(rot, pos)` / `Rotated` / `GetRotation` / `AffineInverse` (the exact Godot
  versions are `FromRotation`, `RotatedExact`, `RotatedLocalExact`, `GetRotationExact`, `AffineInverseExact`),
  `Col.Html`/`ToHtml` (`HtmlExact`/`ToHtmlExact`), `Col.FromHsv` (`FromHsvExact`). Use the exact versions in game code.
- **Untyped dictionaries from JSON hold floats**: `int(d.hp)` -> `(int)d["hp"]` (truncates like GDScript).
