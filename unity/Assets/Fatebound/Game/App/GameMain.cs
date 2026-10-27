// The game's start, as Godot runs project.godot: the autoloads ([autoload] BootGuard) are added to the root first,
// then the main scene (run/main_scene = res://scenes/Boot.tscn: a full-rect Control named "Boot" running
// content_loader.gd) becomes the current scene. Called once by the Unity client after it created the SceneTree.
// The two scenes are one scripted node each, built here (ResourceLoader.RegisterScene) rather than baked:
// content_loader.gd changes to scenes/Main.tscn (a full-rect Control named "Main" running siege_app.gd) and reloads
// Boot.tscn when a content pack won't mount. The port adds its frame-rate counter (FpsCounter) over them.
using Fatebound.GUI;

namespace Fatebound.Game
{
    public static class GameMain
    {
        public const string BOOT_SCENE = "res://scenes/Boot.tscn";
        public const string MAIN_SCENE = "res://scenes/Main.tscn";

        static T FullRect<T>(T c, string name) where T : Control
        {
            c.Name = name;
            c.SetAnchorsPreset(Control.PRESET_FULL_RECT);
            c.GrowHorizontal = Control.GROW_DIRECTION_BOTH;
            c.GrowVertical = Control.GROW_DIRECTION_BOTH;
            return c;
        }

        public static void Start(SceneTree tree)
        {
            ResourceLoader.RegisterScene(BOOT_SCENE, () => FullRect(new ContentLoader(), "Boot"));
            ResourceLoader.RegisterScene(MAIN_SCENE, () => FullRect(new SiegeApp(), "Main"));
            var guard = new BootGuard();
            guard.Name = "BootGuard";
            tree.Root.AddChild(guard);
            var boot = ResourceLoader.Load<PackedScene>(BOOT_SCENE).Instantiate();
            tree.Root.AddChild(boot);
            tree.CurrentScene = boot;
            tree.Root.AddChild(new FpsCounter());      // (the port's test builds: the frame rate on screen)
        }
    }
}
