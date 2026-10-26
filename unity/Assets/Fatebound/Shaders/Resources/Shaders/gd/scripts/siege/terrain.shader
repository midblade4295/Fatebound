// Port of res://scripts/siege/terrain.gdshader (the Rift's painted ground): two painted lawns blended by a slow noise,
// flagstone lanes from the mask's A, worn earth from its R, triplanar cliff rock on steep faces and the mask's ledge rims
// (G), the river bed under the water, cliff-foot shadow (B), the outposts' capture rings, the drifting cloud shadows.
// render_mode specular_disabled (diffuse_burley, cull_back by default) -> opaque, lit.
// As Godot: wpos / wnorm are Godot's world-space position and (model-matrix) normal, so the mask rect, the river
// (z = 0), the lawns' turn, the triplanar planes and the rings' centres (posts[i].xy: Godot x, z) all use Godot's
// coordinates. path_mask, macro_tex and cloud_tex have no source_color: read raw (FB_Raw); path_mask is filter_linear
// without mipmaps: sampled at LOD 0, clamped.
// Uniform arrays (posts, post_ring, post_cap) live outside UnityPerMaterial (Material.SetVectorArray), unset = zeros,
// as Godot's (no ring drawn). The local `line` is renamed (an HLSL keyword).
Shader "Fatebound/gd/scripts/siege/terrain"
{
    Properties
    {
        grass_tex ("grass_tex", 2D) = "white" {}
        grass2_tex ("grass2_tex", 2D) = "white" {}
        lane_tex ("lane_tex", 2D) = "white" {}
        path_tex ("path_tex", 2D) = "white" {}
        rock_tex ("rock_tex", 2D) = "white" {}
        bed_tex ("bed_tex", 2D) = "white" {}
        path_mask ("path_mask", 2D) = "white" {}
        mask_rect ("mask_rect", Vector) = (0, 0, 0, 0)
        grass_scale ("grass_scale", Float) = 9
        lane_scale ("lane_scale", Float) = 7.5
        path_scale ("path_scale", Float) = 6
        rock_scale ("rock_scale", Float) = 5
        bed_scale ("bed_scale", Float) = 4.5
        tint ("tint", Vector) = (1, 1, 1, 0)
        grass_sat ("grass_sat", Float) = 1
        cloud_tex ("cloud_tex", 2D) = "white" {}
        cloud_strength ("cloud_strength", Float) = 0
        macro_tex ("macro_tex", 2D) = "white" {}
        rock_col ("rock_col", Vector) = (1, 1, 1, 0)
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 mask_rect;
        float grass_scale;
        float lane_scale;
        float path_scale;
        float rock_scale;
        float bed_scale;
        float4 tint;
        float grass_sat;
        float cloud_strength;
        float4 rock_col;
    CBUFFER_END

    // Outpost capture rings (uniform arrays: set with SetVectorArray, 6 each)
    float4 posts[6];
    float4 post_ring[6];
    float4 post_cap[6];

    TEXTURE2D(grass_tex);
    TEXTURE2D(grass2_tex);
    TEXTURE2D(lane_tex);
    TEXTURE2D(path_tex);
    TEXTURE2D(rock_tex);
    TEXTURE2D(bed_tex);
    TEXTURE2D(path_mask);
    TEXTURE2D(cloud_tex);
    TEXTURE2D(macro_tex);

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS : NORMAL;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float3 wpos : TEXCOORD2;       // Godot's world position
        float3 wnorm : TEXCOORD3;      // Godot's world normal (MODEL_MATRIX * NORMAL, normalised per vertex)
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    Varyings TerrainVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(v.normalOS);
        o.wpos = FB_Mirror(o.positionWS);
        o.wnorm = normalize(FB_Mirror(TransformObjectToWorldDir(v.normalOS, false)));
        return o;
    }
    ENDHLSL

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" "Queue" = "Geometry" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Back
            ZWrite On
            ZTest LEqual
            Blend Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex TerrainVert
            #pragma fragment TerrainFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 TerrainFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float TIME = _FB_Time;
                float3 wpos = i.wpos;
                float3 wnorm = i.wnorm;
                float4 mk = FB_Raw(FB_SAMPLE_LOD(path_mask, sampler_LinearClamp, (wpos.xz - mask_rect.xy) / mask_rect.zw, 0.0));
                float m1 = FB_Raw(FB_SAMPLE(macro_tex, sampler_TrilinearRepeat, wpos.xz / 31.0)).r;
                float m2 = FB_Raw(FB_SAMPLE(macro_tex, sampler_TrilinearRepeat, wpos.xz / 83.0 + float2(0.31, 0.17))).r;
                float3 g1 = FB_SAMPLE(grass_tex, sampler_TrilinearRepeat, wpos.xz / grass_scale).rgb;
                // TURN = mat2(vec2(0.4536, 0.8912), vec2(-0.8912, 0.4536)) (GLSL columns): the second lawn laid 63 degrees round
                float2 turned = float2(0.4536 * wpos.x - 0.8912 * wpos.z, 0.8912 * wpos.x + 0.4536 * wpos.z);
                float3 g2 = FB_SAMPLE(grass2_tex, sampler_TrilinearRepeat, turned / (grass_scale * 1.17)).rgb;
                float3 g = lerp(g1, g2, smoothstep(0.38, 0.62, m1));
                g = lerp(float3(0.30, 0.52, 0.25), g, 0.72);           // the painting's strokes a little softer at this distance
                // broad painted light: sunlit yellow-green meadows and cooler blue-green hollows
                g *= lerp(float3(0.88, 0.95, 1.02), float3(1.08, 1.05, 0.92), smoothstep(0.3, 0.72, m2));
                float gl = dot(g, float3(0.299, 0.587, 0.114));
                g = lerp(gl.xxx, g, grass_sat);
                float3 col = g;
                float n2 = FB_Raw(FB_SAMPLE(macro_tex, sampler_TrilinearRepeat, wpos.xz / 2.3 + float2(0.37, 0.71))).r;
                if (mk.r > 0.02)
                {
                    // earth: the jungle trails and the pits' trodden arenas
                    float3 p = FB_SAMPLE(path_tex, sampler_TrilinearRepeat, wpos.xz / path_scale).rgb;
                    p = lerp(dot(p, float3(0.299, 0.587, 0.114)).xxx, p, 0.72) * float3(0.96, 0.95, 1.0);   // earthier, less orange
                    p *= 0.92 + 0.16 * m1;
                    float edge = mk.r + (g.g - 0.5) * 0.22 + (n2 - 0.5) * 0.3;
                    float dirt = smoothstep(0.47, 0.53, edge);
                    float inner = smoothstep(0.5, 0.9, mk.r);
                    p *= lerp(0.86, 1.04, inner);                       // damp, darker earth by the grass; dusty middle
                    col = lerp(g * (1.0 - 0.12 * smoothstep(0.25, 0.47, edge)), p, dirt);
                }
                if (mk.a > 0.05)
                {
                    // a lane's flagstones: whole slabs at its edge, the joints stay grass
                    float3 s = FB_SAMPLE(lane_tex, sampler_TrilinearRepeat, wpos.xz / lane_scale).rgb;
                    float slab = 1.0 - clamp((s.g - max(s.r, s.b)) * 9.0, 0.0, 1.0);    // grey slab 1, green joint 0
                    float e = mk.a + 0.16 * slab - 0.08 + (n2 - 0.5) * 0.12;
                    float stone = smoothstep(0.5, 0.56, e);
                    s *= 0.94 + 0.12 * m1;
                    col *= 1.0 - 0.1 * smoothstep(0.3, 0.5, e);
                    col = lerp(col, s, stone);
                }
                // Rock: the painted cliff stone, triplanar, on steep faces and the ledge rims, moss where a face turns up.
                float steep = 1.0 - clamp(wnorm.y, 0.0, 1.0);
                float jit = (m1 - 0.5) * 0.24 + (g.g - 0.5) * 0.3;
                float rockw = smoothstep(0.30, 0.52, steep + jit);
                float rimw = mk.g > 0.15 ? smoothstep(0.44, 0.58, mk.g + jit * 1.2) : 0.0;
                float rw = max(rockw, rimw);
                if (rw > 0.001)
                {
                    float3 an = pow(abs(wnorm), 4.0);
                    an /= (an.x + an.y + an.z);
                    float3 r = FB_SAMPLE(rock_tex, sampler_TrilinearRepeat, float2(wpos.z, -wpos.y) / rock_scale).rgb * an.x
                        + FB_SAMPLE(rock_tex, sampler_TrilinearRepeat, wpos.xz / rock_scale).rgb * an.y
                        + FB_SAMPLE(rock_tex, sampler_TrilinearRepeat, float2(wpos.x, -wpos.y) / rock_scale).rgb * an.z;
                    r *= rock_col.rgb;
                    float moss = smoothstep(0.6, 0.9, wnorm.y) * smoothstep(0.42, 0.62, m1 + (g.g - 0.5));
                    r = lerp(r, g * 0.9, moss * 0.65);
                    col = lerp(col, r, rw);
                }
                // the river bed under the water (the river runs along z = 0; not the paving of a lane's ford)
                if (wpos.y < -0.04 && abs(wpos.z) < 15.0 && mk.a < 0.5)
                {
                    float3 b = FB_SAMPLE(bed_tex, sampler_TrilinearRepeat, wpos.xz / bed_scale).rgb;
                    col = lerp(col, b, smoothstep(-0.04, -0.22, wpos.y));
                }
                col *= 1.0 - 0.38 * mk.b;                          // shadow at the cliff foot
                [loop]
                for (int k = 0; k < 6; k++)
                {
                    float rr = posts[k].z;
                    if (rr <= 0.0) { continue; }
                    float d = distance(wpos.xz, posts[k].xy);
                    if (d > rr + 0.6) { continue; }
                    float ring_line = 1.0 - smoothstep(0.12, 0.26, abs(d - rr));
                    float dash = 0.75 + 0.25 * step(0.5, frac(atan2(wpos.z - posts[k].y, wpos.x - posts[k].x) * 5.0));
                    col = lerp(col, post_ring[k].rgb, ring_line * post_ring[k].a * dash);
                    col = lerp(col, post_ring[k].rgb, (1.0 - smoothstep(rr - 1.2, rr, d)) * step(d, rr) * 0.10 * post_ring[k].a);
                    float fill = (1.0 - smoothstep(rr * posts[k].w - 0.08, rr * posts[k].w + 0.08, d)) * post_cap[k].a;
                    col = lerp(col, post_cap[k].rgb, fill);
                }
                float cl = smoothstep(0.46, 0.74, FB_Raw(FB_SAMPLE(cloud_tex, sampler_TrilinearRepeat, wpos.xz / 95.0 + float2(TIME * 0.006, TIME * 0.0035))).r);

                FBSurface surf = FB_GodotSurface(i.positionWS, normalize(i.normalWS));
                surf.albedo = FB_ApplyDecals(col * tint.rgb * (1.0 - cloud_strength * cl), i.positionWS, surf.normalWS);
                surf.roughness = lerp(0.95, 0.88, rw);
                surf.specularOn = 0.0;
                float3 c = FB_Shade(surf, GetNormalizedScreenSpaceUV(i.positionCS));
                c = FB_MixFog(c, i.positionWS);
                return float4(c, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex TerrainShadowVert
            #pragma fragment TerrainShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings TerrainShadowVert(Attributes v)
            {
                Varyings o = TerrainVert(v);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - o.positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(o.positionWS, o.normalWS, lightDirectionWS)));
                return o;
            }

            float4 TerrainShadowFrag(Varyings i) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On
            ColorMask R
            Cull Back

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex TerrainVert
            #pragma fragment TerrainDepthFrag
            #pragma multi_compile_instancing

            float4 TerrainDepthFrag(Varyings i) : SV_Target
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
