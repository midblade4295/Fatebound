// Port of the inline shader ground_cards.gd builds from DECAL_SHADER (a painted mark laid over the ground -- carved
// stone circles on the lanes and pits, the stone ring round a tower's foot: the picture's own alpha, turned by spin, lit
// as the ground is). The material's render_priority 1 is added to the queue by the renderer.
// render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_disabled -> transparent (ALPHA), Godot's
// mix blend, no depth write, lit. Nothing differs from Godot.
Shader "Fatebound/gd/inline/ground_cards_decal"
{
    Properties
    {
        tex ("tex", 2D) = "white" {}
        tint ("tint", Vector) = (1, 1, 1, 0)
        spin ("spin", Float) = 0
    }

    HLSLINCLUDE
    #include "../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 tint;
        float spin;
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
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float2 uv : TEXCOORD2;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    Varyings DecalVert(Attributes v)
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
            Blend SrcAlpha OneMinusSrcAlpha, One OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex DecalVert
            #pragma fragment DecalFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 DecalFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float2 q = i.uv - 0.5;
                // mat2(vec2(cos(spin), sin(spin)), vec2(-sin(spin), cos(spin))) * q + 0.5 (GLSL's columns)
                q = float2(cos(spin) * q.x - sin(spin) * q.y, sin(spin) * q.x + cos(spin) * q.y) + 0.5;
                float4 c = FB_SAMPLE(tex, sampler_TrilinearClamp, q);
                float alpha = c.a * step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
                FBSurface s = FB_GodotSurface(i.positionWS, normalize(i.normalWS));
                s.albedo = FB_ApplyDecals(c.rgb * tint.rgb, i.positionWS, s.normalWS);
                s.alpha = alpha;
                s.roughness = 0.95;
                s.specularOn = 0.0;
                float3 col = FB_Shade(s, GetNormalizedScreenSpaceUV(i.positionCS));
                col = FB_MixFog(col, i.positionWS);
                return float4(col, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
