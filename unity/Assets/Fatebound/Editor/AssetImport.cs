// Unity import settings for the mirrored Godot assets (Assets/Resources/res/...), taken from each file's Godot
// .import sidecar in ../godot when there is one, so a texture comes out as Godot imported it:
//  * compress/mode=2 (VRAM, what Godot does to textures it finds used in 3D) -> ASTC 6x6, mipmaps, repeat
//  * otherwise uncompressed RGBA32 (Godot's lossless / lossy modes decode to exact pixels), mipmaps if
//    mipmaps/generate, clamped unless mipmapped
//  * normal maps (compress/normal_map=1, or "normal" in the name) linear; everything else sRGB
//  * textures the game reads on the CPU (Image.get_pixel: assets/war_land) readable
// Audio: music streams, the rest decompresses on load (Godot's AudioStreamOggVorbis / WAV behave the same to the game).
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace Fatebound.EditorTools
{
    public sealed class AssetImport : AssetPostprocessor
    {
        const string RES = "Assets/Resources/res/";

        static Dictionary<string, string> GodotImport(string assetPath)
        {
            var map = new Dictionary<string, string>();
            if (!assetPath.StartsWith(RES)) return map;
            string rel = assetPath.Substring(RES.Length);
            string godot = Path.GetFullPath(Path.Combine(Application.dataPath, "..", "..", "godot", rel + ".import"));
            // webp/svg sources were converted to png by sync_assets.py: look for the original's sidecar too
            if (!File.Exists(godot))
            {
                string stem = godot.Substring(0, godot.Length - ".png.import".Length);
                foreach (var ext in new[] { ".webp", ".svg", ".jpg" })
                    if (File.Exists(stem + ext + ".import")) { godot = stem + ext + ".import"; break; }
            }
            if (!File.Exists(godot)) return map;
            bool inParams = false;
            foreach (var raw in File.ReadAllLines(godot))
            {
                string line = raw.Trim();
                if (line.StartsWith("[")) { inParams = line == "[params]"; continue; }
                if (!inParams) continue;
                int eq = line.IndexOf('=');
                if (eq > 0) map[line.Substring(0, eq)] = line.Substring(eq + 1).Trim('"');
            }
            return map;
        }

        void OnPreprocessTexture()
        {
            if (!assetPath.StartsWith(RES)) return;
            var ti = (TextureImporter)assetImporter;
            var g = GodotImport(assetPath);
            g.TryGetValue("compress/mode", out var mode);
            g.TryGetValue("mipmaps/generate", out var mips);
            g.TryGetValue("compress/normal_map", out var normal);
            bool vram = mode == "2";
            bool mip = vram || mips == "true";
            bool isNormal = normal == "1" || Path.GetFileNameWithoutExtension(assetPath).ToLowerInvariant().Contains("normal");

            ti.textureType = TextureImporterType.Default;
            ti.textureShape = TextureImporterShape.Texture2D;
            ti.sRGBTexture = !isNormal;
            ti.alphaSource = TextureImporterAlphaSource.FromInput;
            ti.alphaIsTransparency = !isNormal;
            ti.npotScale = TextureImporterNPOTScale.None;
            ti.mipmapEnabled = mip;
            ti.mipmapFilter = TextureImporterMipFilter.BoxFilter;
            ti.wrapMode = mip ? TextureWrapMode.Repeat : TextureWrapMode.Clamp;
            ti.filterMode = mip ? FilterMode.Trilinear : FilterMode.Bilinear;
            ti.anisoLevel = 1;
            ti.maxTextureSize = 8192;
            ti.isReadable = assetPath.StartsWith(RES + "assets/war_land/");
            ti.textureCompression = vram ? TextureImporterCompression.Compressed : TextureImporterCompression.Uncompressed;
            var android = ti.GetPlatformTextureSettings("Android");
            android.overridden = true;
            android.maxTextureSize = 8192;
            android.format = vram ? TextureImporterFormat.ASTC_6x6 : TextureImporterFormat.RGBA32;
            android.textureCompression = ti.textureCompression;
            ti.SetPlatformTextureSettings(android);
        }

        void OnPreprocessAudio()
        {
            if (!assetPath.StartsWith(RES)) return;
            var ai = (AudioImporter)assetImporter;
            bool music = assetPath.StartsWith(RES + "assets/music/");
            var s = ai.defaultSampleSettings;
            s.loadType = music ? AudioClipLoadType.Streaming : AudioClipLoadType.DecompressOnLoad;
            s.compressionFormat = AudioCompressionFormat.Vorbis;
            s.quality = 0.7f;
            s.preloadAudioData = !music;
            ai.defaultSampleSettings = s;
            ai.forceToMono = false;
            ai.loadInBackground = music;
        }
    }
}
