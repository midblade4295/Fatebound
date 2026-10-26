// Port of res://scripts/siege/foliage.gdshader (the Rift's Meshy trees and bushes, drawn as MultiMeshes): the canopy
// sways above sway_from of the model's height, each plant on its own beat from where it stands; the glow mask shines
// in the texture's own colour.
// render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled -> opaque, lit.
// As Godot: the sway is computed in Godot's object space (VERTEX.x / .z, the instance's origin in Godot's world), the
// shadow and depth passes sway the same way. glow_tex has no source_color: read raw (FB_Raw).
Shader "Fatebound/gd/scripts/siege/foliage"
{
    Properties
    {
        albedo_tex ("albedo_tex", 2D) = "white" {}
        glow_tex ("glow_tex", 2D) = "black" {}
        glow_energy ("glow_energy", Float) = 0
        height ("height", Float) = 4
        sway ("sway", Float) = 0.12
        sway_from ("sway_from", Float) = 0.35
        speed ("speed", Float) = 1.2
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float glow_energy;
        float height;
        float sway;
        float sway_from;
        float speed;
    CBUFFER_END

    TEXTURE2D(albedo_tex);
    TEXTURE2D(glow_tex);

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

    // Godot's vertex(): VERTEX is the vertex in Godot's object space (Unity's mirrored)
    float3 FoliageVertex(float3 positionOS)
    {
        float3 V = FB_Mirror(positionOS);
        float k = clamp((V.y / height - sway_from) / (1.0 - sway_from), 0.0, 1.0);
        k *= k;
        float3 at = FB_GodotModelOrigin();                    // (a MultiMesh instance's own place)
        float t = _FB_Time * speed + at.x * 0.37 + at.z * 0.23;
        V.x += (sin(t) + 0.35 * sin(t * 2.3 + 1.1)) * sway * k;
        V.z += cos(t * 0.8 + 1.7) * sway * 0.6 * k;
        return FB_Mirror(V);
    }

    Varyings FoliageVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(FoliageVertex(v.positionOS.xyz));
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(v.normalOS);
        o.uv = v.uv;
        return o;
    }
    ENDHLSL

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" "Queue" = "Geometry" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Back
            ZWrite On
            ZTest LEqual
            Blend Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex FoliageVert
            #pragma fragment FoliageFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 FoliageFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 col = FB_SAMPLE(albedo_tex, sampler_TrilinearRepeat, i.uv).rgb;
                FBSurface s = FB_GodotSurface(i.positionWS, normalize(i.normalWS));
                s.albedo = FB_ApplyDecals(col, i.positionWS, s.normalWS);
                s.roughness = 0.9;
                s.emission = col * FB_Raw(FB_SAMPLE(glow_tex, sampler_TrilinearRepeat, i.uv)).r * glow_energy;
                s.specularOn = 0.0;
                float3 c = FB_Shade(s, GetNormalizedScreenSpaceUV(i.positionCS));
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
            Cull Back

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex FoliageShadowVert
            #pragma fragment FoliageShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings FoliageShadowVert(Attributes v)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                float3 positionWS = TransformObjectToWorld(FoliageVertex(v.positionOS.xyz));
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS)));
                return o;
            }

            float4 FoliageShadowFrag(Varyings i) : SV_Target
            {
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
            Cull Back

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex FoliageVert
            #pragma fragment FoliageDepthFrag
            #pragma multi_compile_instancing

            float4 FoliageDepthFrag(Varyings i) : SV_Target
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
