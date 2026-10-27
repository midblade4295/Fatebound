// Port of res://scripts/siege/fx_scorch.gdshader (the dark under a spell's ground disc, spell_fx.gd): a soft dark
// disc with a noisy edge, mixed over the ground.
// render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled -> transparent
// (ALPHA), Godot's mix blend (colour SrcAlpha/OneMinusSrcAlpha, alpha One/OneMinusSrcAlpha), no depth write, no shadow.
// Nothing differs from Godot.
Shader "Fatebound/gd/scripts/siege/fx_scorch"
{
    Properties
    {
        gd_color ("color", Color) = (0.05, 0.02, 0.0, 1.0)
        fade ("fade", Float) = 1
        grow ("grow", Float) = 1
        strength ("strength", Float) = 0.5
        seed ("seed", Float) = 0
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 gd_color;   // (Godot: color -- a ShaderLab keyword as a property name, so renamed: MaterialCache maps it)
        float fade;
        float grow;
        float strength;
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

    float scorch_hash(float2 p)
    {
        return frac(sin(dot(p, float2(127.1, 311.7)) + seed) * 43758.5453);
    }

    float scorch_noise(float2 p)
    {
        float2 i = floor(p);
        float2 f = frac(p);
        f = f * f * (3.0 - 2.0 * f);
        return lerp(lerp(scorch_hash(i), scorch_hash(i + float2(1.0, 0.0)), f.x),
                    lerp(scorch_hash(i + float2(0.0, 1.0)), scorch_hash(i + float2(1.0, 1.0)), f.x), f.y);
    }

    Varyings ScorchVert(Attributes v)
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

    float4 ScorchFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
    {
        UNITY_SETUP_INSTANCE_ID(i);
        float2 c = i.uv - 0.5;
        float r = length(c) * 2.0;
        float n = scorch_noise(c * 6.0) * 0.5 + scorch_noise(c * 13.0) * 0.5;
        float a = (1.0 - smoothstep(0.45, 1.0, r + (n - 0.5) * 0.3)) * strength;
        a *= 1.0 - smoothstep(grow - 0.08, grow + 0.02, r);
        float3 albedo = FB_ApplyDecals(gd_color.rgb, i.positionWS, FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0)));
        return float4(albedo, clamp(a * fade * gd_color.a, 0.0, 1.0));
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
            #pragma vertex ScorchVert
            #pragma fragment ScorchFrag
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
    FallBack Off
}
