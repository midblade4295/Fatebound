// Fatebound engine services (Unity port): PackedByteArray's methods on byte[] (encode_* / decode_* little endian with
// Godot's bounds checks, compress / decompress / decompress_dynamic, slice, encode_var / decode_var) and Godot's
// Compression (core/io/compression.cpp) with its exact framing so data crosses both ways with a Godot peer:
//   COMPRESSION_DEFLATE = a zlib stream (2-byte header, raw deflate, Adler-32), COMPRESSION_GZIP = gzip,
//   COMPRESSION_ZSTD = a zstd frame (level 3, ZstdSharp). FastLZ and Brotli are not available (they fail as an
//   unavailable mode does in Godot: an empty array and an error).
using System;
using System.IO;
using System.IO.Compression;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>PackedByteArray methods on byte[] (the port's PackedByteArray).</summary>
    public static class PackedBytes
    {
        static bool Bad(byte[] b, long offset, int size, string fn)
        {
            if (b == null || offset < 0 || offset > b.LongLength - size)
            {
                GD.PushError("Condition \"p_offset < 0 || p_offset > int64_t(size) - " + size + "\" is true. (" + fn + ")");
                return true;
            }
            return false;
        }

        // ------------------------------------------------------------------ decode_*
        public static long DecodeU8(this byte[] b, long offset) => Bad(b, offset, 1, "decode_u8") ? 0 : b[offset];
        public static long DecodeS8(this byte[] b, long offset) => Bad(b, offset, 1, "decode_s8") ? 0 : (sbyte)b[offset];
        public static long DecodeU16(this byte[] b, long offset) => Bad(b, offset, 2, "decode_u16") ? 0 : (ushort)(b[offset] | (b[offset + 1] << 8));
        public static long DecodeS16(this byte[] b, long offset) => Bad(b, offset, 2, "decode_s16") ? 0 : (short)(b[offset] | (b[offset + 1] << 8));
        public static long DecodeU32(this byte[] b, long offset) => Bad(b, offset, 4, "decode_u32") ? 0 : U32(b, offset);
        public static long DecodeS32(this byte[] b, long offset) => Bad(b, offset, 4, "decode_s32") ? 0 : unchecked((int)U32(b, offset));
        public static long DecodeU64(this byte[] b, long offset) => Bad(b, offset, 8, "decode_u64") ? 0 : unchecked((long)U64(b, offset));
        public static long DecodeS64(this byte[] b, long offset) => Bad(b, offset, 8, "decode_s64") ? 0 : unchecked((long)U64(b, offset));
        public static double DecodeHalf(this byte[] b, long offset) => Bad(b, offset, 2, "decode_half") ? 0 : HalfToFloat((ushort)(b[offset] | (b[offset + 1] << 8)));
        public static double DecodeFloat(this byte[] b, long offset) => Bad(b, offset, 4, "decode_float") ? 0 : BitConverter.Int32BitsToSingle(unchecked((int)U32(b, offset)));
        public static double DecodeDouble(this byte[] b, long offset) => Bad(b, offset, 8, "decode_double") ? 0 : BitConverter.Int64BitsToDouble(unchecked((long)U64(b, offset)));

        static uint U32(byte[] b, long p) => (uint)(b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24));
        static ulong U64(byte[] b, long p) => U32(b, p) | ((ulong)U32(b, p + 4) << 32);

        // ------------------------------------------------------------------ encode_*
        public static void EncodeU8(this byte[] b, long offset, long value) { if (!Bad(b, offset, 1, "encode_u8")) b[offset] = unchecked((byte)value); }
        public static void EncodeS8(this byte[] b, long offset, long value) { if (!Bad(b, offset, 1, "encode_s8")) b[offset] = unchecked((byte)(sbyte)value); }
        public static void EncodeU16(this byte[] b, long offset, long value) { if (!Bad(b, offset, 2, "encode_u16")) W16(b, offset, unchecked((ushort)value)); }
        public static void EncodeS16(this byte[] b, long offset, long value) { if (!Bad(b, offset, 2, "encode_s16")) W16(b, offset, unchecked((ushort)(short)value)); }
        public static void EncodeU32(this byte[] b, long offset, long value) { if (!Bad(b, offset, 4, "encode_u32")) W32(b, offset, unchecked((uint)value)); }
        public static void EncodeS32(this byte[] b, long offset, long value) { if (!Bad(b, offset, 4, "encode_s32")) W32(b, offset, unchecked((uint)(int)value)); }
        public static void EncodeU64(this byte[] b, long offset, long value) { if (!Bad(b, offset, 8, "encode_u64")) W64(b, offset, unchecked((ulong)value)); }
        public static void EncodeS64(this byte[] b, long offset, long value) { if (!Bad(b, offset, 8, "encode_s64")) W64(b, offset, unchecked((ulong)value)); }
        public static void EncodeHalf(this byte[] b, long offset, double value) { if (!Bad(b, offset, 2, "encode_half")) W16(b, offset, MakeHalf((float)value)); }
        public static void EncodeFloat(this byte[] b, long offset, double value) { if (!Bad(b, offset, 4, "encode_float")) W32(b, offset, unchecked((uint)BitConverter.SingleToInt32Bits((float)value))); }
        public static void EncodeDouble(this byte[] b, long offset, double value) { if (!Bad(b, offset, 8, "encode_double")) W64(b, offset, unchecked((ulong)BitConverter.DoubleToInt64Bits(value))); }

        static void W16(byte[] b, long p, ushort v) { b[p] = (byte)v; b[p + 1] = (byte)(v >> 8); }
        static void W32(byte[] b, long p, uint v) { b[p] = (byte)v; b[p + 1] = (byte)(v >> 8); b[p + 2] = (byte)(v >> 16); b[p + 3] = (byte)(v >> 24); }
        static void W64(byte[] b, long p, ulong v) { W32(b, p, (uint)v); W32(b, p + 4, (uint)(v >> 32)); }

        /// <summary>Math::make_half_float.</summary>
        public static ushort MakeHalf(float f)
        {
            uint x = unchecked((uint)BitConverter.SingleToInt32Bits(f));
            uint sign = x >> 31;
            uint mantissa = x & ((1u << 23) - 1);
            uint exponent = x & (0xFFu << 23);
            if (exponent >= 0x47800000)
            {
                mantissa = mantissa != 0 && exponent == (0xFFu << 23) ? (1u << 23) - 1 : 0;   // NaN stays NaN, else infinity
                return (ushort)((sign << 15) | (0x1F << 10) | (mantissa >> 13));
            }
            if (exponent <= 0x38000000) return 0;                                            // (Godot: denormals become zero)
            return (ushort)((sign << 15) | ((exponent - 0x38000000) >> 13) | (mantissa >> 13));
        }

        /// <summary>Math::half_to_float (halfbits_to_floatbits).</summary>
        public static float HalfToFloat(ushort h)
        {
            uint hExp = h & 0x7c00u;
            uint fSgn = ((uint)h & 0x8000u) << 16;
            uint r;
            if (hExp == 0)
            {
                uint hSig = h & 0x03ffu;
                if (hSig == 0) r = fSgn;
                else
                {
                    hSig <<= 1;
                    while ((hSig & 0x0400u) == 0) { hSig <<= 1; hExp++; }
                    r = fSgn + ((127 - 15 - hExp) << 23) + ((hSig & 0x03ffu) << 13);
                }
            }
            else if (hExp == 0x7c00u) r = fSgn + 0x7f800000u + (((uint)h & 0x03ffu) << 13);
            else r = fSgn + ((((uint)h & 0x7fffu) + 0x1c000u) << 13);
            return BitConverter.Int32BitsToSingle(unchecked((int)r));
        }

        // ------------------------------------------------------------------ variants
        /// <summary>encode_var(offset, value, allow_objects): the bytes written, -1 when it doesn't fit.</summary>
        public static long EncodeVar(this byte[] b, long offset, Var value, bool allowObjects = false)
        {
            if (offset < 0) { GD.PushError("Condition \"p_offset < 0\" is true. Returning: -1"); return -1; }
            var enc = GMarshal.VarToBytes(value, allowObjects);
            if (enc.Length == 0) return -1;
            if (offset + enc.Length > b.LongLength) return -1;
            Buffer.BlockCopy(enc, 0, b, (int)offset, enc.Length);
            return enc.Length;
        }

        public static Var DecodeVar(this byte[] b, long offset, bool allowObjects = false)
        {
            if (offset < 0) { GD.PushError("Condition \"p_offset < 0\" is true. Returning: Variant()"); return Var.Nil; }
            return GMarshal.DecodeVariant(b, (int)offset, (int)Math.Max(0, b.LongLength - offset), out Var v, out _, allowObjects) == GD.OK ? v : Var.Nil;
        }

        public static long DecodeVarSize(this byte[] b, long offset, bool allowObjects = false)
        {
            if (offset < 0) { GD.PushError("Condition \"p_offset < 0\" is true. Returning: 0"); return 0; }
            return GMarshal.DecodeVariant(b, (int)offset, (int)Math.Max(0, b.LongLength - offset), out _, out int used, allowObjects) == GD.OK ? used : 0;
        }

        public static bool HasEncodedVar(this byte[] b, long offset, bool allowObjects = false)
        {
            if (offset < 0) { GD.PushError("Condition \"p_offset < 0\" is true. Returning: false"); return false; }
            return GMarshal.DecodeVariant(b, (int)offset, (int)Math.Max(0, b.LongLength - offset), out _, out _, allowObjects) == GD.OK;
        }

        // ------------------------------------------------------------------ slicing / reinterpreting
        /// <summary>slice(begin, end): Godot's clamping of negative and out-of-range bounds; a new array.</summary>
        public static byte[] Slice(this byte[] b, long begin, long end = int.MaxValue)
        {
            long s = b.LongLength;
            begin = Math.Max(-s, Math.Min(begin, s));
            if (begin < 0) begin += s;
            end = Math.Max(-s, Math.Min(end, s));
            if (end < 0) end += s;
            if (begin > end) { GD.PushError("Condition \"begin > end\" is true. Returning: result"); return Array.Empty<byte>(); }
            if (end == begin) return Array.Empty<byte>();
            var r = new byte[end - begin];
            Buffer.BlockCopy(b, (int)begin, r, 0, r.Length);
            return r;
        }

        /// <summary>to_int32_array() and the like: the bytes reinterpreted (empty, with an error, when the size isn't a
        /// multiple of the element size).</summary>
        public static int[] ToInt32Array(this byte[] b) => Multiple(b, 4, "32-bit integer", "PackedInt32Array") ? Copy(b, new int[b.Length / 4], 4) : Array.Empty<int>();
        public static long[] ToInt64Array(this byte[] b) => Multiple(b, 8, "64-bit integer", "PackedInt64Array") ? Copy(b, new long[b.Length / 8], 8) : Array.Empty<long>();
        public static float[] ToFloat32Array(this byte[] b) => Multiple(b, 4, "32-bit float", "PackedFloat32Array") ? Copy(b, new float[b.Length / 4], 4) : Array.Empty<float>();
        public static double[] ToFloat64Array(this byte[] b) => Multiple(b, 8, "64-bit double", "PackedFloat64Array") ? Copy(b, new double[b.Length / 8], 8) : Array.Empty<double>();

        static bool Multiple(byte[] b, int size, string what, string to)
        {
            if (b.Length % size == 0) return true;
            GD.PushError("PackedByteArray size must be a multiple of " + size + " (size of " + what + ") to convert to " + to + ".");
            return false;
        }

        static T[] Copy<T>(byte[] b, T[] r, int size)
        {
            Buffer.BlockCopy(b, 0, r, 0, r.Length * size);
            return r;
        }

        // ------------------------------------------------------------------ compression
        /// <summary>compress(mode): empty for an empty array or a mode that can't compress.</summary>
        public static byte[] Compress(this byte[] b, int mode = 0)
        {
            if (b == null || b.Length == 0) return Array.Empty<byte>();
            return GCompression.Compress(b, mode) ?? Array.Empty<byte>();
        }

        /// <summary>decompress(buffer_size, mode): empty when the data is bad or doesn't fit in buffer_size.</summary>
        public static byte[] Decompress(this byte[] b, long bufferSize, int mode = 0)
        {
            if (bufferSize <= 0) { GD.PushError("Decompression buffer size must be greater than zero."); return Array.Empty<byte>(); }
            if (b == null || b.Length == 0) { GD.PushError("Compressed buffer size must be greater than zero."); return Array.Empty<byte>(); }
            return GCompression.Decompress(b, bufferSize, mode) ?? Array.Empty<byte>();
        }

        /// <summary>decompress_dynamic(max_output_size, mode): gzip / deflate of unknown size (-1: no limit).</summary>
        public static byte[] DecompressDynamic(this byte[] b, long maxOutputSize, int mode = 0)
        {
            var r = GCompression.DecompressDynamic(b, maxOutputSize, mode);
            if (r == null) { GD.PushError("Decompression failed."); return Array.Empty<byte>(); }
            return r;
        }
    }

    /// <summary>Godot's Compression with its default levels (zlib/gzip: Z_DEFAULT_COMPRESSION, zstd: 3). Returns null
    /// on failure (the callers turn that into Godot's empty array).</summary>
    public static class GCompression
    {
        public const int MODE_FASTLZ = 0, MODE_DEFLATE = 1, MODE_ZSTD = 2, MODE_GZIP = 3, MODE_BROTLI = 4;
        public static int ZstdLevel = 3;

        public static byte[] Compress(byte[] src, int mode)
        {
            switch (mode)
            {
                case MODE_DEFLATE:
                    {
                        var ms = new MemoryStream();
                        ms.WriteByte(0x78);
                        ms.WriteByte(0x9C);
                        using (var ds = new DeflateStream(ms, CompressionLevel.Optimal, true)) ds.Write(src, 0, src.Length);
                        uint a = Adler32(src, 0, src.Length);
                        ms.WriteByte((byte)(a >> 24)); ms.WriteByte((byte)(a >> 16)); ms.WriteByte((byte)(a >> 8)); ms.WriteByte((byte)a);
                        return ms.ToArray();
                    }
                case MODE_GZIP:
                    {
                        var ms = new MemoryStream();
                        using (var gs = new GZipStream(ms, CompressionLevel.Optimal, true)) gs.Write(src, 0, src.Length);
                        return ms.ToArray();
                    }
                case MODE_ZSTD:
                    using (var c = new ZstdSharp.Compressor(ZstdLevel)) return c.Wrap(src).ToArray();
                case MODE_BROTLI:
                    GD.PushError("Only brotli decompression is supported.");
                    return null;
                default:
                    GD.PushError("Compression mode " + mode + " is not available in the port (FastLZ).");
                    return null;
            }
        }

        /// <summary>Compression::decompress into a buffer of dstMax bytes: the output, or null when it is bad or too big.</summary>
        public static byte[] Decompress(byte[] src, long dstMax, int mode)
        {
            switch (mode)
            {
                case MODE_ZSTD:
                    {
                        var dst = new byte[dstMax];
                        try
                        {
                            using (var d = new ZstdSharp.Decompressor())
                            {
                                if (!d.TryUnwrap(src, dst, 0, out int n)) return null;
                                if (n == dst.Length) return dst;
                                var r = new byte[n];
                                Buffer.BlockCopy(dst, 0, r, 0, n);
                                return r;
                            }
                        }
                        catch (Exception) { return null; }
                    }
                case MODE_DEFLATE:
                case MODE_GZIP:
                    {
                        var r = Inflate(src, mode, dstMax + 1);
                        if (r == null || r.LongLength > dstMax)
                        {
                            GD.PushError("Condition \"err != Z_STREAM_END\" is true. Returning: -1");
                            return null;
                        }
                        return r;
                    }
                case MODE_BROTLI:
                    GD.PushError("Brotli decompression is not available in the port.");
                    return null;
                default:
                    GD.PushError("Compression mode " + mode + " is not available in the port (FastLZ).");
                    return null;
            }
        }

        /// <summary>Compression::decompress_dynamic (gzip / deflate only): null on bad data or more than max bytes.</summary>
        public static byte[] DecompressDynamic(byte[] src, long max, int mode)
        {
            if (src == null || src.Length == 0) { GD.PushError("Condition \"p_src_size <= 0\" is true."); return null; }
            if (mode != MODE_DEFLATE && mode != MODE_GZIP)
            {
                GD.PushError("Dynamic decompression is only supported with gzip, DEFLATE, and Brotli compression methods.");
                return null;
            }
            var r = Inflate(src, mode, max > -1 ? max + 1 : long.MaxValue);
            if (r == null || (max > -1 && r.LongLength > max)) return null;
            return r;
        }

        /// <summary>A zlib (DEFLATE) or gzip stream inflated, checksums verified; null when it is malformed. Stops
        /// reading past limit bytes (the result is then limit bytes long).</summary>
        static byte[] Inflate(byte[] src, int mode, long limit)
        {
            try
            {
                int start = 0, end = src.Length;
                if (mode == MODE_DEFLATE)
                {
                    if (src.Length < 6) return null;
                    int cmf = src[0], flg = src[1];
                    if ((cmf & 0x0f) != 8 || (cmf >> 4) > 7 || ((cmf << 8) | flg) % 31 != 0 || (flg & 0x20) != 0) return null;
                    start = 2;
                    end = src.Length;
                }
                else if (src.Length < 18 || src[0] != 0x1f || src[1] != 0x8b || src[2] != 8) return null;
                var input = new MemoryStream(src, start, end - start, false);
                var output = new MemoryStream();
                Stream z = mode == MODE_DEFLATE ? (Stream)new DeflateStream(input, CompressionMode.Decompress) : new GZipStream(input, CompressionMode.Decompress);
                using (z)
                {
                    var buf = new byte[16384];
                    while (true)
                    {
                        int n = z.Read(buf, 0, buf.Length);
                        if (n <= 0) break;
                        output.Write(buf, 0, n);
                        if (output.Length >= limit) break;
                    }
                }
                var r = output.ToArray();
                if (r.LongLength >= limit) return r;
                if (mode == MODE_DEFLATE)
                {
                    // the Adler-32 of the output closes the stream (a truncated stream fails here)
                    uint want = (uint)((src[src.Length - 4] << 24) | (src[src.Length - 3] << 16) | (src[src.Length - 2] << 8) | src[src.Length - 1]);
                    if (Adler32(r, 0, r.Length) != want) return null;
                }
                else
                {
                    uint crc = (uint)(src[src.Length - 8] | (src[src.Length - 7] << 8) | (src[src.Length - 6] << 16) | (src[src.Length - 5] << 24));
                    uint size = (uint)(src[src.Length - 4] | (src[src.Length - 3] << 8) | (src[src.Length - 2] << 16) | (src[src.Length - 1] << 24));
                    if (size != (uint)r.LongLength || Crc32(r) != crc) return null;
                }
                return r;
            }
            catch (InvalidDataException) { return null; }
            catch (IOException) { return null; }
        }

        public static uint Adler32(byte[] b, int off, int len)
        {
            uint a = 1, s = 0;
            for (int i = off; i < off + len; i++)
            {
                a = (a + b[i]) % 65521;
                s = (s + a) % 65521;
            }
            return (s << 16) | a;
        }

        static uint[] _crcTable;

        public static uint Crc32(byte[] b)
        {
            var t = _crcTable;
            if (t == null)
            {
                t = new uint[256];
                for (uint n = 0; n < 256; n++)
                {
                    uint c = n;
                    for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                    t[n] = c;
                }
                _crcTable = t;
            }
            uint crc = 0xFFFFFFFFu;
            foreach (var x in b) crc = t[(crc ^ x) & 0xFF] ^ (crc >> 8);
            return crc ^ 0xFFFFFFFFu;
        }
    }
}
