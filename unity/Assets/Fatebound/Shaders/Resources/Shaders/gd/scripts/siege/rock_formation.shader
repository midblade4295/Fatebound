// Port of res://scripts/siege/rock_formation.gdshader (the jungle's rock formations, rock_sculpt.gd): the painted cliff
// rock triplanar in world space, each boulder's shade from COLOR.r, darker at its foot (COLOR.g), moss over faces that
// turn up.
// render_mode cull_back, diffuse_burley, specular_disabled -> opaque, lit.
// As Godot: wpos / wnorm are Godot's world-space position and (model-matrix) normal, so the triplanar planes and the
// macro noise land where they do in Godot; wnorm is interpolated and not renormalised, as in Godot. macro_tex has no
// source_color: read raw (FB_Raw).
Shader "Fatebound/gd/scripts/siege/rock_formation"
{
    Properties
    {
        rock_tex ("rock_tex", 2D) = "white" {}
        moss_tex ("moss_tex", 2D) = "white" {}
        macro_tex ("macro_tex", 2D) = "white" {}
        rock_scale ("rock_scale", Float) = 3.2
        moss_scale ("moss_scale", Float) = 6.0
        tint ("tint", Vector) = (1, 1, 1, 0)
        cool ("cool", Vector) = (0.86, 0.93, 1.08, 0)
        warm ("warm", Vector) = (1.06, 1.0, 0.92, 0)
        [HideInInspector] _InstColor ("Instance Color", Color) = (1, 1, 1, 1)
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float rock_scale;
        float moss_scale;
        float4 tint;
        float4 cool;
        float4 warm;
    CBUFFER_END

    UNITY_INSTANCING_BUFFER_START(FBPerInstance)
        UNITY_DEFINE_INSTANCED_PROP(float4, _InstColor)
    UNITY_INSTANCING_BUFFER_END(FBPerInstance)

    TEXTURE2D(rock_tex);
    TEXTURE2D(moss_tex);
    TEXTURE2D(macro_tex);

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS : NORMAL;
        float4 color : COLOR;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float3 wpos : TEXCOORD2;       // Godot's world position
        float3 wnorm : TEXCOORD3;      // Godot's world normal (MODEL_MATRIX * NORMAL, normalised per vertex)
        float4 color : COLOR;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    Varyings RockVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(v.normalOS);
        o.wpos = FB_Mirror(o.positionWS);
        o.wnorm = normalize(FB_Mirror(TransformObjectToWorldDir(v.normalOS, false)));
        o.color = v.color * UNITY_ACCESS_INSTANCED_PROP(FBPerInstance, _InstColor);
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
            #pragma vertex RockVert
            #pragma fragment RockFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 RockFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 wpos = i.wpos;
                float3 wnorm = i.wnorm;
                float4 vcol = i.color;                 // Godot's COLOR
                float3 an = pow(abs(wnorm), 3.0);
                an /= (an.x + an.y + an.z);
                float3 r = FB_SAMPLE(rock_tex, sampler_TrilinearRepeat, float2(wpos.z, -wpos.y) / rock_scale).rgb * an.x
                    + FB_SAMPLE(rock_tex, sampler_TrilinearRepeat, wpos.xz / rock_scale).rgb * an.y
                    + FB_SAMPLE(rock_tex, sampler_TrilinearRepeat, float2(wpos.x, -wpos.y) / rock_scale).rgb * an.z;
                r *= lerp(cool.rgb, warm.rgb, vcol.r);
                r *= lerp(0.62, 1.04, smoothstep(0.0, 0.55, vcol.g));          // darker at the foot
                float mn = FB_Raw(FB_SAMPLE(macro_tex, sampler_TrilinearRepeat, wpos.xz / 7.0)).r;
                float up = smoothstep(0.78, 0.92, wnorm.y + (mn - 0.5) * 0.35 + vcol.b * 0.05);
                float3 moss = FB_SAMPLE(moss_tex, sampler_TrilinearRepeat, wpos.xz / moss_scale).rgb * float3(0.92, 1.0, 0.86);
                float3 col = lerp(r, moss, up * smoothstep(0.55, 0.85, vcol.g + vcol.b * 0.2) * smoothstep(0.3, 0.55, mn + 0.15));

                FBSurface s = FB_GodotSurface(i.positionWS, normalize(i.normalWS));
                s.albedo = FB_ApplyDecals(col * tint.rgb, i.positionWS, s.normalWS);
                s.roughness = 0.92;
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
            #pragma vertex RockShadowVert
            #pragma fragment RockShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings RockShadowVert(Attributes v)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS)));
                return o;
            }

            float4 RockShadowFrag(Varyings i) : SV_Target
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
            #pragma vertex RockVert
            #pragma fragment RockDepthFrag
            #pragma multi_compile_instancing

            float4 RockDepthFrag(Varyings i) : SV_Target
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
