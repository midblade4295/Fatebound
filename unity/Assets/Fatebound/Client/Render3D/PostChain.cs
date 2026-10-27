// A 3D viewport's post chain, Godot 4's Mobile renderer (renderer_scene_render_rd.cpp _render_buffers_post_process):
// glow (gather to quarter resolution, down the mip chain to the deepest level used, back up blending each level's own
// texture by its glow_levels weight) then tonemap_mobile (exposure, glow blend, tonemapper, adjustments) into the
// viewport's sRGB texture. Run from URP's endCameraRendering, after the camera's own work was submitted.
using System;
using Fatebound.GUI;
using UnityEngine;
using UnityEngine.Rendering;
using Environment = Fatebound.GUI.Environment;
using Shader = UnityEngine.Shader;
using Material = UnityEngine.Material;

namespace Fatebound.Client
{
    public static class PostChain
    {
        static Material _mat;
        static CommandBuffer _cmd;
        static RenderTextureFormat _glowFormat = (RenderTextureFormat)(-1);

        const int PASS_GATHER = 0, PASS_DOWN = 1, PASS_UP = 2, PASS_TONEMAP = 3;

        static readonly int ID_Source = Shader.PropertyToID("_Source"), ID_Blend = Shader.PropertyToID("_Blend"),
            ID_SrcPixelSize = Shader.PropertyToID("_SrcPixelSize"), ID_DestPixelSize = Shader.PropertyToID("_DestPixelSize"),
            ID_SrcSize = Shader.PropertyToID("_SrcSize"), ID_GlowStrength = Shader.PropertyToID("_GlowStrength"),
            ID_GlowBloom = Shader.PropertyToID("_GlowBloom"), ID_GlowHdrThreshold = Shader.PropertyToID("_GlowHdrThreshold"),
            ID_GlowHdrScale = Shader.PropertyToID("_GlowHdrScale"), ID_GlowExposure = Shader.PropertyToID("_GlowExposure"),
            ID_GlowLuminanceCap = Shader.PropertyToID("_GlowLuminanceCap"), ID_GlowLevel = Shader.PropertyToID("_GlowLevel"),
            ID_UseBlend = Shader.PropertyToID("_UseBlend"), ID_Exposure = Shader.PropertyToID("_Exposure"),
            ID_White = Shader.PropertyToID("_White"), ID_TonemapParam = Shader.PropertyToID("_TonemapParam"),
            ID_Tonemapper = Shader.PropertyToID("_Tonemapper"), ID_UseGlow = Shader.PropertyToID("_UseGlow"),
            ID_GlowMode = Shader.PropertyToID("_GlowMode"), ID_GlowIntensity = Shader.PropertyToID("_GlowIntensity"),
            ID_UseBcs = Shader.PropertyToID("_UseBcs"), ID_Bcs = Shader.PropertyToID("_Bcs"),
            ID_Transparent = Shader.PropertyToID("_Transparent");

        // glow levels: BLUR_1 mips (level k's own texture at mip k+1) and BLUR_0 mips (the upsampled sums)
        static readonly int[] Blur1 = new int[10], Blur0 = new int[10];

        static PostChain()
        {
            for (int i = 0; i < 10; i++)
            {
                Blur1[i] = Shader.PropertyToID("_FB_Blur1_" + i);
                Blur0[i] = Shader.PropertyToID("_FB_Blur0_" + i);
            }
        }

        static Material Mat
        {
            get
            {
                if (_mat == null)
                {
                    var sh = Shader.Find("Hidden/Fatebound/Post") ?? Resources.Load<Shader>("Shaders/FateboundPost");
                    _mat = new Material(sh) { hideFlags = HideFlags.DontSave };
                }
                return _mat;
            }
        }

        /// <summary>The glow textures' format: 32-bit float RGB like Godot's 32-bit buffers where the GPU can.</summary>
        static RenderTextureFormat GlowFormat
        {
            get
            {
                if ((int)_glowFormat < 0)
                    _glowFormat = SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.RGB111110Float) ? RenderTextureFormat.RGB111110Float : RenderTextureFormat.ARGBHalf;
                return _glowFormat;
            }
        }

        static int Shr(int v, int s) => Math.Max(1, v >> s);

        /// <summary>Godot's Image::get_image_required_mipmaps for the blur textures (levels below the base).</summary>
        static int RequiredMipmaps(int w, int h)
        {
            int n = 0;
            while (w > 1 || h > 1)
            {
                w = Math.Max(1, w >> 1);
                h = Math.Max(1, h >> 1);
                n++;
            }
            return n;
        }

        static void Blit(CommandBuffer cmd, RenderTargetIdentifier dest, int pass)
        {
            cmd.SetRenderTarget(dest, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
            cmd.DrawProcedural(Matrix4x4.identity, Mat, pass, MeshTopology.Triangles, 3, 1);
        }

        static int _usable = -1;

        /// <summary>Whether the post shader runs here (compiled for this GPU, all four passes). If not, say so once (the match
        /// log) and copy the scene straight into the viewport's texture instead, so the 3D still shows.</summary>
        static bool Usable
        {
            get
            {
                if (_usable < 0)
                {
                    var sh = Mat.shader;
                    _usable = sh != null && sh.isSupported && Mat.passCount >= 4 ? 1 : 0;
                    if (_usable == 0)
                        Debug.LogError("Fatebound post shader can't run here (" + (sh == null ? "missing" : sh.name + ", supported " + sh.isSupported + ", "
                            + Mat.passCount + " passes") + "): the 3D is copied without glow or tonemapping");
                }
                return _usable == 1;
            }
        }

        public static void Render(ScriptableRenderContext ctx, RenderTexture hdr, RenderTexture ldr, Environment env, bool transparent)
        {
            if (hdr == null || ldr == null) return;
            var cmd = _cmd ??= new CommandBuffer { name = "Fatebound post" };
            cmd.Clear();
            if (!Usable)
            {
                cmd.Blit(hdr, ldr);
                ctx.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                ctx.Submit();
                return;
            }
            int w = hdr.width, h = hdr.height;
            bool glow = env != null && env.GlowEnabled && Render(cmd, hdr, env, w, h);

            // ---- tonemap
            cmd.SetGlobalTexture(ID_Source, hdr);
            cmd.SetGlobalVector(ID_DestPixelSize, new Vector4(1f / w, 1f / h, 0, 0));
            int mode = env != null ? env.TonemapMode : Environment.TONE_MAPPER_LINEAR;
            float exposure = env != null ? (float)env.TonemapExposure : 1f;
            float white = 1f, param = 1f;
            if (env != null)
            {
                switch (mode)
                {
                    case Environment.TONE_MAPPER_LINEAR: white = 1f; break;
                    case Environment.TONE_MAPPER_REINHARDT:
                        white = Math.Max(1f, (float)env.TonemapWhite);
                        param = white * white;
                        break;
                    case Environment.TONE_MAPPER_ACES:
                        {
                            white = Math.Max(1f, (float)env.TonemapWhite);
                            const float A = 0.0245786f, B = 0.000090537f, C = 0.983729f, D = 0.432951f, E = 0.238081f;
                            float wb = white * 1.8f;
                            param = (wb * (wb + A) - B) / (wb * (C * wb + D) + E);
                            break;
                        }
                    default:
                        {
                            // filmic (and AgX, not ported: drawn as filmic)
                            mode = Environment.TONE_MAPPER_FILMIC;
                            white = Math.Max(1f, (float)env.TonemapWhite);
                            const float bias = 2f, A = 0.22f * bias * bias, B = 0.30f * bias, C = 0.10f, D = 0.20f, E = 0.01f, F = 0.30f;
                            param = ((white * (A * white + C * B) + D * E) / (white * (A * white + B) + D * F)) - E / F;
                            break;
                        }
                }
            }
            cmd.SetGlobalFloat(ID_Tonemapper, mode == Environment.TONE_MAPPER_LINEAR ? 0 : mode == Environment.TONE_MAPPER_REINHARDT ? 1 : mode == Environment.TONE_MAPPER_FILMIC ? 2 : 3);
            cmd.SetGlobalFloat(ID_TonemapParam, param);
            cmd.SetGlobalFloat(ID_White, white);
            cmd.SetGlobalFloat(ID_Exposure, exposure);
            cmd.SetGlobalFloat(ID_UseGlow, glow ? 1 : 0);
            if (glow)
            {
                int gm = env.GlowBlendMode;
                cmd.SetGlobalFloat(ID_GlowMode, gm);
                cmd.SetGlobalFloat(ID_GlowIntensity, gm == Environment.GLOW_BLEND_MODE_MIX ? (float)env.GlowMix : (float)env.GlowIntensity);
                cmd.SetGlobalTexture(ID_Blend, Blur0[2]);
            }
            bool bcs = env != null && env.AdjustmentEnabled;
            cmd.SetGlobalFloat(ID_UseBcs, bcs ? 1 : 0);
            if (bcs) cmd.SetGlobalVector(ID_Bcs, new Vector4((float)env.AdjustmentBrightness, (float)env.AdjustmentContrast, (float)env.AdjustmentSaturation, 0));
            cmd.SetGlobalFloat(ID_Transparent, transparent ? 1 : 0);
            Blit(cmd, ldr, PASS_TONEMAP);
            if (glow) ReleaseGlow(cmd);
            ctx.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            ctx.Submit();
        }

        static int _allocated1, _allocated0;

        /// <summary>The glow chain into Blur0[2] (quarter resolution). False when no level is on.</summary>
        static bool Render(CommandBuffer cmd, RenderTexture hdr, Environment env, int w, int h)
        {
            var levels = env.GlowLevels;
            var lv = new float[7];
            float sum = 0;
            for (int i = 0; i < 7; i++) { lv[i] = i < levels.Count ? levels[i] : 0f; sum += lv[i]; }
            if (env.GlowNormalized && sum != 0) for (int i = 0; i < 7; i++) lv[i] /= sum;
            int maxIdx = -1;
            for (int i = 0; i < 7; i++) if (lv[i] > 0.01f) maxIdx = i;
            if (maxIdx < 0) return false;
            int blur1Mips = Math.Max(1, RequiredMipmaps(w, h) - 1);
            maxIdx = Math.Min(maxIdx, blur1Mips - 1);
            if (maxIdx < 0) return false;
            var fmt = GlowFormat;
            _allocated1 = maxIdx + 2;           // BLUR_1 mips 1 .. maxIdx+1
            _allocated0 = maxIdx + 3;           // BLUR_0 mips 2 .. maxIdx+2
            for (int m = 1; m < _allocated1; m++)
                cmd.GetTemporaryRT(Blur1[m], Shr(w >> 1, m), Shr(h >> 1, m), 0, FilterMode.Bilinear, fmt, RenderTextureReadWrite.Linear);
            for (int m = 2; m < _allocated0; m++)
                cmd.GetTemporaryRT(Blur0[m], Shr(w, m), Shr(h, m), 0, FilterMode.Bilinear, fmt, RenderTextureReadWrite.Linear);

            float strength = (float)env.GlowStrength;
            // gather: the scene -> BLUR_1 mip 1 (quarter resolution)
            cmd.SetGlobalTexture(ID_Source, hdr);
            cmd.SetGlobalVector(ID_SrcSize, new Vector4(w, h, 0, 0));
            cmd.SetGlobalVector(ID_SrcPixelSize, new Vector4(1f / w, 1f / h, 0, 0));
            cmd.SetGlobalFloat(ID_GlowStrength, strength);
            cmd.SetGlobalFloat(ID_GlowExposure, (float)env.TonemapExposure);
            cmd.SetGlobalFloat(ID_GlowBloom, (float)env.GlowBloom);
            cmd.SetGlobalFloat(ID_GlowHdrThreshold, (float)env.GlowHdrThreshold);
            cmd.SetGlobalFloat(ID_GlowHdrScale, (float)env.GlowHdrScale);
            cmd.SetGlobalFloat(ID_GlowLuminanceCap, (float)env.GlowHdrLuminanceCap);
            Blit(cmd, Blur1[1], PASS_GATHER);
            // downsample: BLUR_1 mip i -> mip i+1 (the source's size is the pixel size)
            for (int i = 1; i < maxIdx + 1; i++)
            {
                int sw = Shr(w >> 1, i), sh = Shr(h >> 1, i);
                cmd.SetGlobalTexture(ID_Source, Blur1[i]);
                cmd.SetGlobalVector(ID_SrcPixelSize, new Vector4(1f / sw, 1f / sh, 0, 0));
                cmd.SetGlobalFloat(ID_GlowStrength, strength);
                Blit(cmd, Blur1[i + 1], PASS_DOWN);
            }
            // upsample
            RenderTargetIdentifier source = Blur1[maxIdx + 1];
            if (maxIdx <= 0)
            {
                // only level 0: Godot upsamples black and blends level 0's texture
                cmd.SetGlobalTexture(ID_Source, UnityEngine.Texture2D.blackTexture);
                cmd.SetGlobalVector(ID_SrcPixelSize, new Vector4(1f / Shr(w, 2), 1f / Shr(h, 2), 0, 0));
                cmd.SetGlobalVector(ID_DestPixelSize, new Vector4(1f / Shr(w, 2), 1f / Shr(h, 2), 0, 0));
                cmd.SetGlobalTexture(ID_Blend, Blur1[1]);
                cmd.SetGlobalFloat(ID_GlowLevel, lv[0] * 0.5f);
                cmd.SetGlobalFloat(ID_UseBlend, lv[0] > 0.01f ? 1 : 0);
                cmd.SetGlobalFloat(ID_GlowStrength, 0f);
                Blit(cmd, Blur0[2], PASS_UP);
            }
            for (int i = maxIdx - 1; i >= 0; i--)
            {
                int sw = Shr(w, i + 3), sh = Shr(h, i + 3), dw = Shr(w, i + 2), dh = Shr(h, i + 2);
                cmd.SetGlobalTexture(ID_Source, source);
                cmd.SetGlobalVector(ID_SrcPixelSize, new Vector4(1f / sw, 1f / sh, 0, 0));
                cmd.SetGlobalVector(ID_DestPixelSize, new Vector4(1f / dw, 1f / dh, 0, 0));
                cmd.SetGlobalTexture(ID_Blend, Blur1[i + 1]);
                cmd.SetGlobalFloat(ID_GlowLevel, lv[i] * 0.5f);
                cmd.SetGlobalFloat(ID_UseBlend, lv[i] > 0.01f ? 1 : 0);
                cmd.SetGlobalFloat(ID_GlowStrength, i == maxIdx - 1 ? lv[i + 1] : 1f);
                Blit(cmd, Blur0[i + 2], PASS_UP);
                source = Blur0[i + 2];
            }
            return true;
        }

        static void ReleaseGlow(CommandBuffer cmd)
        {
            for (int m = 1; m < _allocated1; m++) cmd.ReleaseTemporaryRT(Blur1[m]);
            for (int m = 2; m < _allocated0; m++) cmd.ReleaseTemporaryRT(Blur0[m]);
        }
    }
}
