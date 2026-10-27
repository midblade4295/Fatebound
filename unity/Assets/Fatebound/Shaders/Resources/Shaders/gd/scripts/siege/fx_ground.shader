// Port of res://scripts/siege/fx_ground.gdshader (spell_fx.gd's ground discs): UV 0..1 over the disc. style 0 a soft
// disc with a bright rim; 1 a sprite (tex) turning at spin; 2 fire; 3 electric arcs; 4 dappled nature light; 5 a thin
// rim. fade: the caster's hand on its brightness; grow: how much of the radius is lit.
// render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled -> transparent,
// Godot's add blend, no depth write, both faces.
// tex has no source_color: read raw (FB_Raw). exp(-pow(x, 2.0)) is written exp(-x * x): GLSL leaves pow() of a
// negative base undefined, the GPU drivers (and HLSL compilers) square it -- the rim is a gaussian either side of 0.9.
Shader "Fatebound/gd/scripts/siege/fx_ground"
{
    Properties
    {
        gd_color ("color", Color) = (1.0, 0.8, 0.4, 1.0)
        style ("style", Float) = 0
        tex ("tex", 2D) = "white" {}
        fade ("fade", Float) = 1
        grow ("grow", Float) = 1
        spin ("spin", Float) = 0
        energy ("energy", Float) = 1
        rim ("rim", Float) = 0.8
        seed ("seed", Float) = 0
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 gd_color;   // (Godot: color -- a ShaderLab keyword as a property name, so renamed: MaterialCache maps it)
        float style;
        float fade;
        float grow;
        float spin;
        float energy;
        float rim;
        float seed;
    CBUFFER_END

    TEXTURE2D(tex);

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

    float ground_hash(float2 p)
    {
        return frac(sin(dot(p, float2(127.1, 311.7)) + seed) * 43758.5453);
    }

    float ground_noise(float2 p)
    {
        float2 i = floor(p);
        float2 f = frac(p);
        f = f * f * (3.0 - 2.0 * f);
        return lerp(lerp(ground_hash(i), ground_hash(i + float2(1.0, 0.0)), f.x),
                    lerp(ground_hash(i + float2(0.0, 1.0)), ground_hash(i + float2(1.0, 1.0)), f.x), f.y);
    }

    float ground_bell(float x)
    {
        return exp(-(x * x));
    }

    Varyings GroundVert(Attributes v)
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

    float4 GroundFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
    {
        UNITY_SETUP_INSTANCE_ID(i);
        float TIME = _FB_Time;
        float2 c = i.uv - 0.5;
        float r = length(c) * 2.0;
        float ang = atan2(c.y, c.x);
        float edge = 1.0 - smoothstep(0.92, 1.0, r);
        float wave = 1.0 - smoothstep(grow - 0.08, grow + 0.02, r);
        float a = 0.0;
        float3 col = gd_color.rgb;
        int st = (int)style;
        if (st == 0)
        {
            a = 0.2 * (1.0 - r * 0.5) + rim * 0.7 * ground_bell((r - 0.9) / 0.07);
            a *= 0.85 + 0.15 * sin(TIME * 5.0 + r * 6.0);
        }
        else if (st == 1)
        {
            float s = TIME * spin;
            // mat2(vec2(cos(s), -sin(s)), vec2(sin(s), cos(s))) * c: GLSL's columns
            float2 uv = float2(cos(s) * c.x + sin(s) * c.y, -sin(s) * c.x + cos(s) * c.y) + 0.5;
            float l = FB_Raw(FB_SAMPLE(tex, sampler_TrilinearClamp, uv)).r;
            a = l * 0.8 * (0.9 + 0.1 * sin(TIME * 4.0)) + rim * 0.45 * ground_bell((r - 0.9) / 0.06);
            col = lerp(col, 1.0, smoothstep(0.75, 1.0, l) * 0.3);
        }
        else if (st == 2)
        {
            float2 p = c * 7.0;
            float n = ground_noise(p + float2(0.0, -TIME * 2.5)) * 0.6 + ground_noise(p * 2.3 + float2(TIME * 1.3, -TIME * 4.0)) * 0.4;
            float flame = smoothstep(0.4, 0.95, n + r * 0.3);
            a = flame * (0.3 + 0.35 * r) + rim * 0.5 * ground_bell((r - 0.92) / 0.08) * (0.7 + 0.3 * ground_noise(float2(ang * 3.0, TIME * 6.0)));
            col = lerp(col, float3(1.0, 0.9, 0.6), flame * flame * 0.3);
        }
        else if (st == 3)
        {
            float2 p = float2(ang * 2.5, r * 4.0 - TIME * 3.0);
            float n = ground_noise(p * 2.0 + TIME * 7.0);
            float arc = smoothstep(0.62, 0.68, n) * (1.0 - smoothstep(0.72, 0.8, n));
            float flick = step(0.35, ground_hash(float2(floor(TIME * 18.0), floor(ang * 3.0))));
            a = arc * 1.2 * flick + 0.08 + rim * 0.6 * ground_bell((r - 0.9) / 0.06) * (0.5 + 0.5 * flick);
            col = lerp(col, 1.0, arc * 0.5);
        }
        else if (st == 4)
        {
            float n = ground_noise(c * 5.0 + TIME * 0.4) * 0.6 + ground_noise(c * 11.0 - TIME * 0.6) * 0.4;
            a = smoothstep(0.35, 0.8, n) * 0.4 * (1.0 - r * 0.4) + rim * 0.7 * ground_bell((r - 0.9) / 0.07) * (0.8 + 0.2 * sin(TIME * 3.0));
        }
        else
        {
            a = rim * ground_bell((r - 0.9) / 0.05) + 0.03;
        }
        float3 albedo = FB_ApplyDecals(col * energy, i.positionWS, FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0)));
        return float4(albedo, clamp(a * edge * wave * fade * gd_color.a, 0.0, 1.0));
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
            #pragma vertex GroundVert
            #pragma fragment GroundFrag
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
    FallBack Off
}
