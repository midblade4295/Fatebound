// Port of the inline shader siege_view.gd's _water_hq_material builds (the High-quality river: a simulated wave field,
// rip_tex, stepped on the GPU by siege_view_ripples): the surface rises and falls with the waves (held at the banks,
// UV2.y), flowing detail from two scrolling noise layers (the river runs toward Godot's -x), the waves' slopes as the
// normal, see-through over the bed, a sky sheen at grazing angles, sun glints.
// render_mode cull_disabled, blend_mix, depth_draw_opaque (diffuse_burley, specular_schlick_ggx by default) ->
// transparent (ALPHA), Godot's mix blend, no depth write (alpha with depth_draw_opaque), both faces, lit.
// As Godot: wpos is Godot's world position (the wave field's x mapping and the flow use Godot's x); the written NORMAL
// (VIEW_MATRIX * wn, a Godot world normal) is the mirror of wn in Unity's world; it replaces the side-checked one on
// both faces, as in Godot. ripples has no source_color: read raw (FB_Raw). rip_tex is read as stored (a float wave
// field the ripple pass renders; see the report about 2D SubViewports).
Shader "Fatebound/gd/inline/siege_view_water_hq"
{
    Properties
    {
        ripples ("ripples", 2D) = "white" {}
        rip_tex ("rip_tex", 2D) = "black" {}
        rip_half ("rip_half", Float) = 34
        rip_texel ("rip_texel", Vector) = (0.001953, 0.019231, 0, 0)
        rip_strength ("rip_strength", Float) = 28
        wake_tint ("wake_tint", Float) = 4.5
        deep_col ("deep_col", Color) = (0.05, 0.33, 0.40, 1)
        shallow_col ("shallow_col", Color) = (0.26, 0.66, 0.62, 1)
        sky_col ("sky_col", Color) = (0.62, 0.80, 0.95, 1)
        glint ("glint", Float) = 0
        wave_height ("wave_height", Float) = 1.5
    }

    HLSLINCLUDE
    #include "../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float rip_half;
        float4 rip_texel;
        float rip_strength;
        float wake_tint;
        float4 deep_col;
        float4 shallow_col;
        float4 sky_col;
        float glint;
        float wave_height;
    CBUFFER_END

    TEXTURE2D(ripples);
    TEXTURE2D(rip_tex);

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS : NORMAL;
        float2 uv : TEXCOORD0;
        float2 uv2 : TEXCOORD1;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 positionWS : TEXCOORD0;
        float3 wpos : TEXCOORD1;       // Godot's world position (risen with the waves)
        float2 uv : TEXCOORD2;
        float2 uv2 : TEXCOORD3;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    float water_bad(float x)
    {
        return (isnan(x) || isinf(x)) ? 1.0 : 0.0;
    }

    Varyings WaterVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        float3 p = v.positionOS.xyz;
        float3 wpos = FB_Mirror(TransformObjectToWorld(p));
        float2 ruv = float2((wpos.x + rip_half) / (2.0 * rip_half), v.uv.y);
        float inside = step(0.0, ruv.x) * step(ruv.x, 1.0);
        float h = FB_SAMPLE_LOD(rip_tex, sampler_LinearClamp, ruv, 0.0).r * inside;
        h = water_bad(h) > 0.5 ? 0.0 : h;
        float edge = smoothstep(0.0, 0.1, v.uv2.y) * smoothstep(1.0, 0.9, v.uv2.y);     // held at the banks
        p.y += h * wave_height * edge;                // VERTEX.y (y is the same in both spaces)
        wpos.y += h * wave_height * edge;
        o.positionWS = TransformObjectToWorld(p);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.wpos = wpos;
        o.uv = v.uv;
        o.uv2 = v.uv2;
        return o;
    }

    float water_detail(float2 p)
    {
        float TIME = _FB_Time;
        return FB_Raw(FB_SAMPLE(ripples, sampler_TrilinearRepeat, p * 0.11 + float2(-TIME * 0.035, 0.0))).r * 0.6
            + FB_Raw(FB_SAMPLE(ripples, sampler_TrilinearRepeat, p * 0.23 + float2(-TIME * 0.05, TIME * 0.02))).r * 0.4;
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
            #pragma vertex WaterVert
            #pragma fragment WaterFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 WaterFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float TIME = _FB_Time;
                float3 wpos = i.wpos;
                float2 UV = i.uv;
                float2 UV2 = i.uv2;
                // Flowing detail (the river runs toward -x) from finite differences of two scrolling layers.
                float e = 0.2;
                float d0 = water_detail(wpos.xz);
                float2 slope = float2(water_detail(wpos.xz + float2(e, 0.0)) - d0, water_detail(wpos.xz + float2(0.0, e)) - d0) / e * 0.22;
                // The simulated waves.
                float2 ruv = float2((wpos.x + rip_half) / (2.0 * rip_half), UV.y);
                float inside = step(0.0, ruv.x) * step(ruv.x, 1.0);
                float h = FB_SAMPLE_LOD(rip_tex, sampler_LinearClamp, ruv, 0.0).r * inside;
                float hx = (FB_SAMPLE_LOD(rip_tex, sampler_LinearClamp, ruv + float2(rip_texel.x, 0.0), 0.0).r
                    - FB_SAMPLE_LOD(rip_tex, sampler_LinearClamp, ruv - float2(rip_texel.x, 0.0), 0.0).r) * inside;
                float hz = (FB_SAMPLE_LOD(rip_tex, sampler_LinearClamp, ruv + float2(0.0, rip_texel.y), 0.0).r
                    - FB_SAMPLE_LOD(rip_tex, sampler_LinearClamp, ruv - float2(0.0, rip_texel.y), 0.0).r) * inside;
                if (water_bad(h + hx + hz) > 0.5) { h = 0.0; hx = 0.0; hz = 0.0; }
                slope += clamp(float2(hx, hz) * rip_strength, -1.5, 1.5);
                float3 wn = normalize(float3(-slope.x, 1.0, -slope.y));          // Godot's world normal
                float3 N = normalize(FB_Mirror(wn));                             // NORMAL = VIEW_MATRIX * wn
                float3 VIEW = normalize(GetWorldSpaceViewDir(i.positionWS));
                float edge = min(UV2.y, 1.0 - UV2.y);
                float depth = smoothstep(0.02, 0.4, edge);
                float3 col = lerp(shallow_col.rgb, deep_col.rgb, depth);
                float fres = pow(1.0 - clamp(dot(N, VIEW), 0.0, 1.0), 4.0);
                col = lerp(col, sky_col.rgb, clamp(fres * 0.3, 0.0, 0.25));
                // No foam: the wakes read as light crests and dark troughs.
                col *= 1.0 + clamp(h, -0.12, 0.12) * wake_tint;
                float alpha = lerp(0.38, 0.66, depth);
                float sg = FB_Raw(FB_SAMPLE(ripples, sampler_TrilinearRepeat, wpos.xz * 0.19 + float2(-TIME * 0.09, TIME * 0.05))).r
                    * FB_Raw(FB_SAMPLE(ripples, sampler_TrilinearRepeat, wpos.xz * 0.13 + float2(TIME * 0.07, -TIME * 0.04))).r;

                FBSurface s = FB_GodotSurface(i.positionWS, N);
                s.albedo = FB_ApplyDecals(col, i.positionWS, N);
                s.alpha = alpha;
                s.roughness = 0.16;
                s.specular = 0.35;
                s.emission = float3(1.0, 0.97, 0.88) * smoothstep(0.58, 0.64, sg) * glint;
                float3 c = FB_Shade(s, GetNormalizedScreenSpaceUV(i.positionCS));
                c = FB_MixFog(c, i.positionWS);
                return float4(c, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
