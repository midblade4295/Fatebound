// Port of res://scripts/siege/fx_beam.gdshader (spell_fx.gd's pillars, beams, cones and sheets): UV.y along the
// effect, UV.x across it; noise scrolling along it, faded at its ends (and sides, side_fade), lit up from the root by
// grow, in the spell's colour, added.
// render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled -> transparent,
// Godot's add blend, no depth write, both faces. Nothing differs from Godot.
Shader "Fatebound/gd/scripts/siege/fx_beam"
{
    Properties
    {
        color ("color", Color) = (1.0, 0.8, 0.4, 1.0)
        energy ("energy", Float) = 1
        fade ("fade", Float) = 1
        grow ("grow", Float) = 1
        speed ("speed", Float) = 2
        scale ("scale", Float) = 3
        fade_root ("fade_root", Float) = 0.15
        fade_end ("fade_end", Float) = 0.4
        side_fade ("side_fade", Float) = 1
        core ("core", Float) = 0.4
        seed ("seed", Float) = 0
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 color;
        float energy;
        float fade;
        float grow;
        float speed;
        float scale;
        float fade_root;
        float fade_end;
        float side_fade;
        float core;
        float seed;
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
        float2 uv : TEXCOORD0;
        float3 positionWS : TEXCOORD1;
        float3 normalWS : TEXCOORD2;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    float beam_hash(float2 p)
    {
        return frac(sin(dot(p, float2(127.1, 311.7)) + seed) * 43758.5453);
    }

    float beam_noise(float2 p)
    {
        float2 i = floor(p);
        float2 f = frac(p);
        f = f * f * (3.0 - 2.0 * f);
        return lerp(lerp(beam_hash(i), beam_hash(i + float2(1.0, 0.0)), f.x),
                    lerp(beam_hash(i + float2(0.0, 1.0)), beam_hash(i + float2(1.0, 1.0)), f.x), f.y);
    }

    Varyings BeamVert(Attributes v)
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

    float4 BeamFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
    {
        UNITY_SETUP_INSTANCE_ID(i);
        float TIME = _FB_Time;
        float y = i.uv.y;
        float x = i.uv.x;
        float n = beam_noise(float2(x * scale * 2.0, y * scale - TIME * speed)) * 0.6
            + beam_noise(float2(x * scale * 4.0 + 3.0, y * scale * 2.0 - TIME * speed * 1.7)) * 0.4;
        float a = smoothstep(0.3, 0.9, n) * 0.7 + 0.05;
        a *= smoothstep(0.0, fade_root, y) * (1.0 - smoothstep(1.0 - fade_end, 1.0, y));
        if (side_fade > 0.5)
        {
            float s = abs(x - 0.5) * 2.0;
            a *= 1.0 - smoothstep(0.55, 1.0, s);
            a += core * (1.0 - smoothstep(0.0, 0.35, s)) * smoothstep(0.0, fade_root, y) * (1.0 - smoothstep(1.0 - fade_end, 1.0, y));
        }
        else
        {
            a += core * 0.3 * smoothstep(0.0, fade_root, y) * (1.0 - smoothstep(1.0 - fade_end, 1.0, y));
        }
        a *= 1.0 - smoothstep(grow - 0.05, grow + 0.02, y);
        float3 col = lerp(color.rgb, 1.0, smoothstep(0.8, 1.0, n) * 0.3);
        float3 albedo = FB_ApplyDecals(col * energy, i.positionWS, FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0)));
        return float4(albedo, clamp(a * fade * color.a, 0.0, 1.0));
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
            Blend SrcAlpha One, SrcAlpha One

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex BeamVert
            #pragma fragment BeamFrag
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
    FallBack Off
}
