// Port of res://scripts/siege/ground_cards.gdshader (the Rift's painted grass clumps, brush and flower patches): a
// MultiMesh whose instances pick their cell of the sheet (INSTANCE_CUSTOM.x), shade (.y) and beat in the breeze (.z);
// cut out at the picture's edge (discard -- opaque, no sorting); NORMAL straight up.
// render_mode cull_disabled, diffuse_burley, specular_disabled -> opaque with discard (AlphaTest queue), lit.
// As Godot: the sway is computed in Godot's object space (VERTEX.x / .z) with the instance's origin in Godot's world;
// INSTANCE_CUSTOM is the MultiMesh's custom data (_InstCustom). Godot's DO_SIDE_CHECK (cull_disabled) turns NORMAL round
// on a card's back face, so the back is lit as a surface facing down -- kept. Shadow and depth passes sway and cut the
// same way.
Shader "Fatebound/gd/scripts/siege/ground_cards"
{
    Properties
    {
        sheet ("sheet", 2D) = "white" {}
        cells ("cells", Vector) = (4, 2, 0, 0)
        sway ("sway", Float) = 0.12
        speed ("speed", Float) = 1.4
        tint ("tint", Vector) = (1, 1, 1, 0)
        cut ("cut", Float) = 0.45
        [HideInInspector] _InstCustom ("Instance Custom", Vector) = (0, 0, 0, 0)
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 cells;
        float sway;
        float speed;
        float4 tint;
        float cut;
    CBUFFER_END

    UNITY_INSTANCING_BUFFER_START(FBPerInstance)
        UNITY_DEFINE_INSTANCED_PROP(float4, _InstCustom)
    UNITY_INSTANCING_BUFFER_END(FBPerInstance)

    TEXTURE2D(sheet);

    struct Attributes
    {
        float4 positionOS : POSITION;
        float2 uv : TEXCOORD0;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float2 uv : TEXCOORD2;
        float shade : TEXCOORD3;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    Varyings CardsVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        float4 custom = UNITY_ACCESS_INSTANCED_PROP(FBPerInstance, _InstCustom);   // Godot's INSTANCE_CUSTOM
        float3 V = FB_Mirror(v.positionOS.xyz);                                    // Godot's VERTEX
        float cell = custom.x;
        float2 c = float2(FB_Mod(cell, cells.x), floor(cell / cells.x));
        float2 uv = (c + v.uv) / cells.xy;
        o.shade = 0.86 + 0.28 * custom.y;
        float k = (1.0 - (uv.y * cells.y - c.y));            // 0 at the card's foot .. 1 at its top
        k = k * k;
        float3 at = FB_GodotModelOrigin();
        float t = _FB_Time * speed + custom.z * 6.283 + at.x * 0.21 + at.z * 0.17;
        float gust = 0.6 + 0.4 * sin(_FB_Time * 0.7 + at.x * 0.05 + at.z * 0.04);
        V.x += (sin(t) + 0.3 * sin(t * 2.7 + 1.3)) * sway * k * gust;
        V.z += cos(t * 0.9 + 0.7) * sway * 0.5 * k * gust;
        o.positionWS = TransformObjectToWorld(FB_Mirror(V));
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(float3(0.0, 1.0, 0.0));        // NORMAL = vec3(0.0, 1.0, 0.0)
        o.uv = uv;
        return o;
    }

    float4 CardsSheet(float2 uv)
    {
        return FB_SAMPLE(sheet, sampler_TrilinearClamp, uv);
    }
    ENDHLSL

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "TransparentCutout" "Queue" = "AlphaTest" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Off
            ZWrite On
            ZTest LEqual
            Blend Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex CardsVert
            #pragma fragment CardsFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 CardsFrag(Varyings i, FRONT_FACE_TYPE facing : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float4 s = CardsSheet(i.uv);
                if (s.a < cut)
                {
                    discard;
                }
                FBSurface surf = FB_GodotSurface(i.positionWS, FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(facing, 1.0, -1.0)));
                surf.albedo = FB_ApplyDecals(s.rgb * i.shade * tint.rgb, i.positionWS, surf.normalWS);
                surf.roughness = 0.95;
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
            Cull Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex CardsShadowVert
            #pragma fragment CardsShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings CardsShadowVert(Attributes v)
            {
                Varyings o = CardsVert(v);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - o.positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(o.positionWS, o.normalWS, lightDirectionWS)));
                return o;
            }

            float4 CardsShadowFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                if (CardsSheet(i.uv).a < cut)
                {
                    discard;
                }
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
            Cull Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex CardsVert
            #pragma fragment CardsDepthFrag
            #pragma multi_compile_instancing

            float4 CardsDepthFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                if (CardsSheet(i.uv).a < cut)
                {
                    discard;
                }
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
