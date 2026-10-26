// Unity's entry point: after the (empty) boot scene loads, create the GUI host (SceneTree, input, drawing, the 3D
// renderer) and start the game the way Godot starts project.godot (Fatebound.Game.GameMain).
using UnityEngine;

namespace Fatebound.Client
{
    public static class Boot
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Start()
        {
            if (GuiCanvas.Instance != null) return;
            Application.runInBackground = false;
            // Godot's math error checks (MATH_CHECKS, debug templates only) stay on: the Godot builds the game shipped
            // were debug exports (godot/tools/build_siege_preview.sh: --export-debug), so their fallbacks are the game's
            Fatebound.Sim.GD.MathChecks = true;
            Screen.sleepTimeout = SleepTimeout.SystemSetting;
            var gui = GuiCanvas.Create();
            Fatebound.Game.GameMain.Start(gui.Tree);
        }
    }
}
