// Port of res://scripts/siege/plasma_beam.gdshader (the Necromancer's siphon, siege_view.gd): a unit cylinder stretched
// between the ends, UV.x round it, UV.y along it; two twisting wave trains and a value noise make the plasma, pulses
// run along it, the sides fade (view-facing), both ends fade. core 1: the thin bright core instead of the sheath.
// render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled -> transparent (ALPHA), Godot's mix
// blend, no depth write, both faces. Fog is NOT disabled: Godot's fog is mixed over it, as here.
// As Godot: beam_len is an instance uniform (per renderer, MaterialPropertyBlock); facing = |dot(NORMAL, VIEW)| in
// world space.
Shader "Fatebound/gd/scripts/siege/plasma_beam"
{
    Properties
    {
        plasma_color ("plasma_color", Color) = (0.22, 0.95, 0.35, 1)
        deep_color ("deep_color", Color) = (0.26, 0.02, 0.48, 1)
        hot_color ("hot_color", Color) = (0.86, 1.0, 0.74, 1)
        flow_speed ("flow_speed", Float) = 1
        flow_dir ("flow_dir", Float) = 1
        twist ("twist", Float) = 2
        intensity ("intensity", Float) = 1.5
        softness ("softness", Float) = 1.4
        core ("core", Float) = 0
        beam_len ("beam_len (instance)", Float) = 5
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 plasma_color;
        float4 deep_color;
        float4 hot_color;
        float flow_speed;
        float flow_dir;
        float twist;
        float intensity;
        float softness;
        float core;
        float beam_len;
    CBUFFER_END

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS : NORMAL;
        float2 uv : TEXCOORD0;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float2 uv : TEXCOORD2;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    float plasma_hash21(float2 p)
    {
        p = frac(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return frac(p.x * p.y);
    }

    float plasma_vnoise(float2 p)
    {
        float2 i = floor(p);
        float2 f = frac(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        float a = plasma_hash21(i);
        float b = plasma_hash21(i + float2(1.0, 0.0));
        float c = plasma_hash21(i + float2(0.0, 1.0));
        float d = plasma_hash21(i + float2(1.0, 1.0));
        return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
    }

    Varyings PlasmaVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(v.normalOS);
        o.uv = v.uv;
        return o;
    }

    float4 PlasmaFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
    {
        UNITY_SETUP_INSTANCE_ID(i);
        float2 UV = i.uv;
        float t = _FB_Time * flow_speed;
        float along = UV.y * beam_len;
        float around = UV.x * 6.2831853;
        float s = along * flow_dir;

        // two wave trains twisting round the beam in opposite senses, warped by each other
        float w1 = sin(s * 2.6 + t * 5.0 + around * twist);
        float w2 = sin(s * 4.3 + t * 7.5 - around * (twist + 1.0) + 1.4 * sin(s * 1.1 + t * 2.0));
        float n = plasma_vnoise(float2(s * 1.8 + t * 4.0, UV.x * 7.0)) * 0.7 + plasma_vnoise(float2(s * 5.0 + t * 9.0, UV.x * 15.0)) * 0.3;
        float plasma = clamp(0.5 + 0.22 * w1 + 0.22 * w2 + 0.45 * (n - 0.5), 0.0, 1.0);
        float filaments = smoothstep(0.5, 0.78, plasma);

        // pulses running down the beam
        float pulse = pow(0.5 + 0.5 * sin(s * 1.35 + t * 9.0), 8.0);

        // troughs: dark violet; crests: bright green filaments with hot cores
        float3 col = lerp(deep_color.rgb, plasma_color.rgb, smoothstep(0.3, 0.62, plasma));
        col = lerp(col, hot_color.rgb, smoothstep(0.7, 0.95, plasma) * 0.6 + pulse * 0.5);

        float3 N = FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0));
        float3 VIEW = normalize(GetWorldSpaceViewDir(i.positionWS));
        float facing = abs(dot(N, VIEW));
        float side_fade = pow(facing, softness);
        float ends = smoothstep(0.0, 0.05, UV.y) * smoothstep(1.0, 0.95, UV.y);
        float a = (0.5 + 0.45 * filaments + 0.3 * pulse) * side_fade * ends;

        if (core > 0.5)
        {
            // the core: a steady hot line with a flicker
            col = lerp(plasma_color.rgb, hot_color.rgb, 0.45 + 0.35 * pulse);
            a = (0.85 + 0.15 * sin(t * 40.0 + s * 3.0)) * pow(facing, 0.6) * ends;
        }
        float3 albedo = FB_ApplyDecals(col * intensity, i.positionWS, N);
        float3 c = FB_MixFog(albedo, i.positionWS);
        return float4(c, clamp(a, 0.0, 1.0));
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
            #pragma vertex PlasmaVert
            #pragma fragment PlasmaFrag
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
    FallBack Off
}
