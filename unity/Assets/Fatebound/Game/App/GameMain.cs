// The game's start, as Godot runs project.godot: the autoloads ([autoload] BootGuard) are added to the root first,
// then the main scene (run/main_scene = res://scenes/Boot.tscn: a full-rect Control named "Boot" running
// content_loader.gd) becomes the current scene. Called once by the Unity client after it created the SceneTree.
using Fatebound.GUI;

namespace Fatebound.Game
{
    public static class GameMain
    {
        public static void Start(SceneTree tree)
        {
            var guard = new BootGuard();
            guard.Name = "BootGuard";
            tree.Root.AddChild(guard);
            // scenes/Boot.tscn
            var boot = new ContentLoader();
            boot.Name = "Boot";
            boot.SetAnchorsPreset(Control.PRESET_FULL_RECT);
            boot.GrowHorizontal = Control.GROW_DIRECTION_BOTH;
            boot.GrowVertical = Control.GROW_DIRECTION_BOTH;
            tree.Root.AddChild(boot);
            tree.CurrentScene = boot;
        }
    }
}
