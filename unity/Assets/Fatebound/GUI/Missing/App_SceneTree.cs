// Facade additions for the app shell's port (app/siege_app.gd, app/content_loader.gd), as scene/main/scene_tree.cpp and
// node.h:
//  - SceneTree.change_scene_to_file / change_scene_to_packed: load the PackedScene (ERR_CANT_OPEN if it won't), instantiate
//    it (ERR_CANT_CREATE), then change_scene_to_node
//  - SceneTree.auto_accept_quit (stored: the Unity host reads it for a window close request)
//  - SceneTree.get_nodes_in_group (the group's nodes in tree order, as Godot sorts a group before handing it out)
//  - SceneTree.get_script() (the port's tree never has a script attached: null -- the .gd's "not under tests and tools")
//  - SceneTree.reload_current_scene, Node.scene_file_path, Node.get_process_delta_time
//  - Node.NOTIFICATION_WM_CLOSE_REQUEST (1006)
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial class SceneTree
    {
        public bool AutoAcceptQuit = true;

        public int ChangeSceneToFile(string path)
        {
            var scene = ResourceLoader.Load(path) as PackedScene;
            if (scene == null) return GD.ERR_CANT_OPEN;
            return ChangeSceneToPacked(scene);
        }

        public int ChangeSceneToPacked(PackedScene scene)
        {
            if (scene == null)
            {
                GD.PushError("Can't change to a null scene. Use unload_current_scene() if you wish to unload it.");
                return GD.ERR_INVALID_PARAMETER;
            }
            var node = scene.Instantiate();
            if (node == null) return GD.ERR_CANT_CREATE;
            ChangeSceneToNode(node);
            return GD.OK;
        }

        public List<Node> GetNodesInGroup(string group)
        {
            var o = new List<Node>();
            foreach (var n in TreeOrder())
                if (n.IsInGroup(group)) o.Add(n);
            return o;
        }

        public object GetScript() => null;

        /// <summary>reload_current_scene(): change_scene_to_file of the current scene's scene_file_path (ERR_UNCONFIGURED
        /// without a current scene; ERR_CANT_OPEN when it has no file).</summary>
        public int ReloadCurrentScene()
        {
            if (CurrentScene == null) return GD.ERR_UNCONFIGURED;
            string path = CurrentScene.SceneFilePath ?? "";
            if (path == "") return GD.ERR_CANT_OPEN;
            return ChangeSceneToFile(path);
        }
    }

    public partial class Node
    {
        public const int NOTIFICATION_WM_CLOSE_REQUEST = 1006;
        /// <summary>scene_file_path: the scene file this node was instantiated from ("" when it wasn't).</summary>
        public string SceneFilePath = "";

        /// <summary>get_process_delta_time(): this frame's process step.</summary>
        public double GetProcessDeltaTime() => GetTree()?.ProcessDelta ?? 0.0;
    }
}
