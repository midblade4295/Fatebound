// Fatebound GUI (Unity port): Godot's resources the UI code uses -- textures (loaded, ImageTexture, AtlasTexture,
// GradientTexture1D/2D, a SubViewport's texture), Image, Gradient, Curve, and load()/preload() through the host.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial class Resource
    {
        public string ResourcePath = "";
        public string ResourceName = "";
        public event Action Changed;
        public void EmitChanged() { version++; Changed?.Invoke(); }
        public int version;
        public virtual Resource Duplicate(bool deep = false) => (Resource)MemberwiseClone();

        /// <summary>Godot's _set for stored properties with dynamic names ("tracks/0/keys", "bones/3/rest",
        /// "bind/2/pose"...): the baked-asset loader calls it first; true = handled. Plain properties are set by name
        /// (snake_case -> the C# property) when this returns false.</summary>
        public virtual bool SetStoredProperty(string name, Fatebound.Sim.Var value) => false;
    }

    /// <summary>What the engine side provides: file bytes and GPU textures by res:// path, and texture uploads.</summary>
    public interface IGuiHost
    {
        /// <summary>Raw bytes of a res:// file (fonts, json), or null.</summary>
        byte[] ReadFile(string resPath);
        bool FileExists(string resPath);
        /// <summary>Size and engine handle of an image file (png/jpg/webp converted at sync time), or false.</summary>
        bool LoadTexture(string resPath, out int width, out int height, out object handle);
        /// <summary>Creates or refreshes the engine texture of a CPU image (ImageTexture, gradients, glyph atlases).</summary>
        object UploadImage(Image img, object previous, bool linearFilter, bool repeat);
        void ReleaseTexture(object handle);
    }

    public static partial class ResourceLoader
    {
        public static IGuiHost Host;
        static readonly Dictionary<string, WeakReference<Resource>> _cache = new Dictionary<string, WeakReference<Resource>>();
        static readonly Dictionary<string, Resource> _pinned = new Dictionary<string, Resource>();

        public static string Normalize(string path)
        {
            if (path == null) return "";
            if (!path.StartsWith("res://") && !path.StartsWith("user://")) path = "res://" + path.TrimStart('/');
            return path;
        }

        public static bool Exists(string path)
        {
            path = Normalize(path);
            lock (_codeScenes) if (_codeScenes.ContainsKey(path)) return true;
#if FB3D
            // baked scenes/resources: answered from the bake's manifest (the host would load the whole file to tell)
            if (BakedLoader.Handles(path)) { bool? b = BakedLoader.InManifest(path); if (b.HasValue) return b.Value; }
#endif
            return Host != null && Host.FileExists(path);
        }

        /// <summary>load(path): cached like Godot's resource cache.</summary>
        public static Resource Load(string path)
        {
            path = Normalize(path);
            lock (_cache)
            {
                if (_pinned.TryGetValue(path, out var p)) return p;
                if (_cache.TryGetValue(path, out var w) && w.TryGetTarget(out var r)) return r;
            }
            if (JoinThreadLoad(path, out var threaded)) return threaded;       // (being loaded by load_threaded_request)
            Resource res = LoadUncached(path);
            if (res == null) return null;
            res.ResourcePath = path;
            lock (_cache)
            {
                _cache[path] = new WeakReference<Resource>(res);
                if (res is Font) _pinned[path] = res;
            }
            return res;
        }

        public static T Load<T>(string path) where T : Resource => Load(path) as T;

        static readonly Dictionary<string, Func<Node>> _codeScenes = new Dictionary<string, Func<Node>>();

        /// <summary>A scene the port builds in code rather than bakes (scenes/Boot.tscn, scenes/Main.tscn: one scripted node
        /// each): load(path) gives a PackedScene whose instantiate() calls make, and the node it makes has path as its
        /// scene_file_path (SceneTree.reload_current_scene).</summary>
        public static void RegisterScene(string path, Func<Node> make)
        {
            lock (_codeScenes) _codeScenes[Normalize(path)] = make;
        }

        static Resource LoadUncached(string path)
        {
#if FB3D
            Func<Node> make;
            lock (_codeScenes) _codeScenes.TryGetValue(path, out make);
            if (make != null) return PackedScene.FromCode(path, make);
#endif
            string ext = System.IO.Path.GetExtension(path).ToLowerInvariant();
#if FB3D
            // .glb .gltf .scn .tscn .res .tres: baked by tools/bake (any thread: the bytes come through the main thread)
            if (BakedLoader.Handles(path)) return BakedLoader.Load(path);
#endif
            bool texture = ext == ".png" || ext == ".jpg" || ext == ".jpeg" || ext == ".webp" || ext == ".svg" || ext == ".bmp" || ext == ".tga";
            // off the main thread (a threaded load's dependency): textures resolve on first use, the rest via the main thread
            if (!PlatformHost.IsMainThread)
                return texture ? new LoadedTexture(path) : OnMainThread(() => LoadUncached(path));
            switch (ext)
            {
                case ".ttf":
                case ".otf":
                case ".woff2":
                case ".woff":
                    return FontFile.LoadFromHost(path);
                case ".gdshader":
                    return Shader.Get(path);
                // audio: the clip itself is loaded by the host on first use (AudioStream.Clip, main thread)
                case ".ogg":
                    return new AudioStreamOggVorbis();
                case ".mp3":
                    return new AudioStreamMP3();
                case ".wav":
                    return new AudioStreamWAV();
                case ".png":
                case ".jpg":
                case ".jpeg":
                case ".webp":
                case ".svg":
                case ".bmp":
                case ".tga":
                    if (Host != null && Host.LoadTexture(path, out int w, out int h, out object handle))
                        return new LoadedTexture(path, w, h, handle);
                    GD_Log.Error("load: no texture " + path);
                    return null;
                default:
                    GD_Log.Error("load: unsupported resource " + path);
                    return null;
            }
        }
    }

    // ---------- textures ----------
    public abstract partial class Texture2D : Resource
    {
        public abstract int GetWidth();
        public abstract int GetHeight();
        public Vec2 GetSize() => new Vec2(GetWidth(), GetHeight());
        /// <summary>The host's texture object to bind.</summary>
        public abstract object GetHandle();
        /// <summary>Texture actually bound when drawing this one (an AtlasTexture binds its atlas).</summary>
        public virtual Texture2D BoundTexture() => this;
        /// <summary>Maps a 0..1 uv of this texture to the bound texture's uv.</summary>
        public virtual Vec2 MapUV(Vec2 uv) => uv;
        public virtual Image GetImage() => null;
        public virtual bool HasAlpha() => true;
        /// <summary>Whether sampling repeats (tiled draws, gradient repeat).</summary>
        public bool repeat;
        public bool linearFilter = true;
    }

    public sealed partial class LoadedTexture : Texture2D
    {
        int _w, _h;
        object _handle;
        volatile bool _pending;
        public LoadedTexture(string path, int w, int h, object handle) { ResourcePath = path; _w = w; _h = h; _handle = handle; }

        /// <summary>A texture loaded off the main thread (a threaded load's dependency): the host loads it on first use
        /// (on the main thread; a use from another thread waits for it there).</summary>
        public LoadedTexture(string path) { ResourcePath = path; _pending = true; }

        void Resolve()
        {
            if (!_pending) return;
            lock (this)
            {
                if (!_pending) return;
                string path = ResourcePath;
                ResourceLoader.OnMainThread(() =>
                {
                    if (ResourceLoader.Host == null || !ResourceLoader.Host.LoadTexture(path, out _w, out _h, out _handle))
                        GD_Log.Error("load: no texture " + path);
                    return true;
                });
                _pending = false;
            }
        }

        public override int GetWidth() { Resolve(); return _w; }
        public override int GetHeight() { Resolve(); return _h; }
        public override object GetHandle() { Resolve(); return _handle; }
    }

    /// <summary>A texture whose pixels live on the CPU (ImageTexture, gradients, glyph atlases): uploaded when changed.</summary>
    public abstract partial class CpuTexture : Texture2D
    {
        object _handle;
        int _uploaded = -1;
        protected abstract Image BuildImage();
        protected int pixelsVersion;
        Image _img;

        public void MarkDirty() { pixelsVersion++; _img = null; EmitChanged(); }

        public override Image GetImage()
        {
            if (_img == null) _img = BuildImage();
            return _img;
        }

        public override object GetHandle()
        {
            if (_uploaded != pixelsVersion || _handle == null)
            {
                var img = GetImage();
                if (img != null && ResourceLoader.Host != null) _handle = ResourceLoader.Host.UploadImage(img, _handle, linearFilter, repeat);
                _uploaded = pixelsVersion;
            }
            return _handle;
        }

        ~CpuTexture()
        {
            if (_handle != null) MainThread.Post(h => ResourceLoader.Host?.ReleaseTexture(h), _handle);
        }
    }

    /// <summary>Work that must run on the main thread (texture release from a finalizer).</summary>
    public static partial class MainThread
    {
        static readonly List<(Action<object>, object)> _q = new List<(Action<object>, object)>();
        public static void Post(Action<object> a, object arg) { lock (_q) _q.Add((a, arg)); }

        public static void Flush()
        {
            (Action<object>, object)[] items;
            lock (_q)
            {
                if (_q.Count == 0) return;
                items = _q.ToArray();
                _q.Clear();
            }
            foreach (var (a, o) in items) a(o);
        }
    }

    public sealed partial class ImageTexture : CpuTexture
    {
        Image _src;
        public static ImageTexture CreateFromImage(Image img)
        {
            var t = new ImageTexture();
            t.SetImage(img);
            return t;
        }

        public void SetImage(Image img) { _src = img; MarkDirty(); }
        public void Update(Image img) { _src = img; MarkDirty(); }
        protected override Image BuildImage() => _src;
        public override int GetWidth() => _src?.Width ?? 0;
        public override int GetHeight() => _src?.Height ?? 0;
        public void SetSizeOverride(Vec2 s) { }
    }

    public sealed partial class AtlasTexture : Texture2D
    {
        public Texture2D atlas;
        public Rect2 region;
        public Rect2 margin;
        public bool filterClip;

        public Texture2D Atlas { get => atlas; set => atlas = value; }
        public Rect2 Region { get => region; set => region = value; }
        public Rect2 Margin { get => margin; set => margin = value; }

        public override int GetWidth() => (int)(region.size.x + margin.size.x);
        public override int GetHeight() => (int)(region.size.y + margin.size.y);
        public override object GetHandle() => atlas?.GetHandle();
        public override Texture2D BoundTexture() => atlas?.BoundTexture() ?? atlas;

        public override Vec2 MapUV(Vec2 uv)
        {
            if (atlas == null) return uv;
            Vec2 a = atlas.GetSize();
            Vec2 px = region.position + new Vec2(uv.x * region.size.x, uv.y * region.size.y);
            return atlas.MapUV(new Vec2(px.x / a.x, px.y / a.y));
        }
    }

    /// <summary>A SubViewport's render target as seen by the UI (the host fills the handle).</summary>
    /// <summary>A viewport's picture (SubViewport.get_texture()): the renderer sets `handle` to its render texture.</summary>
    public sealed partial class ViewportTexture : Texture2D
    {
        public int width = 1, height = 1;
        public object handle;
        public Viewport viewport;
        /// <summary>Asks the host for the viewport's current texture (the Unity renderer resolves it from BackendData).</summary>
        public static Func<ViewportTexture, object> Resolve;
#if FB3D
        public override int GetWidth() => viewport is SubViewport sv ? sv.Size.x : viewport != null ? (int)viewport.Get3DSize().x : width;
        public override int GetHeight() => viewport is SubViewport sv ? sv.Size.y : viewport != null ? (int)viewport.Get3DSize().y : height;
#else
        public override int GetWidth() => width;
        public override int GetHeight() => height;
#endif
        public override object GetHandle() => Resolve != null ? Resolve(this) ?? handle : handle;
    }

    public sealed partial class PlaceholderTexture2D : Texture2D
    {
        public Vec2 Size = new Vec2(1, 1);
        public override int GetWidth() => (int)Size.x;
        public override int GetHeight() => (int)Size.y;
        public override object GetHandle() => null;
    }

    // ---------- Image ----------
    public enum ImageFormat { L8 = 0, LA8 = 1, R8 = 2, RG8 = 3, RGB8 = 4, RGBA8 = 5, RF = 8, RGBAF = 11 }

    /// <summary>Godot's Image, kept as RGBA floats-free bytes (every format stored as RGBA8).</summary>
    public sealed partial class Image : Resource
    {
        public int Width, Height;
        public byte[] Data;
        public ImageFormat Format = ImageFormat.RGBA8;
        /// <summary>Single-channel images (glyph atlases) keep one byte per pixel.</summary>
        public bool AlphaOnly;

        public static Image Create(int w, int h, bool mipmaps, ImageFormat format)
        {
            var img = new Image { Width = Math.Max(1, w), Height = Math.Max(1, h), Format = format };
            img.Data = new byte[img.Width * img.Height * 4];
            return img;
        }

        public static Image CreateEmpty(int w, int h, bool mipmaps, ImageFormat format) => Create(w, h, mipmaps, format);

        public static Image CreateAlpha(int w, int h)
        {
            return new Image { Width = w, Height = h, AlphaOnly = true, Format = ImageFormat.R8, Data = new byte[w * h] };
        }

        public static Image CreateFromData(int w, int h, bool mipmaps, ImageFormat format, byte[] data)
        {
            var img = Create(w, h, mipmaps, ImageFormat.RGBA8);
            int n = w * h;
            switch (format)
            {
                case ImageFormat.RGBA8: Array.Copy(data, img.Data, Math.Min(data.Length, n * 4)); break;
                case ImageFormat.RGB8:
                    for (int i = 0; i < n; i++) { img.Data[i * 4] = data[i * 3]; img.Data[i * 4 + 1] = data[i * 3 + 1]; img.Data[i * 4 + 2] = data[i * 3 + 2]; img.Data[i * 4 + 3] = 255; }
                    break;
                case ImageFormat.L8:
                case ImageFormat.R8:
                    for (int i = 0; i < n; i++) { byte v = data[i]; img.Data[i * 4] = v; img.Data[i * 4 + 1] = format == ImageFormat.L8 ? v : (byte)0; img.Data[i * 4 + 2] = format == ImageFormat.L8 ? v : (byte)0; img.Data[i * 4 + 3] = 255; }
                    break;
                case ImageFormat.LA8:
                    for (int i = 0; i < n; i++) { byte v = data[i * 2]; img.Data[i * 4] = v; img.Data[i * 4 + 1] = v; img.Data[i * 4 + 2] = v; img.Data[i * 4 + 3] = data[i * 2 + 1]; }
                    break;
                default: throw new NotSupportedException("Image format " + format);
            }
            return img;
        }

        public int GetWidth() => Width;
        public int GetHeight() => Height;
        public Vec2 GetSize() => new Vec2(Width, Height);
        public byte[] GetData() => Data;

        static byte B(float v) => (byte)Math.Round(Math.Max(0f, Math.Min(1f, v)) * 255f);

        public void SetPixel(int x, int y, Col c)
        {
            if (x < 0 || y < 0 || x >= Width || y >= Height) return;
            if (AlphaOnly) { Data[y * Width + x] = B(c.a); return; }
            int i = (y * Width + x) * 4;
            if (Format == ImageFormat.RF) { WriteRF(i, c.r); return; }      // (baked FORMAT_RF images: raw floats, see SetStoredProperty)
            Data[i] = B(c.r); Data[i + 1] = B(c.g); Data[i + 2] = B(c.b); Data[i + 3] = B(c.a);
        }

        public void SetPixelv(Vec2i p, Col c) => SetPixel(p.x, p.y, c);

        public Col GetPixel(int x, int y)
        {
            if (x < 0 || y < 0 || x >= Width || y >= Height) return new Col(0f, 0f, 0f, 0f);
            if (AlphaOnly) return new Col(1f, 1f, 1f, Data[y * Width + x] / 255f);
            int i = (y * Width + x) * 4;
            if (Format == ImageFormat.RF) return new Col(BitConverter.ToSingle(Data, i), 0f, 0f, 1f);
            return new Col(Data[i] / 255f, Data[i + 1] / 255f, Data[i + 2] / 255f, Data[i + 3] / 255f);
        }

        public void Fill(Col c)
        {
            for (int y = 0; y < Height; y++)
                for (int x = 0; x < Width; x++) SetPixel(x, y, c);
        }

        public void FillRect(Rect2 r, Col c)
        {
            int x0 = Math.Max(0, (int)r.position.x), y0 = Math.Max(0, (int)r.position.y);
            int x1 = Math.Min(Width, (int)(r.position.x + r.size.x)), y1 = Math.Min(Height, (int)(r.position.y + r.size.y));
            for (int y = y0; y < y1; y++)
                for (int x = x0; x < x1; x++) SetPixel(x, y, c);
        }

        public bool IsEmpty() => Data == null || Width == 0 || Height == 0;

        void WriteRF(int i, float v)
        {
            byte[] b = BitConverter.GetBytes(v);
            Data[i] = b[0]; Data[i + 1] = b[1]; Data[i + 2] = b[2]; Data[i + 3] = b[3];
        }

        /// <summary>Godot's stored "data" ({width, height, format (Image::format_names), mipmaps, data}) -- the baked-asset
        /// loader (Image resources: assets/terrain/height.res, pathmask.res, the cache's blood splats). 8-bit formats become
        /// RGBA8 as everywhere in this Image; FORMAT_RF ("RFloat", the height map) keeps its raw floats (get_data() is what
        /// Godot's is: the game reads it with to_float32_array()). Mipmaps are dropped (only the base level is kept).</summary>
        public override bool SetStoredProperty(string name, Var value)
        {
            if (name != "data") return false;
            var d = value.AsDict();
            if (d == null || !d.Has("width") || !d.Has("height") || !d.Has("format") || !d.Has("data")) { GD_Log.Error("Image: bad stored data."); return true; }
            int w = d["width"].AsInt(), h = d["height"].AsInt();
            var bytes = d["data"].Obj as byte[] ?? Array.Empty<byte>();
            string f = d["format"].AsString();
            AlphaOnly = false;
            Width = w;
            Height = h;
            switch (f)
            {
                case "RFloat":
                    Format = ImageFormat.RF;
                    Data = new byte[w * h * 4];
                    Array.Copy(bytes, Data, Math.Min(bytes.Length, Data.Length));
                    break;
                case "Lum8": case "LumAlpha8": case "Red8": case "RGB8": case "RGBA8":
                {
                    var fmt = f == "Lum8" ? ImageFormat.L8 : f == "LumAlpha8" ? ImageFormat.LA8 : f == "Red8" ? ImageFormat.R8 : f == "RGB8" ? ImageFormat.RGB8 : ImageFormat.RGBA8;
                    var img = CreateFromData(w, h, false, fmt, bytes);
                    Data = img.Data;
                    Format = ImageFormat.RGBA8;
                    break;
                }
                default:
                    GD_Log.Error("Image: stored format " + f + " is not supported by the port.");
                    Data = new byte[w * h * 4];
                    Format = ImageFormat.RGBA8;
                    break;
            }
            EmitChanged();
            return true;
        }
        public void GenerateMipmaps() { }
        public void Convert(ImageFormat f) { }

        public void Resize(int w, int h, int interpolation = 1)
        {
            var o = Create(w, h, false, ImageFormat.RGBA8);
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    float sx = (x + 0.5f) * Width / w - 0.5f, sy = (y + 0.5f) * Height / h - 0.5f;
                    o.SetPixel(x, y, interpolation == 0 ? GetPixel((int)Math.Round(sx), (int)Math.Round(sy)) : Bilinear(sx, sy));
                }
            Width = w; Height = h; Data = o.Data; AlphaOnly = false;
        }

        Col Bilinear(float x, float y)
        {
            int x0 = (int)Math.Floor(x), y0 = (int)Math.Floor(y);
            float fx = x - x0, fy = y - y0;
            Col P(int px, int py) => GetPixel(Math.Max(0, Math.Min(Width - 1, px)), Math.Max(0, Math.Min(Height - 1, py)));
            return P(x0, y0).Lerp(P(x0 + 1, y0), fx).Lerp(P(x0, y0 + 1).Lerp(P(x0 + 1, y0 + 1), fx), fy);
        }

        public Image GetRegion(Rect2 r)
        {
            var o = Create((int)r.size.x, (int)r.size.y, false, ImageFormat.RGBA8);
            for (int y = 0; y < o.Height; y++)
                for (int x = 0; x < o.Width; x++) o.SetPixel(x, y, GetPixel(x + (int)r.position.x, y + (int)r.position.y));
            return o;
        }

        public void BlitRect(Image src, Rect2 srcRect, Vec2i dst)
        {
            for (int y = 0; y < (int)srcRect.size.y; y++)
                for (int x = 0; x < (int)srcRect.size.x; x++)
                    SetPixel(dst.x + x, dst.y + y, src.GetPixel((int)srcRect.position.x + x, (int)srcRect.position.y + y));
        }
    }

    // ---------- Gradient, Curve ----------
    public sealed partial class Gradient : Resource
    {
        public enum InterpolationModeEnum { Linear = 0, Constant = 1, Cubic = 2 }
        public float[] Offsets = { 0f, 1f };
        public Col[] Colors = { Col.BLACK, Col.WHITE };
        public InterpolationModeEnum InterpolationMode = InterpolationModeEnum.Linear;

        void SortPoints()
        {
            var idx = new int[Offsets.Length];
            for (int i = 0; i < idx.Length; i++) idx[i] = i;
            var off = Offsets;
            Array.Sort(idx, (a, b) => off[a] != off[b] ? off[a].CompareTo(off[b]) : a.CompareTo(b));
            var no = new float[idx.Length];
            var nc = new Col[idx.Length];
            for (int i = 0; i < idx.Length; i++) { no[i] = Offsets[idx[i]]; nc[i] = Colors[idx[i]]; }
            Offsets = no;
            Colors = nc;
        }

        public void SetOffsets(IList<double> offs)
        {
            Offsets = new float[offs.Count];
            for (int i = 0; i < offs.Count; i++) Offsets[i] = (float)offs[i];
            if (Colors.Length != Offsets.Length) Array.Resize(ref Colors, Offsets.Length);
            EmitChanged();
        }

        public void SetColors(IList<Col> cols)
        {
            Colors = new Col[cols.Count];
            cols.CopyTo(Colors, 0);
            if (Offsets.Length != Colors.Length) Array.Resize(ref Offsets, Colors.Length);
            EmitChanged();
        }

        public void AddPoint(double offset, Col color)
        {
            Array.Resize(ref Offsets, Offsets.Length + 1);
            Array.Resize(ref Colors, Colors.Length + 1);
            Offsets[Offsets.Length - 1] = (float)offset;
            Colors[Colors.Length - 1] = color;
            SortPoints();
            EmitChanged();
        }

        public void RemovePoint(int i)
        {
            if (i < 0 || i >= Offsets.Length || Offsets.Length <= 1) return;
            var o = new List<float>(Offsets);
            var c = new List<Col>(Colors);
            o.RemoveAt(i);
            c.RemoveAt(i);
            Offsets = o.ToArray();
            Colors = c.ToArray();
            EmitChanged();
        }

        public void SetColor(int i, Col c) { if (i >= 0 && i < Colors.Length) { Colors[i] = c; EmitChanged(); } }
        public void SetOffset(int i, double o) { if (i >= 0 && i < Offsets.Length) { Offsets[i] = (float)o; SortPoints(); EmitChanged(); } }
        public Col GetColor(int i) => Colors[i];
        public double GetOffset(int i) => Offsets[i];
        public int GetPointCount() => Offsets.Length;

        /// <summary>Gradient::get_color_at_offset.</summary>
        public Col Sample(double offset)
        {
            int n = Offsets.Length;
            if (n == 0) return new Col(0f, 0f, 0f, 1f);
            if (n == 1) return Colors[0];
            float o = (float)offset;
            int low = 0, high = n - 1, middle = 0;
            while (low <= high)
            {
                middle = (low + high) / 2;
                if (Offsets[middle] < o) low = middle + 1;
                else if (Offsets[middle] > o) high = middle - 1;
                else return Colors[middle];
            }
            if (Offsets[middle] > o) middle--;
            int first = middle, second = middle + 1;
            if (second >= n) return Colors[n - 1];
            if (first < 0) return Colors[0];
            float d = Offsets[second] - Offsets[first];
            float t = d == 0 ? 0f : (o - Offsets[first]) / d;
            switch (InterpolationMode)
            {
                case InterpolationModeEnum.Constant: return Colors[first];
                case InterpolationModeEnum.Cubic:
                {
                    Col c0 = Colors[Math.Max(first - 1, 0)], c1 = Colors[first], c2 = Colors[second], c3 = Colors[Math.Min(second + 1, n - 1)];
                    float Cub(float a, float b, float pa, float pb) => GD.CubicInterpolateF(a, b, pa, pb, t);
                    return new Col(Cub(c1.r, c2.r, c0.r, c3.r), Cub(c1.g, c2.g, c0.g, c3.g), Cub(c1.b, c2.b, c0.b, c3.b), Cub(c1.a, c2.a, c0.a, c3.a));
                }
                default: return Colors[first].Lerp(Colors[second], t);
            }
        }
    }

    /// <summary>Godot's Curve (scene/resources/curve.cpp): points kept inside the value and domain ranges, the cubic
    /// Bezier with tangents a third of the way, linear tangent modes, the baked cache (bake_resolution 100).</summary>
    public sealed partial class Curve : Resource
    {
        public const int TANGENT_FREE = 0, TANGENT_LINEAR = 1, TANGENT_MODE_COUNT = 2;
        const float MIN_X_RANGE = 0.01f, MIN_Y_RANGE = 0.01f, CMP_EPSILON = 0.00001f;

        public partial struct Point
        {
            public float x, y, leftTangent, rightTangent;
            public int leftMode, rightMode;
        }

        public readonly List<Point> Points = new List<Point>();
        float _minValue = 0f, _maxValue = 1f, _minDomain = 0f, _maxDomain = 1f;
        int _bakeResolution = 100;
        float[] _baked = Array.Empty<float>();
        bool _bakedDirty = true;
        public event Action RangeChanged, DomainChanged;

        void MarkDirty() { _bakedDirty = true; EmitChanged(); }

        public double MinValue
        {
            get => _minValue;
            set
            {
                _minValue = Math.Min((float)value, _maxValue - MIN_Y_RANGE);
                foreach (var p in Points) _minValue = Math.Min(_minValue, p.y);
                RangeChanged?.Invoke();
            }
        }

        public double MaxValue
        {
            get => _maxValue;
            set
            {
                _maxValue = Math.Max((float)value, _minValue + MIN_Y_RANGE);
                foreach (var p in Points) _maxValue = Math.Max(_maxValue, p.y);
                RangeChanged?.Invoke();
            }
        }

        public double MinDomain
        {
            get => _minDomain;
            set
            {
                _minDomain = Math.Min((float)value, _maxDomain - MIN_X_RANGE);
                if (Points.Count > 0 && _minDomain > Points[0].x) _minDomain = Points[0].x;
                MarkDirty();
                DomainChanged?.Invoke();
            }
        }

        public double MaxDomain
        {
            get => _maxDomain;
            set
            {
                _maxDomain = Math.Max((float)value, _minDomain + MIN_X_RANGE);
                if (Points.Count > 0 && _maxDomain < Points[Points.Count - 1].x) _maxDomain = Points[Points.Count - 1].x;
                MarkDirty();
                DomainChanged?.Invoke();
            }
        }

        public double GetValueRange() => _maxValue - _minValue;
        public double GetDomainRange() => _maxDomain - _minDomain;

        public int BakeResolution
        {
            get => _bakeResolution;
            set
            {
                if (value < 1 || value > 1000) { GD_Log.Error("Curve: bake resolution out of range."); return; }
                _bakeResolution = value;
                _bakedDirty = true;
            }
        }

        public int PointCount
        {
            get => Points.Count;
            set
            {
                int n = Math.Max(0, value);
                if (n < Points.Count) Points.RemoveRange(n, Points.Count - n);
                else while (Points.Count < n) Points.Add(new Point());
                MarkDirty();
            }
        }

        public int GetPointCount() => Points.Count;

        int AddPointInternal(Vec2 pos, float left, float right, int leftMode, int rightMode, bool markDirty)
        {
            // Points must remain within the given value and domain ranges.
            float px = Math.Max(_minDomain, Math.Min(_maxDomain, pos.x));
            float py = Math.Max(_minValue, Math.Min(_maxValue, pos.y));
            var pt = new Point { x = px, y = py, leftTangent = left, rightTangent = right, leftMode = leftMode, rightMode = rightMode };
            int ret;
            if (Points.Count == 0)
            {
                Points.Add(pt);
                ret = 0;
            }
            else if (Points.Count == 1)
            {
                float diff = px - Points[0].x;
                if (diff > 0) { Points.Add(pt); ret = 1; }
                else { Points.Insert(0, pt); ret = 0; }
            }
            else
            {
                int i = GetIndex(px);
                if (i == 0 && px < Points[0].x) { Points.Insert(0, pt); ret = 0; }
                else { ++i; Points.Insert(i, pt); ret = i; }
            }
            UpdateAutoTangents(ret);
            if (markDirty) MarkDirty();
            return ret;
        }

        public int AddPoint(Vec2 position, double leftTangent = 0, double rightTangent = 0, int leftMode = TANGENT_FREE, int rightMode = TANGENT_FREE)
            => AddPointInternal(position, (float)leftTangent, (float)rightTangent, leftMode, rightMode, true);

        public int GetIndex(double offset)
        {
            // Lower-bound float binary search.
            float o = (float)offset;
            int imin = 0, imax = Points.Count - 1;
            while (imax - imin > 1)
            {
                int m = (imin + imax) / 2;
                float a = Points[m].x, b = Points[m + 1].x;
                if (a < o && b < o) imin = m;
                else if (a > o) imax = m;
                else return m;
            }
            // Will happen if the offset is out of bounds.
            if (o > Points[imax].x) return imax;
            return imin;
        }

        public void CleanDupes()
        {
            bool dirty = false;
            for (int i = 1; i < Points.Count; ++i)
            {
                float diff = Points[i - 1].x - Points[i].x;
                if (diff <= CMP_EPSILON) { Points.RemoveAt(i); --i; dirty = true; }
            }
            if (dirty) MarkDirty();
        }

        bool Bad(int i)
        {
            if (i >= 0 && i < Points.Count) return false;
            GD_Log.Error("Curve: index " + i + " out of range (" + Points.Count + ").");
            return true;
        }

        static float Slope(Point from, Point to)
        {
            // (to - from).normalized(), then y / x -- as Godot computes it
            float dx = to.x - from.x, dy = to.y - from.y;
            float l = (float)Math.Sqrt(dx * dx + dy * dy);
            if (l != 0f) { dx /= l; dy /= l; }
            return dy / dx;
        }

        public void SetPointLeftTangent(int i, double t)
        {
            if (Bad(i)) return;
            var p = Points[i]; p.leftTangent = (float)t; p.leftMode = TANGENT_FREE; Points[i] = p;
            MarkDirty();
        }

        public void SetPointRightTangent(int i, double t)
        {
            if (Bad(i)) return;
            var p = Points[i]; p.rightTangent = (float)t; p.rightMode = TANGENT_FREE; Points[i] = p;
            MarkDirty();
        }

        public void SetPointLeftMode(int i, int mode)
        {
            if (Bad(i)) return;
            var p = Points[i];
            p.leftMode = mode;
            if (i > 0 && mode == TANGENT_LINEAR) p.leftTangent = Slope(p, Points[i - 1]);
            Points[i] = p;
            MarkDirty();
        }

        public void SetPointRightMode(int i, int mode)
        {
            if (Bad(i)) return;
            var p = Points[i];
            p.rightMode = mode;
            if (i + 1 < Points.Count && mode == TANGENT_LINEAR) p.rightTangent = Slope(p, Points[i + 1]);
            Points[i] = p;
            MarkDirty();
        }

        public double GetPointLeftTangent(int i) => Bad(i) ? 0 : Points[i].leftTangent;
        public double GetPointRightTangent(int i) => Bad(i) ? 0 : Points[i].rightTangent;
        public int GetPointLeftMode(int i) => Bad(i) ? TANGENT_FREE : Points[i].leftMode;
        public int GetPointRightMode(int i) => Bad(i) ? TANGENT_FREE : Points[i].rightMode;
        public Vec2 GetPointPosition(int i) => Bad(i) ? Vec2.Zero : new Vec2(Points[i].x, Points[i].y);

        public void RemovePoint(int i)
        {
            if (Bad(i)) return;
            Points.RemoveAt(i);
            MarkDirty();
        }

        public void ClearPoints()
        {
            if (Points.Count == 0) return;
            Points.Clear();
            MarkDirty();
        }

        public void SetPointValue(int i, double y)
        {
            if (Bad(i)) return;
            var p = Points[i]; p.y = (float)y; Points[i] = p;
            UpdateAutoTangents(i);
            MarkDirty();
        }

        public int SetPointOffset(int index, double offset)
        {
            if (Bad(index)) return -1;
            var p = Points[index];
            Points.RemoveAt(index);
            int i = AddPointInternal(new Vec2((float)offset, p.y), p.leftTangent, p.rightTangent, p.leftMode, p.rightMode, false);
            if (index != i && index < Points.Count) UpdateAutoTangents(index);
            UpdateAutoTangents(i);
            MarkDirty();
            return i;
        }

        void UpdateAutoTangents(int index)
        {
            var p = Points[index];
            if (index > 0)
            {
                if (p.leftMode == TANGENT_LINEAR) p.leftTangent = Slope(p, Points[index - 1]);
                var q = Points[index - 1];
                if (q.rightMode == TANGENT_LINEAR) { q.rightTangent = Slope(p, q); Points[index - 1] = q; }
            }
            if (index + 1 < Points.Count)
            {
                if (p.rightMode == TANGENT_LINEAR) p.rightTangent = Slope(p, Points[index + 1]);
                var q = Points[index + 1];
                if (q.leftMode == TANGENT_LINEAR) { q.leftTangent = Slope(p, q); Points[index + 1] = q; }
            }
            Points[index] = p;
        }

        public double Sample(double offset)
        {
            if (Points.Count == 0) return 0;
            if (Points.Count == 1) return Points[0].y;
            int i = GetIndex(offset);
            if (i == Points.Count - 1) return Points[i].y;
            float local = (float)offset - Points[i].x;
            if (i == 0 && local <= 0) return Points[0].y;
            return SampleLocalNoCheck(i, local);
        }

        public double SampleLocalNoCheck(int index, double localOffset)
        {
            var a = Points[index];
            var b = Points[index + 1];
            // Control points are chosen at equal distances.
            float d = b.x - a.x;
            if (Math.Abs(d) < CMP_EPSILON) return b.y;
            float t = (float)localOffset / d;
            d /= 3f;
            float yac = a.y + d * a.rightTangent;
            float ybc = b.y - d * b.leftTangent;
            // Math::bezier_interpolate
            float omt = 1f - t, omt2 = omt * omt, omt3 = omt2 * omt, t2 = t * t, t3 = t2 * t;
            return a.y * omt3 + yac * omt2 * t * 3f + ybc * omt * t2 * 3f + b.y * t3;
        }

        public void Bake()
        {
            _baked = new float[_bakeResolution];
            for (int i = 1; i < _bakeResolution - 1; ++i)
            {
                float x = (float)GetDomainRange() * i / (float)(_bakeResolution - 1) + _minDomain;
                _baked[i] = (float)Sample(x);
            }
            if (Points.Count != 0)
            {
                _baked[0] = Points[0].y;
                _baked[_baked.Length - 1] = Points[Points.Count - 1].y;
            }
            _bakedDirty = false;
        }

        public double SampleBaked(double offset)
        {
            if (double.IsNaN(offset) || double.IsInfinity(offset)) { GD_Log.Error("Offset is non-finite"); return 0; }
            if (_bakedDirty) Bake();
            if (_baked.Length == 0) return Points.Count == 0 ? 0 : Points[0].y;
            if (_baked.Length == 1) return _baked[0];
            float fi = ((float)offset - _minDomain) / (float)GetDomainRange() * (_baked.Length - 1);
            int i = (int)Math.Floor(fi);
            if (i < 0) { i = 0; fi = 0; }
            else if (i >= _baked.Length) { i = _baked.Length - 1; fi = 0; }
            if (i + 1 < _baked.Length)
            {
                float t = fi - i;
                return _baked[i] + (_baked[i + 1] - _baked[i]) * t;
            }
            return _baked[_baked.Length - 1];
        }

        /// <summary>Godot's stored properties (Curve::set_data / set_limits / point_count) -- the baked-asset loader:
        /// "_data" = [position, left_tangent, right_tangent, left_mode, right_mode] per point, set as is (Godot doesn't
        /// re-sort or clamp here); "_limits" = [min_value, max_value, min_domain, max_domain].</summary>
        public override bool SetStoredProperty(string name, Var value)
        {
            switch (name)
            {
                case "_data":
                {
                    var a = value.AsArr();
                    if (a == null || a.Size() % 5 != 0) { GD_Log.Error("Curve: bad _data."); return true; }
                    Points.Clear();
                    for (int i = 0; i < a.Size(); i += 5)
                    {
                        var p = a[i].AsVec2();
                        Points.Add(new Point { x = p.x, y = p.y, leftTangent = (float)a[i + 1].AsFloat(), rightTangent = (float)a[i + 2].AsFloat(),
                            leftMode = a[i + 3].AsInt(), rightMode = a[i + 4].AsInt() });
                    }
                    MarkDirty();
                    return true;
                }
                case "_limits":
                {
                    var a = value.AsArr();
                    if (a == null || a.Size() != 4) { _minValue = 0; _maxValue = 1; _minDomain = 0; _maxDomain = 1; return true; }
                    _minValue = (float)a[0].AsFloat();
                    _maxValue = (float)a[1].AsFloat();
                    _minDomain = (float)a[2].AsFloat();
                    _maxDomain = (float)a[3].AsFloat();
                    _bakedDirty = true;
                    return true;
                }
                case "point_count":
                    PointCount = value.AsInt();
                    return true;
                case "bake_resolution":
                    BakeResolution = value.AsInt();
                    return true;
            }
            return false;
        }
    }

    public sealed partial class GradientTexture1D : CpuTexture
    {
        Gradient _g;
        int _w = 256;
        bool _hdr;
        public bool UseHdr { get => _hdr; set { _hdr = value; MarkDirty(); } }
        public Gradient Gradient { get => _g; set { if (_g != null) _g.Changed -= MarkDirty; _g = value; if (_g != null) _g.Changed += MarkDirty; MarkDirty(); } }
        public int Width { get => _w; set { _w = Math.Max(1, value); MarkDirty(); } }
        public override int GetWidth() => _w;
        public override int GetHeight() => 1;

        protected override Image BuildImage()
        {
            var img = Image.Create(_w, 1, false, ImageFormat.RGBA8);
            for (int x = 0; x < _w; x++) img.SetPixel(x, 0, _g == null ? Col.WHITE : _g.Sample(x / (double)Math.Max(1, _w - 1)));
            return img;
        }
    }

    public sealed partial class GradientTexture2D : CpuTexture
    {
        public enum FillEnum { Linear = 0, Radial = 1, Square = 2, Conic = 3 }
        public enum RepeatEnum { None = 0, Repeat = 1, Mirror = 2 }
        Gradient _g;
        int _w = 64, _h = 64;
        FillEnum _fill = FillEnum.Linear;
        Vec2 _from = Vec2.Zero, _to = new Vec2(1, 0);
        RepeatEnum _repeat = RepeatEnum.None;
        public bool UseHdr;

        public Gradient Gradient { get => _g; set { if (_g != null) _g.Changed -= MarkDirty; _g = value; if (_g != null) _g.Changed += MarkDirty; MarkDirty(); } }
        public int Width { get => _w; set { _w = Math.Max(1, value); MarkDirty(); } }
        public int Height { get => _h; set { _h = Math.Max(1, value); MarkDirty(); } }
        public FillEnum Fill { get => _fill; set { _fill = value; MarkDirty(); } }
        public Vec2 FillFrom { get => _from; set { _from = value; MarkDirty(); } }
        public Vec2 FillTo { get => _to; set { _to = value; MarkDirty(); } }
        public RepeatEnum Repeat { get => _repeat; set { _repeat = value; MarkDirty(); } }
        public override int GetWidth() => _w;
        public override int GetHeight() => _h;

        /// <summary>GradientTexture2D::_get_gradient_offset_at.</summary>
        float OffsetAt(int x, int y)
        {
            if (_to == _from) return 0f;
            float ofs = 0f;
            Vec2 pos = Vec2.Zero;
            if (_w > 1) pos.x = (float)x / (_w - 1);
            if (_h > 1) pos.y = (float)y / (_h - 1);
            if (_fill == FillEnum.Linear)
            {
                Vec2 seg = _to - _from;
                float l2 = seg.LengthSquared();
                Vec2 closest = l2 == 0 ? _from : _from + seg * ((pos - _from).Dot(seg) / l2);
                ofs = (closest - _from).Length() / seg.Length();
                if ((closest - _from).Dot(seg) < 0) ofs = -ofs;
            }
            else if (_fill == FillEnum.Radial)
                ofs = (pos - _from).Length() / (_to - _from).Length();
            else if (_fill == FillEnum.Square)
                ofs = Math.Max(Math.Abs(pos.x - _from.x), Math.Abs(pos.y - _from.y)) / Math.Max(Math.Abs(_to.x - _from.x), Math.Abs(_to.y - _from.y));
            else
            {
                float rel = (_to - _from).AngleTo(pos - _from);
                double tau = Math.PI * 2;
                double m = rel % tau;
                if (m < 0) m += tau;
                ofs = (float)(m / tau);
            }
            if (_repeat == RepeatEnum.None) ofs = Math.Max(0f, Math.Min(1f, ofs));
            else if (_repeat == RepeatEnum.Repeat)
            {
                ofs = ofs % 1f;
                if (ofs < 0) ofs = 1 + ofs;
            }
            else
            {
                ofs = Math.Abs(ofs) % 2f;
                if (ofs > 1f) ofs = 2f - ofs;
            }
            return ofs;
        }

        protected override Image BuildImage()
        {
            var img = Image.Create(_w, _h, false, ImageFormat.RGBA8);
            if (_g == null) { img.Fill(Col.WHITE); return img; }
            for (int y = 0; y < _h; y++)
                for (int x = 0; x < _w; x++) img.SetPixel(x, y, _g.Sample(OffsetAt(x, y)));
            return img;
        }
    }

    /// <summary>A texture built from a lambda over an Image (noise, procedural UI art).</summary>
    public sealed partial class ProceduralTexture : CpuTexture
    {
        readonly Func<Image> _make;
        readonly int _w, _h;
        public ProceduralTexture(int w, int h, Func<Image> make) { _w = w; _h = h; _make = make; }
        protected override Image BuildImage() => _make();
        public override int GetWidth() => _w;
        public override int GetHeight() => _h;
    }
}
