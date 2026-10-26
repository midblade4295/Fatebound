// Fatebound (Unity port): the GUI framework's engine side -- res:// files from Resources/res (TextAssets for fonts
// and json, Texture2D for images), CPU images uploaded as textures (RGBA32, or Alpha8 for the glyph atlas).
using System.Collections.Generic;
using Fatebound.GUI;
using UnityEngine;
using GImage = Fatebound.GUI.Image;

namespace Fatebound.Client
{
    public sealed class UnityGuiHost : IGuiHost
    {
        readonly Dictionary<string, UnityEngine.Texture2D> _textures = new Dictionary<string, UnityEngine.Texture2D>();

        /// <summary>res://assets/ui/x.png -&gt; "res/assets/ui/x" (Resources paths have no extension).</summary>
        public static string ResourcesPath(string resPath, bool keepExtension = false)
        {
            string p = resPath.StartsWith("res://") ? resPath.Substring(6) : resPath.TrimStart('/');
            if (!keepExtension)
            {
                int dot = p.LastIndexOf('.');
                int slash = p.LastIndexOf('/');
                if (dot > slash) p = p.Substring(0, dot);
            }
            return "res/" + p;
        }

        public byte[] ReadFile(string resPath)
        {
            // fonts are stored as <name>.ttf.bytes (the TextAsset's name keeps the font's extension)
            var ta = Resources.Load<TextAsset>(ResourcesPath(resPath, true)) ?? Resources.Load<TextAsset>(ResourcesPath(resPath));
            return ta != null ? ta.bytes : null;
        }

        public bool FileExists(string resPath)
        {
            string p = ResourcesPath(resPath);
            return Resources.Load(p) != null || Resources.Load(ResourcesPath(resPath, true)) != null;
        }

        public bool LoadTexture(string resPath, out int width, out int height, out object handle)
        {
            if (!_textures.TryGetValue(resPath, out var t))
            {
                t = Resources.Load<UnityEngine.Texture2D>(ResourcesPath(resPath));
                _textures[resPath] = t;
            }
            width = t != null ? t.width : 0;
            height = t != null ? t.height : 0;
            handle = t;
            return t != null;
        }

        public object UploadImage(GImage img, object previous, bool linearFilter, bool repeat)
        {
            var fmt = img.AlphaOnly ? TextureFormat.Alpha8 : TextureFormat.RGBA32;
            var t = previous as UnityEngine.Texture2D;
            if (t == null || t.width != img.Width || t.height != img.Height || t.format != fmt)
            {
                if (t != null) Object.Destroy(t);
                // glyph atlases hold distances (linear data); images are sRGB like Godot's
                t = new UnityEngine.Texture2D(img.Width, img.Height, fmt, false, img.AlphaOnly);
                t.hideFlags = HideFlags.DontSave;
            }
            t.filterMode = linearFilter ? FilterMode.Bilinear : FilterMode.Point;
            t.wrapMode = repeat ? TextureWrapMode.Repeat : TextureWrapMode.Clamp;
            // Godot images are top-down, Unity textures bottom-up (the GUI mesh flips v for every texture)
            int row = img.Width * (img.AlphaOnly ? 1 : 4);
            var flipped = new byte[img.Data.Length];
            for (int y = 0; y < img.Height; y++) System.Buffer.BlockCopy(img.Data, y * row, flipped, (img.Height - 1 - y) * row, row);
            t.LoadRawTextureData(flipped);
            t.Apply(false, false);
            return t;
        }

        public void ReleaseTexture(object handle)
        {
            if (handle is UnityEngine.Texture2D t) Object.Destroy(t);
        }
    }
}
