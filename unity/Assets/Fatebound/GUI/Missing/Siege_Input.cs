// Facade additions for the siege/ port (siege_hud.gd move_vector / block_held / ability_held / attack_held):
//  - Input.get_action_strength(action) / get_axis(negative, positive) (core/input/input.cpp: get_axis is
//    get_action_strength(positive) - get_action_strength(negative); a digital action's strength is 1 while pressed)
//  - Input.is_physical_key_pressed(key): Godot keeps a set of the physical keycodes held. The facade's Input tracks the
//    held keys by keycode only (Input.Parse, Core/Input.cs) -- this answers from that set, the same key on a QWERTY
//    layout (the Unity client sends no physical keycodes: its key events are the virtual keyboard's typing).
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public static partial class Input
    {
        /// <summary>get_action_strength(action): 1.0 while the (digital) action is pressed, else 0.</summary>
        public static double GetActionStrength(string action) => IsActionPressed(action) ? 1.0 : 0.0;

        /// <summary>get_axis(negative, positive): get_action_strength(positive) - get_action_strength(negative).</summary>
        public static double GetAxis(string negativeAction, string positiveAction) =>
            GetActionStrength(positiveAction) - GetActionStrength(negativeAction);

        /// <summary>is_physical_key_pressed(key) -- see the note at the top of this file.</summary>
        public static bool IsPhysicalKeyPressed(Key k) => IsKeyPressed(k);
    }
}
