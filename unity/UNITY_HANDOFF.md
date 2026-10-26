# Fatebound Unity port -- build handoff (for grokbot)

Kevin asked for the whole game rebuilt in Unity. This folder (`unity/` on branch `claude/unity-port`) is the Unity
project. It was written without a Unity editor: every C# file compiles against Unity 6000.3's reference assemblies,
but the shaders, the URP setup and the APK have never been built. Expect a first round of fixes; the logs below are
what I need back to make them.

## What it is
- Unity **6000.3.27f1**, URP 17.3 (`Packages/manifest.json`), Android, IL2CPP ARM64, Vulkan only, linear colour.
- The game's own GDScript translated to C# (`Assets/Fatebound/Game`), running on a C# re-implementation of the
  Godot APIs it uses (`Assets/Fatebound/GUI`, `Assets/Fatebound/Sim`), drawn by `Assets/Fatebound/Client`.
  No scene setup: `Client/Core/Boot.cs` starts everything from an empty boot scene.
- Assets live in `Assets/Resources/res/` (mirrored from `godot/assets` by `tools/sync_assets.py`; 3D scenes baked
  from Godot by `tools/bake/bake.sh`). The first import takes a while (several hundred MB of textures and audio).

## Build
1. Open `unity/` in Unity 6000.3.27f1 (Android Build Support + IL2CPP installed) -- or skip to step 3.
2. Menu **Fatebound > Setup Project** (creates the URP asset in `Assets/Fatebound/Settings/`, the player settings,
   `Assets/Fatebound/Boot.unity`). The build step runs it too.
3. Command line:
   ```
   Unity -batchmode -quit -projectPath unity \
     -executeMethod Fatebound.EditorTools.BuildScript.BuildAndroid -logFile build.log
   ```
   Environment variables (all optional):
   - `FB_OUTPUT` -- default `Builds/Fatebound.apk` (an `.aab` name builds a bundle)
   - `FB_ANDROID_PACKAGE` -- default `com.fatebound.unityport`, which installs beside the Godot preview. Saves don't
     carry over between packages.
   - `FB_VERSION_NAME` / `FB_VERSION_CODE` -- default `0.32.0-unity` / `1`
   - `FB_KEYSTORE`, `FB_KEYSTORE_PASS`, `FB_KEY_ALIAS`, `FB_KEY_PASS` -- default is Unity's debug key. **Don't sign
     with the Play upload key, and don't upload to Play:** this is a test build.
   - `FB_DEVELOPMENT=1` -- a development build (adds the profiler and stack traces; useful for the first run).

## What I need back
- `build.log` (Unity's log of the import and build), even when it succeeds -- shader compile warnings are in it.
- After installing on the phone: `adb logcat -s Unity` from launch until the menu (or the crash), and again through
  one match. Lines starting `Fatebound` are the port's own messages (missing shader ports, unknown baked
  properties, unsupported nodes).
- A screenshot of the title screen, of a menu, and of a match.

## Known risks
- **Shaders** (`Assets/Fatebound/Shaders/Resources/Shaders`, `gd/` = the game's own shaders ported) have never been
  compiled. A shader error shows as magenta/invisible geometry and is in build.log.
- **`Assets/Plugins/ZstdSharp/System.Runtime.CompilerServices.Unsafe.dll`**: if Unity reports two assemblies with that
  name, delete this copy.
- IL2CPP strips nothing of the Fatebound assemblies (`Assets/Fatebound/link.xml`); if a build error mentions
  stripping, that file is where to look.
- Platform plugins (Google Play Billing, Play Games, notifications) are not wired yet: the game runs as if they
  were absent.
