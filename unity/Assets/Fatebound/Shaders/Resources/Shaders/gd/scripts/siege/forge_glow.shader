// Port of res://scripts/siege/forge_glow.gdshader (a weapon's glow, weapon_fx.gd: an additive next_pass over the
// weapon's own material): a fresnel rim, a glint running up the piece, glowing veins (a 3D cell pattern in the piece's
// own space) with a pulse flowing up them, and a legendary's keyed texels (gems, lava, eyes) breathing in their colour.
// render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled -> transparent, Godot's
// add blend, no depth write.
// As Godot: lp is VERTEX in Godot's object space (the veins' cells are hashed on Godot's coordinates, so they fall
// where Godot puts them); the fresnel is dot(NORMAL, VIEW) in world space. albedo_tex has no source_color (the key reads
// the painted, sRGB values): read raw (FB_Raw).
Shader "Fatebound/gd/scripts/siege/forge_glow"
{
    Properties
    {
        tint ("tint", Color) = (1.0, 0.75, 0.3, 1.0)
        rim ("rim", Float) = 0.3
        sweep ("sweep", Float) = 0.6
        veins ("veins", Float) = 0
        boost ("boost", Float) = 1
        span ("span", Float) = 2
        albedo_tex ("albedo_tex", 2D) = "white" {}
        key ("key", Vector) = (0.0, 0.05, 0.5, 0.5)
        key_amt ("key_amt", Float) = 0
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 tint;
        float rim;
        float sweep;
        float veins;
        float boost;
        float span;
        float4 key;
        float key_amt;
    CBUFFER_END

    TEXTURE2D(albedo_tex);

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
        float3 lp : TEXCOORD3;          // Godot's VERTEX (object space)
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    float3 glow_hash3(float3 p)
    {
        p = float3(dot(p, float3(127.1, 311.7, 74.7)), dot(p, float3(269.5, 183.3, 246.1)), dot(p, float3(113.5, 271.9, 124.6)));
        return frac(sin(p) * 43758.5453);
    }

    float glow_cracks(float3 p)
    {
        // distance to the nearest edge between cells (F2 - F1): small on the cracks
        float3 i = floor(p);
        float3 f = frac(p);
        float d1 = 8.0;
        float d2 = 8.0;
        for (int z = -1; z <= 1; z++)
        {
            for (int y = -1; y <= 1; y++)
            {
                for (int x = -1; x <= 1; x++)
                {
                    float3 g = float3(float(x), float(y), float(z));
                    float d = length(g + glow_hash3(i + g) - f);
                    if (d < d1)
                    {
                        d2 = d1;
                        d1 = d;
                    }
                    else if (d < d2)
                    {
                        d2 = d;
                    }
                }
            }
        }
        return d2 - d1;
    }

    float3 glow_hsv(float3 c)
    {
        float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
        float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
        float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
        float d = q.x - min(q.w, q.y);
        return float3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
    }

    Varyings GlowVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(v.normalOS);
        o.uv = v.uv;
        o.lp = FB_Mirror(v.positionOS.xyz);
        return o;
    }

    float4 GlowFrag(Varyings i) : SV_Target
    {
        UNITY_SETUP_INSTANCE_ID(i);
        float TIME = _FB_Time;
        float3 VIEW = normalize(GetWorldSpaceViewDir(i.positionWS));
        float facing = clamp(dot(normalize(i.normalWS), VIEW), 0.0, 1.0);
        float fres = pow(1.0 - facing, 3.0);
        float y = i.lp.y / max(span, 0.01);
        float3 hot = lerp(tint.rgb, 1.0, 0.65);
        float3 c = tint.rgb * fres * rim;
        // the glint: a narrow band, its core white
        float band = abs(frac(y * 0.75 - TIME * 0.42) - 0.5);
        c += hot * smoothstep(0.045, 0.0, band) * sweep * (0.4 + 0.6 * facing);
        c += tint.rgb * smoothstep(0.12, 0.0, band) * sweep * 0.25;
        if (veins > 0.0)
        {
            float vn = smoothstep(0.06, 0.0, glow_cracks(i.lp / max(span, 0.01) * 12.0));
            float flow = 0.25 + 0.75 * pow(0.5 + 0.5 * sin(y * 11.0 - TIME * 3.2), 3.0);
            c += lerp(tint.rgb, 1.0, 0.35 * flow) * vn * flow * veins;
        }
        if (key_amt > 0.0)
        {
            float3 a = FB_Raw(FB_SAMPLE(albedo_tex, sampler_TrilinearRepeat, i.uv)).rgb;
            float3 h = glow_hsv(a);
            float dh = abs(frac(h.x - key.x + 0.5) - 0.5);
            float m = smoothstep(key.y, key.y * 0.4, dh) * smoothstep(key.z, key.z + 0.15, h.y) * smoothstep(key.w, key.w + 0.15, h.z);
            float breathe = 0.7 + 0.3 * sin(TIME * 2.2);
            c += pow(a, 2.2) * m * key_amt * breathe;
        }
        float3 albedo = FB_ApplyDecals(c * boost * 0.5, i.positionWS, normalize(i.normalWS));   // (the scene's exposure lifts an unshaded add a lot)
        return float4(albedo, 1.0);
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
            #pragma vertex GlowVert
            #pragma fragment GlowFrag
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
    FallBack Off
}
