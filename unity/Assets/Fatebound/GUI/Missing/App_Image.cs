// Facade addition for the app's port (app/war_land_view.gd): Image.is_compressed() / decompress() (core/io/image.cpp).
// The facade's Image holds only uncompressed formats (ImageFormat: L8 ... RGBAF, every one kept as RGBA8 bytes), so
// is_compressed() is false and decompress() has nothing it can decompress: ERR_UNAVAILABLE, as Godot's for such a format.
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public sealed partial class Image
    {
        public bool IsCompressed() => false;
        public int Decompress() => GD.ERR_UNAVAILABLE;
    }
}
