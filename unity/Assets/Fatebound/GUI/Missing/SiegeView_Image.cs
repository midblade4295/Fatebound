// Facade addition for the siege view's port (siege_view.gd _foliage_ok reads the baked path mask with it):
// Image.get_pixelv(point) -- core/io/image.cpp: get_pixel(point.x, point.y).
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public sealed partial class Image
    {
        public Col GetPixelv(Vec2i p) => GetPixel(p.x, p.y);
    }
}
