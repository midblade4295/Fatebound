// Added for the app/ UI port (ui2.gd sweep(), social_ui.gd, training_pick.gd, screens.gd): CanvasItem.clip_children,
// as canvas_item.h/.cpp -- the mode is stored and marks the canvas for a repaint. NOTE: the renderer (Client) has to
// honour it: CLIP_CHILDREN_ONLY / CLIP_CHILDREN_AND_DRAW clip the children to this item's drawn alpha (the mask), the
// _AND_DRAW one drawing the item itself too.
namespace Fatebound.GUI
{
    public enum ClipChildrenMode { Disabled = 0, Only = 1, AndDraw = 2 }

    public abstract partial class CanvasItem
    {
        public const ClipChildrenMode CLIP_CHILDREN_DISABLED = ClipChildrenMode.Disabled, CLIP_CHILDREN_ONLY = ClipChildrenMode.Only,
            CLIP_CHILDREN_AND_DRAW = ClipChildrenMode.AndDraw;

        ClipChildrenMode _clipChildren = ClipChildrenMode.Disabled;

        /// <summary>clip_children (set_clip_children_mode / get_clip_children_mode).</summary>
        public ClipChildrenMode ClipChildren
        {
            get => _clipChildren;
            set
            {
                if (_clipChildren == value) return;
                _clipChildren = value;
                QueueRepaint();
            }
        }
    }
}
