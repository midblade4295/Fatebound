using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using Fatebound.GUI;
using Fatebound.Sim;

namespace GuiTest
{
    public static class Program
    {
        public static string Repo = TestHost.Root;

        static readonly string[] Fonts = { "res://assets/fonts/LilitaOne-Regular.ttf", "res://assets/fonts/Nunito-Bold.woff2", "res://assets/fonts/Nunito-ExtraBold.woff2",
            "res://assets/fonts/Cinzel-Black.woff2", "res://assets/fonts/DejaVuSans.ttf", "" };
        static readonly int[] Sizes = { 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 21, 22, 24, 26, 28, 32, 36, 40, 48, 64 };
        static readonly string[] Texts = { "Hello World", "PLAY", "Fatebound", "1,234 gold", "Wavy AV To Ty", "The quick brown fox jumps over the lazy dog.", "x", "  spaced  ", "WWW iii", "100%" };

        public static int Main(string[] args)
        {
            CultureInfo.DefaultThreadCurrentCulture = CultureInfo.InvariantCulture;
            CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
            ResourceLoader.Host = new TestHost(Repo);
            string cmd = args.Length > 0 ? args[0] : "help";
            switch (cmd)
            {
                case "runtime":
                    RuntimeTest.Run();
                    return 0;
                case "anim":
                    AnimTest.Run(args);
                    return 0;
                case "bake":
                    return BakeTest.Run(args.Skip(1).ToArray());
                case "services":
                case "services-gen":
                    ServicesTest.Run(cmd == "services-gen");
                    return 0;
                case "math":
                    MathTest.Run();
                    return 0;
                case "mesh":
                    MeshTest.Run(args);
                    return 0;
                case "physics": return PhysicsTest.Run();
                case "particles":
                    ParticlesTest.RunAll();
                    return 0;
                case "particles-parity":
                    ParticlesTest.Parity(args[1]);
                    return 0;
                case "fonts":
                    foreach (var fp in Fonts)
                    {
                        Font f = fp == "" ? ThemeDB.FallbackFont : ResourceLoader.Load<FontFile>(fp);
                        foreach (int s in Sizes)
                        {
                            string line = string.Format("F {0} {1} asc={2:F4} desc={3:F4} h={4:F4}", fp == "" ? "default" : Path.GetFileName(fp), s, f.GetAscent(s), f.GetDescent(s), f.GetHeight(s));
                            foreach (var t in Texts) line += string.Format(" |{0}|={1:F4}", t, f.GetStringSize(t, HorizontalAlignment.Left, -1, s).x);
                            Console.WriteLine(line);
                        }
                    }
                    return 0;
                case "glyph":
                {
                    var f = ResourceLoader.Load<FontFile>(args[1]);
                    int g = f.Face.GlyphIndex(args[2][0]);
                    foreach (var c in f.Face.Outline(g))
                        Console.WriteLine(string.Join(" ", c.Select(p => $"{p.x},{p.y}{(p.on ? "" : "*")}")));
                    f.Face.Bounds(g, out int bx0, out int by0, out int bx1, out int by1);
                    float sc = 48f / f.Face.UnitsPerEm;
                    int pad = 9;
                    float fx0 = MathF.Floor(bx0 * sc) - pad, fy1 = MathF.Ceiling(by1 * sc) + pad;
                    int w = (int)(MathF.Ceiling(bx1 * sc) + pad - fx0), h = (int)(fy1 - (MathF.Floor(by0 * sc) - pad));
                    var field = SdfRaster.Render(f.Face.Outline(g), sc, fx0, fy1, w, h, 8f);
                    for (int y = 0; y < h; y++)
                    {
                        var sb = new System.Text.StringBuilder();
                        for (int x = 0; x < w; x++) { int v = field[y * w + x]; sb.Append(v >= 128 ? '#' : v > 64 ? '+' : v > 8 ? '.' : ' '); }
                        Console.WriteLine(sb.ToString());
                    }
                    return 0;
                }
                case "scene":
                    return Scenes.Run(args.Skip(1).ToArray());
                case "ui":
                    foreach (var l in UiParity.Run(args[1])) Console.WriteLine(l);
                    return 0;
                case "uirender":
                {
                    var (tree, frames) = UiParity.Load(args[1]);
                    int sc = args.Length > 3 ? int.Parse(args[3]) : 1;
                    tree.Root.SetWindowSize(tree.Root.Size * sc);
                    for (int i = 0; i < frames; i++) tree.Iterate(1.0 / 60.0);
                    var batches = tree.Root.Render();
                    var r = new SoftRaster((int)tree.Root.GetWindowSize().x, (int)tree.Root.GetWindowSize().y, new Col(0.3f, 0.3f, 0.3f, 1f));
                    r.Draw(batches);
                    Png.Save(args[2], r.ToImage());
                    if (System.Environment.GetEnvironmentVariable("ATLAS") != null)
                        for (int pi = 0; pi < GlyphAtlas.Shared.Pages.Count; pi++)
                        {
                            var pg = GlyphAtlas.Shared.Pages[pi].img;
                            var ai = new RgbaImage(pg.Width, pg.Height);
                            for (int k = 0; k < pg.Width * pg.Height; k++) { ai.Px[k * 4] = ai.Px[k * 4 + 1] = ai.Px[k * 4 + 2] = pg.Data[k]; ai.Px[k * 4 + 3] = 255; }
                            Png.Save(args[2] + ".atlas" + pi + ".png", ai);
                        }
                    Console.WriteLine("batches " + batches.Count);
                    return 0;
                }
                default:
                    Console.WriteLine("guitest fonts | scene <name> [out.png] [w h]");
                    return 1;
            }
        }
    }
}
