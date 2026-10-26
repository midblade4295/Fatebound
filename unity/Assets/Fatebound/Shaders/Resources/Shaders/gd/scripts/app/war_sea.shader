// Port of res://scripts/app/war_sea.gdshader (the sea round the war map's land, war_land_view.gd): its colour from the
// depth under it (the land's height in region_lin's A), waves from two drifting noise layers, foam breathing along the
// shore, cloud shadows; cut to an oval (disc) on Home's table.
// render_mode blend_mix, specular_schlick_ggx, cull_disabled (diffuse_burley by default) -> transparent (ALPHA), Godot's
// mix blend, no depth write (depth_draw_opaque with alpha), both faces, lit, NORMAL_MAP with NORMAL_MAP_DEPTH.
// As Godot: `world` is to_map * MODEL_MATRIX * VERTEX in Godot's space (to_map is a Godot mat4 in Godot's column layout;
// a material that never set it reads Unity's zero matrix, taken as Godot's default mat4(1.0)). The normal map bends the
// side-checked normal along the mesh's tangent and binormal (Godot's DO_SIDE_CHECK flips only the normal).
// wave_tex and cloud_tex have no source_color: read raw (FB_Raw); region_lin's A is never sRGB-decoded.
// to_map is outside UnityPerMaterial (no Properties entry for a matrix).
Shader "Fatebound/gd/scripts/app/war_sea"
{
    Properties
    {
        region_lin ("region_lin", 2D) = "white" {}
        wave_tex ("wave_tex", 2D) = "white" {}
        cloud_tex ("cloud_tex", 2D) = "white" {}
        map_rect ("map_rect", Vector) = (0, 0, 0, 0)
        h_min ("h_min", Float) = -0.4
        h_max ("h_max", Float) = 2.15
        shallow ("shallow", Color) = (0.3, 0.72, 0.74, 1)
        deep ("deep", Color) = (0.06, 0.22, 0.42, 1)
        far ("far", Color) = (0.05, 0.14, 0.3, 1)
        wind ("wind", Vector) = (0.012, 0.006, 0, 0)
        disc ("disc", Vector) = (0, 0, 0, 0)
        glow ("glow", Float) = 0
        wave_scale ("wave_scale", Float) = 1
        spec ("spec", Float) = 0.55
        rough ("rough", Float) = 0.18
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 map_rect;
        float h_min;
        float h_max;
        float4 shallow;
        float4 deep;
        float4 far;
        float4 wind;
        float4 disc;
        float glow;
        float wave_scale;
        float spec;
        float rough;
    CBUFFER_END

    float4x4 to_map;      // Godot's mat4 (SetMatrix, Godot's column layout); unset (all zero) = identity

    TEXTURE2D(region_lin);
    TEXTURE2D(wave_tex);
    TEXTURE2D(cloud_tex);

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS : NORMAL;
        float4 tangentOS : TANGENT;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float4 tangentWS : TEXCOORD2;
        float3 world : TEXCOORD3;      // Godot's to_map * MODEL_MATRIX * VERTEX
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    float3 SeaToMap(float3 positionWS)
    {
        float4x4 m = to_map;
        if (m._m33 == 0.0 && m._m00 == 0.0)
        {
            m = float4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        }
        return mul(m, float4(FB_Mirror(positionWS), 1.0)).xyz;
    }

    Varyings SeaVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(v.normalOS);
        o.tangentWS = float4(TransformObjectToWorldDir(v.tangentOS.xyz), v.tangentOS.w * GetOddNegativeScale());
        o.world = SeaToMap(o.positionWS);
        return o;
    }
    ENDHLSL

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Transparent" "Queue" = "Transparent" "IgnoreProjector" = "True" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Off
            ZWrite Off
            ZTest LEqual
            Blend SrcAlpha OneMinusSrcAlpha, One OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex SeaVert
            #pragma fragment SeaFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 SeaFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 world = i.world;
                if (disc.x > 0.0 && length(world.xz / disc.xy) > 1.0)
                {
                    discard;
                }
                float2 muv = (world.xz - map_rect.xy) / map_rect.zw;
                float inside = step(0.0, muv.x) * step(0.0, muv.y) * step(muv.x, 1.0) * step(muv.y, 1.0);
                float ground = lerp(h_min, FB_SAMPLE_LOD(region_lin, sampler_LinearRepeat, clamp(muv, 0.0, 1.0), 0.0).a * (h_max - h_min) + h_min, inside);
                float depth = max(0.0, -ground);
                float t = _FB_Time;
                float2 p = world.xz * wave_scale;
                float w1 = FB_Raw(FB_SAMPLE(wave_tex, sampler_TrilinearRepeat, p * 0.22 + float2(t * 0.025, t * 0.011))).r;
                float w2 = FB_Raw(FB_SAMPLE(wave_tex, sampler_TrilinearRepeat, p * 0.37 - float2(t * 0.018, -t * 0.021))).r;
                float waves = w1 + w2;
                float3 col = lerp(shallow.rgb, deep.rgb, smoothstep(0.0, 0.11, depth));
                float off = length(max(abs(muv - 0.5) - 0.5, 0.0));
                col = lerp(col, far.rgb, smoothstep(0.0, 0.25, off));
                col += float3(0.025, 0.035, 0.04) * (waves - 1.0);
                // a glint where the waves catch the light
                col += float3(0.5, 0.55, 0.5) * smoothstep(0.86, 0.95, w1 * w2 * 1.6) * 0.12;
                // foam: a band along the shore that breathes, broken up by the waves
                float shore = 1.0 - smoothstep(0.0, 0.07, depth);
                float breathe = 0.6 + 0.4 * sin(t * 1.6 + (w1 * 6.0));
                float foam = shore * smoothstep(0.45, 0.75, w2 * breathe + shore * 0.35) * inside;
                col = lerp(col, float3(0.94, 0.98, 1.0), foam * 0.85);
                float c = FB_Raw(FB_SAMPLE(cloud_tex, sampler_TrilinearRepeat, world.xz * 0.045 + t * wind.xy)).r;
                col *= 1.0 - 0.22 * smoothstep(0.52, 0.78, c);
                float alpha = lerp(0.72, 1.0, smoothstep(0.0, 0.2, depth));
                // gentle normals from the waves
                float3 normalMap = normalize(float3(w1 - 0.5, w2 - 0.5, 2.5)) * 0.5 + 0.5;
                float3 n = FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0));
                float3 tangent = i.tangentWS.xyz;
                float3 binormal = cross(normalize(i.normalWS), tangent) * i.tangentWS.w;
                n = FB_ApplyNormalMap(n, tangent, binormal, normalMap, 0.6);

                FBSurface s = FB_GodotSurface(i.positionWS, n);
                s.albedo = FB_ApplyDecals(col, i.positionWS, FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0)));   // (geo normal: before the normal map)
                s.alpha = alpha;
                s.emission = col * glow;
                s.roughness = rough;
                s.specular = spec;
                float3 lit = FB_Shade(s, GetNormalizedScreenSpaceUV(i.positionCS));
                lit = FB_MixFog(lit, i.positionWS);
                return float4(lit, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
