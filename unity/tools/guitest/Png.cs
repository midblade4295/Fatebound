// A small PNG codec for the tests (8/16-bit, grey, RGB, palette, alpha; not interlaced).
using System;
using System.IO;
using System.IO.Compression;

namespace GuiTest
{
    public sealed class RgbaImage
    {
        public readonly int W, H;
        public readonly byte[] Px;
        public RgbaImage(int w, int h) { W = w; H = h; Px = new byte[w * h * 4]; }
    }

    public static class Png
    {
        static uint U32(byte[] d, int o) => (uint)(d[o] << 24 | d[o + 1] << 16 | d[o + 2] << 8 | d[o + 3]);

        public static RgbaImage Decode(byte[] d)
        {
            int p = 8, w = 0, h = 0, depth = 0, ctype = 0, interlace = 0;
            byte[] pal = null, trns = null;
            var idat = new MemoryStream();
            while (p < d.Length)
            {
                int len = (int)U32(d, p);
                string type = System.Text.Encoding.ASCII.GetString(d, p + 4, 4);
                int o = p + 8;
                if (type == "IHDR") { w = (int)U32(d, o); h = (int)U32(d, o + 4); depth = d[o + 8]; ctype = d[o + 9]; interlace = d[o + 12]; }
                else if (type == "PLTE") { pal = new byte[len]; Array.Copy(d, o, pal, 0, len); }
                else if (type == "tRNS") { trns = new byte[len]; Array.Copy(d, o, trns, 0, len); }
                else if (type == "IDAT") idat.Write(d, o, len);
                else if (type == "IEND") break;
                p += 12 + len;
            }
            if (interlace != 0) throw new NotSupportedException("interlaced png");
            idat.Position = 0;
            var raw = new MemoryStream();
            using (var z = new ZLibStream(idat, CompressionMode.Decompress)) z.CopyTo(raw);
            byte[] r = raw.ToArray();
            int ch = ctype switch { 0 => 1, 2 => 3, 3 => 1, 4 => 2, 6 => 4, _ => 4 };
            int bpp = Math.Max(1, ch * depth / 8);
            int stride = (w * ch * depth + 7) / 8;
            var img = new RgbaImage(w, h);
            var prev = new byte[stride];
            var cur = new byte[stride];
            int rp = 0;
            for (int y = 0; y < h; y++)
            {
                int f = r[rp++];
                Array.Copy(r, rp, cur, 0, stride);
                rp += stride;
                for (int x = 0; x < stride; x++)
                {
                    int a = x >= bpp ? cur[x - bpp] : 0, b = prev[x], c = x >= bpp ? prev[x - bpp] : 0;
                    switch (f)
                    {
                        case 1: cur[x] = (byte)(cur[x] + a); break;
                        case 2: cur[x] = (byte)(cur[x] + b); break;
                        case 3: cur[x] = (byte)(cur[x] + ((a + b) >> 1)); break;
                        case 4:
                        {
                            int pp = a + b - c, pa = Math.Abs(pp - a), pb = Math.Abs(pp - b), pc = Math.Abs(pp - c);
                            cur[x] = (byte)(cur[x] + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c));
                            break;
                        }
                    }
                }
                for (int x = 0; x < w; x++)
                {
                    byte R, G, B, A = 255;
                    int Sample(int i)
                    {
                        if (depth == 8) return cur[i];
                        if (depth == 16) return cur[i * 2];
                        int perByte = 8 / depth, bi = i / perByte, sh = 8 - depth * (i % perByte + 1);
                        int v = (cur[bi] >> sh) & ((1 << depth) - 1);
                        return ctype == 3 ? v : v * 255 / ((1 << depth) - 1);
                    }
                    switch (ctype)
                    {
                        case 0: R = G = B = (byte)Sample(x); if (trns != null && trns.Length >= 2 && Sample(x) == trns[1]) A = 0; break;
                        case 2: R = (byte)Sample(x * 3); G = (byte)Sample(x * 3 + 1); B = (byte)Sample(x * 3 + 2); break;
                        case 3: { int i = Sample(x); R = pal[i * 3]; G = pal[i * 3 + 1]; B = pal[i * 3 + 2]; A = trns != null && i < trns.Length ? trns[i] : (byte)255; break; }
                        case 4: R = G = B = (byte)Sample(x * 2); A = (byte)Sample(x * 2 + 1); break;
                        default: R = (byte)Sample(x * 4); G = (byte)Sample(x * 4 + 1); B = (byte)Sample(x * 4 + 2); A = (byte)Sample(x * 4 + 3); break;
                    }
                    int q = (y * w + x) * 4;
                    img.Px[q] = R; img.Px[q + 1] = G; img.Px[q + 2] = B; img.Px[q + 3] = A;
                }
                var t = prev; prev = cur; cur = t;
            }
            return img;
        }

        static uint Crc(byte[] b, int o, int n)
        {
            uint c = 0xffffffff;
            for (int i = o; i < o + n; i++)
            {
                c ^= b[i];
                for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
            }
            return c ^ 0xffffffff;
        }

        static void Chunk(Stream s, string type, byte[] data)
        {
            var b = new byte[data.Length + 12];
            b[0] = (byte)(data.Length >> 24); b[1] = (byte)(data.Length >> 16); b[2] = (byte)(data.Length >> 8); b[3] = (byte)data.Length;
            System.Text.Encoding.ASCII.GetBytes(type, 0, 4, b, 4);
            Array.Copy(data, 0, b, 8, data.Length);
            uint c = Crc(b, 4, data.Length + 4);
            b[b.Length - 4] = (byte)(c >> 24); b[b.Length - 3] = (byte)(c >> 16); b[b.Length - 2] = (byte)(c >> 8); b[b.Length - 1] = (byte)c;
            s.Write(b, 0, b.Length);
        }

        public static void Save(string path, RgbaImage img)
        {
            using var f = File.Create(path);
            f.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
            var ih = new byte[13];
            ih[0] = (byte)(img.W >> 24); ih[1] = (byte)(img.W >> 16); ih[2] = (byte)(img.W >> 8); ih[3] = (byte)img.W;
            ih[4] = (byte)(img.H >> 24); ih[5] = (byte)(img.H >> 16); ih[6] = (byte)(img.H >> 8); ih[7] = (byte)img.H;
            ih[8] = 8; ih[9] = 6;
            Chunk(f, "IHDR", ih);
            var raw = new MemoryStream();
            using (var z = new ZLibStream(raw, CompressionLevel.Fastest, true))
                for (int y = 0; y < img.H; y++)
                {
                    z.WriteByte(0);
                    z.Write(img.Px, y * img.W * 4, img.W * 4);
                }
            Chunk(f, "IDAT", raw.ToArray());
            Chunk(f, "IEND", new byte[0]);
        }
    }
}
