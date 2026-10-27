// Port of res://scripts/siege/fx_shell.gdshader (spell_fx.gd's shells round a hero: a shield's bubble, a stone or bark
// skin, a fury's halo, a dome): a fresnel rim, bands of noise drifting over it, a pulse. style 0 glass, 1 crust,
// 2 energy, 3 dome.
// render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled -> transparent, Godot's
// add blend (colour SrcAlpha/One, alpha SrcAlpha/One), no depth write.
// As Godot: the fresnel is dot(NORMAL, VIEW), taken here in world space (the same angle). Nothing else differs.
Shader "Fatebound/gd/scripts/siege/fx_shell"
{
    Properties
    {
        gd_color ("color", Color) = (0.5, 0.8, 1.0, 1.0)
        style ("style", Float) = 0
        energy ("energy", Float) = 1
        fade ("fade", Float) = 1
        speed ("speed", Float) = 1
        seed ("seed", Float) = 0
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 gd_color;   // (Godot: color -- a ShaderLab keyword as a property name, so renamed: MaterialCache maps it)
        float style;
        float energy;
        float fade;
        float speed;
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
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float2 uv : TEXCOORD2;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    float shell_hash(float2 p)
    {
        return frac(sin(dot(p, float2(127.1, 311.7)) + seed) * 43758.5453);
    }

    float shell_noise(float2 p)
    {
        float2 i = floor(p);
        float2 f = frac(p);
        f = f * f * (3.0 - 2.0 * f);
        return lerp(lerp(shell_hash(i), shell_hash(i + float2(1.0, 0.0)), f.x),
                    lerp(shell_hash(i + float2(0.0, 1.0)), shell_hash(i + float2(1.0, 1.0)), f.x), f.y);
    }

    Varyings ShellVert(Attributes v)
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

    float4 ShellFrag(Varyings i) : SV_Target
    {
        UNITY_SETUP_INSTANCE_ID(i);
        float TIME = _FB_Time;
        float3 VIEW = normalize(GetWorldSpaceViewDir(i.positionWS));
        float fres = pow(1.0 - clamp(dot(normalize(i.normalWS), VIEW), 0.0, 1.0), 2.5);
        float n = shell_noise(i.uv * float2(6.0, 3.0) + float2(TIME * 0.3 * speed, -TIME * 0.7 * speed)) * 0.6
            + shell_noise(i.uv * float2(13.0, 7.0) - TIME * 0.5 * speed) * 0.4;
        float a = 0.0;
        float3 col = gd_color.rgb;
        int st = (int)style;
        if (st == 0)
        {
            a = fres * 1.1 + 0.07 + smoothstep(0.6, 0.9, n) * 0.18;
        }
        else if (st == 1)
        {
            a = 0.35 + smoothstep(0.3, 0.8, n) * 0.5 + fres * 0.5;
            col = lerp(col * 0.6, col, smoothstep(0.3, 0.8, n));
        }
        else if (st == 2)
        {
            a = fres * 0.9 + smoothstep(0.45, 0.85, n) * 0.7 + 0.1;
            col = lerp(col, 1.0, smoothstep(0.75, 1.0, n) * 0.5);
        }
        else
        {
            a = fres * 1.3 + 0.03 + smoothstep(0.7, 0.95, n) * 0.12;
        }
        a *= 0.9 + 0.1 * sin(TIME * 4.0 * speed);
        float3 albedo = FB_ApplyDecals(col * energy, i.positionWS, normalize(i.normalWS));
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
            Cull Back
            ZWrite Off
            ZTest LEqual
            Blend SrcAlpha One, SrcAlpha One

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ShellVert
            #pragma fragment ShellFrag
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
    FallBack Off
}
