// Port of the inline shader siege_view.gd's _build_water builds when High-quality graphics are off (the plain river):
// two scrolling noise layers in UV space, teal over the painted bed, the banks shaded (UV2.y), sun glints (glint).
// render_mode cull_disabled, blend_mix, depth_draw_opaque (diffuse_burley, specular_schlick_ggx by default) ->
// transparent (ALPHA), Godot's mix blend, no depth write, both faces, lit.
// As Godot (all in UV space); Godot's DO_SIDE_CHECK turns NORMAL round on back faces. ripples has no source_color:
// read raw (FB_Raw).
Shader "Fatebound/gd/inline/siege_view_water"
{
    Properties
    {
        ripples ("ripples", 2D) = "white" {}
        glint ("glint", Float) = 0
    }

    HLSLINCLUDE
    #include "../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float glint;
    CBUFFER_END

    TEXTURE2D(ripples);

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS : NORMAL;
        float2 uv : TEXCOORD0;
        float2 uv2 : TEXCOORD1;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float2 uv : TEXCOORD2;
        float2 uv2 : TEXCOORD3;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    Varyings WaterVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(v.normalOS);
        o.uv = v.uv;
        o.uv2 = v.uv2;
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
            Cull Off
            ZWrite Off
            ZTest LEqual
            Blend SrcAlpha OneMinusSrcAlpha, One OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex WaterVert
            #pragma fragment WaterFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 WaterFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float TIME = _FB_Time;
                float2 UV2 = i.uv2;
                float2 w = i.uv * float2(18.0, 1.0);
                float a = FB_Raw(FB_SAMPLE(ripples, sampler_TrilinearRepeat, w * 0.35 + float2(TIME * 0.05, TIME * 0.02))).r;
                float b = FB_Raw(FB_SAMPLE(ripples, sampler_TrilinearRepeat, w * 0.21 - float2(TIME * 0.03, 0.0))).r;
                float n = a * 0.6 + b * 0.4;
                float shore = 1.0 - smoothstep(0.0, 0.16, min(UV2.y, 1.0 - UV2.y));
                float3 deep = float3(0.06, 0.36, 0.44);
                float3 shallow = float3(0.24, 0.64, 0.62);
                float3 col = lerp(deep, shallow, smoothstep(0.35, 0.75, n));
                col *= 1.0 - shore * 0.18;                     // no foam: the banks just shade a little
                float alpha = lerp(0.5, 0.72, smoothstep(0.0, 0.4, min(UV2.y, 1.0 - UV2.y)));
                // Sun glints: sparse sparkles where two scrolling layers line up
                float sg = FB_Raw(FB_SAMPLE(ripples, sampler_TrilinearRepeat, w * 1.3 + float2(-TIME * 0.09, TIME * 0.05))).r
                    * FB_Raw(FB_SAMPLE(ripples, sampler_TrilinearRepeat, w * 0.9 + float2(TIME * 0.07, -TIME * 0.04))).r;

                FBSurface s = FB_GodotSurface(i.positionWS, FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0)));
                s.albedo = FB_ApplyDecals(col, i.positionWS, s.normalWS);
                s.alpha = alpha;
                s.roughness = 0.18;
                s.specular = 0.35;
                s.emission = float3(1.0, 0.97, 0.88) * smoothstep(0.58, 0.64, sg) * glint;
                float3 c = FB_Shade(s, GetNormalizedScreenSpaceUV(i.positionCS));
                c = FB_MixFog(c, i.positionWS);
                return float4(c, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
