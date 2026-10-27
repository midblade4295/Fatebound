// Fatebound (Unity port): Godot 4's Mobile-renderer post chain for a 3D viewport (PostChain.cs drives it).
//  pass 0  glow gather      blur_raster.glsl MODE_GLOW_GATHER  (full res -> quarter, threshold / bloom)
//  pass 1  glow downsample  blur_raster.glsl MODE_GLOW_DOWNSAMPLE
//  pass 2  glow upsample    blur_raster.glsl MODE_GLOW_UPSAMPLE
//  pass 3  tonemap          tonemap_mobile.glsl (exposure, glow, tonemapper, adjustments)
// Godot's Mobile renderer keeps the scene in an RGB10A2 buffer holding colour / 2: every value it reads is clamped
// to [0, 2] -- reproduced here (FB_BUF) on the scene and on every glow level, so highlights glow as they did.
// Pixel addressing is by SV_Position like Godot's gl_FragCoord (memory rows on every API: no flips needed).
// The output is sRGB-encoded (Godot's convert_to_srgb) into the viewport's raw RGBA8 texture: Godot's 2D colour space,
// where the viewport's own canvas is drawn on top and the GUI samples it.
Shader "Hidden/Fatebound/Post"
{
    HLSLINCLUDE
    Texture2D _Source;
    Texture2D _Blend;
    SamplerState sampler_linear_clamp;

    float4 _SrcPixelSize;      // xy: 1 / source size
    float4 _DestPixelSize;     // xy: 1 / destination size
    float4 _SrcSize;           // xy: source size in pixels
    // glow
    float _GlowStrength, _GlowBloom, _GlowHdrThreshold, _GlowHdrScale, _GlowExposure, _GlowLuminanceCap;
    float _GlowLevel, _UseBlend;
    // tonemap
    float _Exposure, _White, _TonemapParam, _Tonemapper;   // tonemapper: 0 linear 1 reinhard 2 filmic 3 aces
    float _UseGlow, _GlowMode, _GlowIntensity;            // glow mode: 0 add 1 screen 2 softlight 3 replace 4 mix
    float _UseBcs;
    float4 _Bcs;                                           // brightness, contrast, saturation
    float _Transparent;

    #define FB_BUF(c) clamp(c, 0.0, 2.0)

    struct V2F { float4 pos : SV_POSITION; };

    V2F vert(uint id : SV_VertexID)
    {
        V2F o;
        float2 b = id == 0 ? float2(-1.0, -1.0) : (id == 1 ? float2(-1.0, 3.0) : float2(3.0, -1.0));
        o.pos = float4(b, 0.0, 1.0);
        return o;
    }
    ENDHLSL

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Cull Off ZWrite Off ZTest Always Blend Off

        // 0: gather -- the 4x4 block's average (Godot's four bilinear taps at pixel corners), each texel clamped to the
        // scene buffer's range first, then strength^2, exposure, the HDR threshold / bloom, the luminance cap
        Pass
        {
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            float4 frag(V2F i) : SV_Target
            {
                float2 size = _SrcSize.xy;
                float2 block = floor(i.pos.xy) * 4.0;
                float2 end = max(size - float2(4.0, 4.0), float2(0.0, 0.0));
                int2 b = (int2)clamp(block, float2(0.0, 0.0), end);
                int2 mx = (int2)size - 1;
                float4 c = 0;
                [unroll] for (int y = 0; y < 4; y++)
                    [unroll] for (int x = 0; x < 4; x++)
                        c += FB_BUF(_Source.Load(int3(min(b + int2(x, y), mx), 0)));
                c *= 1.0 / 16.0;
                c *= _GlowStrength;
                c *= _GlowStrength;
                c *= _GlowExposure;
                float luminance = max(c.r, max(c.g, c.b));
                float feedback = max(smoothstep(_GlowHdrThreshold, _GlowHdrThreshold + _GlowHdrScale, luminance), _GlowBloom);
                c = min(c * feedback, _GlowLuminanceCap.xxxx);
                return FB_BUF(c);
            }
            ENDHLSL
        }

        // 1: downsample (BloomDownKernel4) * strength
        Pass
        {
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            float4 frag(V2F i) : SV_Target
            {
                float2 rcp = _SrcPixelSize.xy;
                float2 tc = (floor(i.pos.xy) * 2.0 + 1.0) * rcp;
                float2 o = (0.5 + 0.25) * rcp;
                float4 c = 0;
                c += _Source.SampleLevel(sampler_linear_clamp, tc + float2(-1.0, -1.0) * o, 0) * 0.25;
                c += _Source.SampleLevel(sampler_linear_clamp, tc + float2(1.0, -1.0) * o, 0) * 0.25;
                c += _Source.SampleLevel(sampler_linear_clamp, tc + float2(-1.0, 1.0) * o, 0) * 0.25;
                c += _Source.SampleLevel(sampler_linear_clamp, tc + float2(1.0, 1.0) * o, 0) * 0.25;
                c *= _GlowStrength;
                return FB_BUF(c);
            }
            ENDHLSL
        }

        // 2: upsample (BloomUpKernel4) * base strength + the level's own downsampled texture * level
        Pass
        {
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            float4 frag(V2F i) : SV_Target
            {
                float2 rcp = _SrcPixelSize.xy;
                float2 uv = floor(i.pos.xy) * 0.5 + 0.5;
                float2 uvI = floor(uv);
                float2 uvF = uv - uvI;
                float2 tc = uvI * rcp;
                const float lw = 0.357386;
                const float la = 25.0 / 32.0;
                const float lb = 3.0 / 64.0;
                float2 l = float2(-1.5 + la, 0.5 + lb);
                float2 lx = uvF.x == 0.0 ? l.xy : -l.yx;
                float2 ly = uvF.y == 0.0 ? l.xy : -l.yx;
                lx *= rcp.xx;
                ly *= rcp.yy;
                float4 c00 = _Source.SampleLevel(sampler_linear_clamp, tc + float2(lx.x, ly.x), 0);
                float4 c10 = _Source.SampleLevel(sampler_linear_clamp, tc + float2(lx.y, ly.x), 0);
                float4 c01 = _Source.SampleLevel(sampler_linear_clamp, tc + float2(lx.x, ly.y), 0);
                float4 c11 = _Source.SampleLevel(sampler_linear_clamp, tc + float2(lx.y, ly.y), 0);
                float2 w = abs(uvF * 2.0 - lw);
                float4 cx0 = c00 * (1.0 - w.x) + (c10 * w.x);
                float4 cx1 = c01 * (1.0 - w.x) + (c11 * w.x);
                float4 c = (cx0 * (1.0 - w.y) + (cx1 * w.y)) * _GlowStrength;
                if (_UseBlend > 0.5)
                {
                    float2 buv = (floor(i.pos.xy) + 0.5) * _DestPixelSize.xy;
                    c += _Blend.SampleLevel(sampler_linear_clamp, buv, 0) * _GlowLevel;
                }
                return FB_BUF(c);
            }
            ENDHLSL
        }

        // 3: tonemap
        Pass
        {
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag

            // (written per channel with plain selects: the shader compilers Unity uses for Vulkan and GLES don't all take a
            // bool vector as lerp's weight)
            float linear_to_srgb1(float c)
            {
                return c < 0.0031308 ? 12.92 * c : 1.055 * pow(max(c, 0.0), 1.0 / 2.4) - 0.055;
            }

            float3 linear_to_srgb(float3 color)
            {
                return float3(linear_to_srgb1(color.r), linear_to_srgb1(color.g), linear_to_srgb1(color.b));
            }

            float3 tonemap_reinhard(float3 color)
            {
                float white_squared = _TonemapParam;
                return color * (1.0 + color / white_squared) / (1.0 + color);   // (output_max_value 1)
            }

            float3 tonemap_filmic(float3 color)
            {
                const float exposure_bias = 2.0;
                const float A = 0.22 * exposure_bias * exposure_bias;
                const float B = 0.30 * exposure_bias;
                const float C = 0.10;
                const float D = 0.20;
                const float E = 0.01;
                const float F = 0.30;
                float3 t = ((color * (A * color + C * B) + D * E) / (color * (A * color + B) + D * F)) - E / F;
                return t / _TonemapParam;
            }

            float3 tonemap_aces(float3 color)
            {
                const float exposure_bias = 1.8;
                const float A = 0.0245786;
                const float B = 0.000090537;
                const float C = 0.983729;
                const float D = 0.432951;
                const float E = 0.238081;
                // GLSL mat3(cols) * as a row vector == HLSL rows dotted with the vector
                const float3x3 rgb_to_rrt = float3x3(
                    0.59719 * exposure_bias, 0.35458 * exposure_bias, 0.04823 * exposure_bias,
                    0.07600 * exposure_bias, 0.90834 * exposure_bias, 0.01566 * exposure_bias,
                    0.02840 * exposure_bias, 0.13383 * exposure_bias, 0.83777 * exposure_bias);
                const float3x3 odt_to_rgb = float3x3(
                    1.60475, -0.53108, -0.07367,
                    -0.10208, 1.10813, -0.00605,
                    -0.00327, -0.07276, 1.07602);
                color = mul(rgb_to_rrt, color);
                float3 t = (color * (color + A) - B) / (color * (C * color + D) + E);
                t = mul(odt_to_rgb, t);
                return t / _TonemapParam;
            }

            float3 apply_tonemapping(float3 color)
            {
                if (_Tonemapper < 0.5) return color;
                color = max(float3(0.0, 0.0, 0.0), color);
                if (_Tonemapper < 1.5) return tonemap_reinhard(color);
                if (_Tonemapper < 2.5) return tonemap_filmic(color);
                return tonemap_aces(color);
            }

            float3 apply_glow(float3 color, float3 glow, float white)
            {
                if (_GlowMode < 0.5) return color + glow;                          // additive
                if (_GlowMode < 1.5)                                               // screen
                {
                    glow = clamp(glow, float3(0.0, 0.0, 0.0), float3(white, white, white));
                    return color + glow - (color * glow / white);
                }
                if (_GlowMode < 2.5)                                               // softlight
                {
                    glow = saturate(glow);
                    color.r = color.r > 1.0 ? color.r : color.r + glow.r * ((color.r <= 0.25 ? ((16.0 * color.r - 12.0) * color.r + 4.0) * color.r : sqrt(color.r)) - color.r);
                    color.g = color.g > 1.0 ? color.g : color.g + glow.g * ((color.g <= 0.25 ? ((16.0 * color.g - 12.0) * color.g + 4.0) * color.g : sqrt(color.g)) - color.g);
                    color.b = color.b > 1.0 ? color.b : color.b + glow.b * ((color.b <= 0.25 ? ((16.0 * color.b - 12.0) * color.b + 4.0) * color.b : sqrt(color.b)) - color.b);
                    return color;
                }
                return glow;                                                       // replace
            }

            float3 gather_glow(float2 pos)
            {
                float2 uv = pos * _DestPixelSize.xy;
                return _Blend.SampleLevel(sampler_linear_clamp, uv, 0).rgb;
            }

            float4 frag(V2F i) : SV_Target
            {
                float4 color = _Source.Load(int3(int2(i.pos.xy), 0));
                color.rgb = FB_BUF(color.rgb);
                color.a = saturate(color.a);
                color.rgb *= _Exposure;
                bool softlight = _GlowMode > 1.5 && _GlowMode < 2.5;
                if (_UseGlow > 0.5 && !softlight)
                {
                    float3 glow = gather_glow(i.pos.xy) * _GlowIntensity;
                    if (_GlowMode > 3.5) color.rgb = color.rgb * (1.0 - _GlowIntensity) + glow;     // mix
                    else color.rgb = apply_glow(color.rgb, glow, _White);
                }
                color.rgb = apply_tonemapping(color.rgb);
                if (_UseGlow > 0.5 && softlight)
                {
                    float3 glow = gather_glow(i.pos.xy) * _GlowIntensity;
                    glow = apply_tonemapping(glow);
                    color.rgb = apply_glow(color.rgb, glow, _White);
                }
                if (_UseBcs > 0.5)
                {
                    color.rgb = color.rgb * _Bcs.x;
                    color.rgb = linear_to_srgb(color.rgb);
                    color.rgb = lerp(float3(0.5, 0.5, 0.5), color.rgb, _Bcs.y);
                    float grey = (color.r + color.g + color.b) * (1.0 / 3.0);
                    color.rgb = lerp(float3(grey, grey, grey), color.rgb, _Bcs.z);
                    color.rgb = saturate(color.rgb);
                }
                else color.rgb = linear_to_srgb(saturate(color.rgb));     // convert_to_srgb
                if (_Transparent < 0.5) color.a = 1.0;
                return color;
            }
            ENDHLSL
        }
    }
}
