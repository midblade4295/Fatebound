// The IGuiHost for tests: res:// files from the synced Unity Resources folder (Assets/Resources/res), images decoded
// with the PNG codec here (jpg converted to png once with Pillow into a cache).
using System;
using System.Collections.Generic;
using System.IO;
using Fatebound.GUI;

namespace GuiTest
{
    public sealed class TestHost : IGuiHost
    {
        public static readonly string Root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../home/claude/midblade4295/fatebound"));
        public readonly string ResDir;
        public readonly string Cache = "/tmp/fb-guitest/cache";
        readonly Dictionary<string, RgbaImage> _images = new Dictionary<string, RgbaImage>();

        public TestHost(string repoRoot)
        {
            ResDir = Path.Combine(repoRoot, "unity", "Assets", "Resources", "res");
            Directory.CreateDirectory(Cache);
        }

        string Local(string resPath)
        {
            string rel = resPath.StartsWith("res://") ? resPath.Substring(6) : resPath;
            return Path.Combine(ResDir, rel);
        }

        public byte[] ReadFile(string resPath)
        {
            string p = Local(resPath);
            if (File.Exists(p)) return File.ReadAllBytes(p);
            if (File.Exists(p + ".bytes")) return File.ReadAllBytes(p + ".bytes");
            return null;
        }

        public bool FileExists(string resPath)
        {
            string p = Local(resPath);
            if (File.Exists(p) || File.Exists(p + ".bytes")) return true;
            string stem = Path.Combine(Path.GetDirectoryName(p), Path.GetFileNameWithoutExtension(p));
            return File.Exists(stem + ".png");
        }

        public RgbaImage Image(string resPath)
        {
            if (_images.TryGetValue(resPath, out var im)) return im;
            string p = Local(resPath);
            string ext = Path.GetExtension(p).ToLowerInvariant();
            string stem = Path.Combine(Path.GetDirectoryName(p), Path.GetFileNameWithoutExtension(p));
            if (ext == ".webp" || ext == ".svg") p = stem + ".png";
            if (ext == ".jpg" || ext == ".jpeg")
            {
                string c = Path.Combine(Cache, resPath.Replace("res://", "").Replace('/', '_') + ".png");
                if (!File.Exists(c))
                {
                    var psi = new System.Diagnostics.ProcessStartInfo("python3", $"-c \"from PIL import Image; Image.open('{p}').convert('RGBA').save('{c}')\"");
                    System.Diagnostics.Process.Start(psi).WaitForExit();
                }
                p = c;
            }
            if (!File.Exists(p)) return null;
            im = Png.Decode(File.ReadAllBytes(p));
            _images[resPath] = im;
            return im;
        }

        public bool LoadTexture(string resPath, out int width, out int height, out object handle)
        {
            var im = Image(resPath);
            width = im?.W ?? 0;
            height = im?.H ?? 0;
            handle = im;
            return im != null;
        }

        public object UploadImage(Image img, object previous, bool linearFilter, bool repeat)
        {
            var r = previous as RgbaImage ?? new RgbaImage(img.Width, img.Height);
            if (r.W != img.Width || r.H != img.Height) r = new RgbaImage(img.Width, img.Height);
            if (img.AlphaOnly)
            {
                for (int i = 0; i < img.Width * img.Height; i++) { r.Px[i * 4] = 255; r.Px[i * 4 + 1] = 255; r.Px[i * 4 + 2] = 255; r.Px[i * 4 + 3] = img.Data[i]; }
            }
            else Array.Copy(img.Data, r.Px, Math.Min(img.Data.Length, r.Px.Length));
            return r;
        }

        public void ReleaseTexture(object handle) { }
    }
}
