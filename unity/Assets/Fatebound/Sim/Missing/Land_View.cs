// Sim addition for the siege view's port (no rule changes): siege_land.gd's baked-terrain paths and its bake_key(),
// which siege_view.gd checks the baked start-up cache (assets/terrain/cache.res) against.
namespace Fatebound.Sim
{
    public static partial class Land
    {
        public const string HEIGHT_RES = "res://assets/terrain/height.res";
        public const string MASK_RES = "res://assets/terrain/pathmask.res";

        /// <summary>bake_key(): str(hash(str(parts))) of the land's shape data in siege_land.gd. The Godot game is frozen
        /// at 0.31.222 and this port's land is that land, so the key is Godot's own value for it (printed by Godot 4.7.2
        /// from siege_land.gd, and the key stored in the baked cache.res): a changed land needs a new bake and a new key.</summary>
        public static string BakeKey() => "633754923";
    }
}
