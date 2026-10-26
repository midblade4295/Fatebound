// Port of the inline shader siege_view.gd builds from CAPE_SHADER (cloth capes: the skinned cape mesh bent by a 3 x 4
// spring grid -- offs[12], model-space offsets the view steps at 30 Hz -- interpolated over the cape).
// render_mode cull_disabled (diffuse_burley, specular_schlick_ggx by default) -> opaque, lit, both faces.
// As Godot: VERTEX is the skinned vertex in Godot's model space (the renderer's skinning gives the skinned mesh, as
// Godot's does before vertex()); the grid cell is found from Godot's x and the offsets (Godot model-space vectors) are
// added in Godot's space. The shadow and depth passes bend the same way; Godot's DO_SIDE_CHECK turns NORMAL round on
// back faces. offs is a uniform array outside UnityPerMaterial (SetVectorArray, the Vector3s in .xyz).
Shader "Fatebound/gd/inline/siege_view_cape"
{
    Properties
    {
        albedo_tex ("albedo_tex", 2D) = "white" {}
        albedo ("albedo", Color) = (1, 1, 1, 1)
        roughness ("roughness", Float) = 0.5
    }

    HLSLINCLUDE
    #include "../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 albedo;
        float roughness;
    CBUFFER_END

    float4 offs[12];            // Godot's vec3 offs[12]

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
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    // Godot's vertex(): model-space position -> place on the 3 x 4 grid (shoulders at y 1.2, hem at 0.12, 0.94 m across)
    float3 CapeVertex(float3 positionOS)
    {
        float3 V = FB_Mirror(positionOS);
        float u = clamp((V.x + 0.47) / 0.94, 0.0, 1.0) * 2.0;
        float v = clamp((1.2 - V.y) / 1.08, 0.0, 1.0) * 3.0;
        int c0 = (int)min(floor(u), 1.0);
        int r0 = (int)min(floor(v), 2.0);
        float fu = u - float(c0);
        float fv = v - float(r0);
        float3 a = lerp(offs[r0 * 3 + c0].xyz, offs[r0 * 3 + c0 + 1].xyz, fu);
        float3 b = lerp(offs[(r0 + 1) * 3 + c0].xyz, offs[(r0 + 1) * 3 + c0 + 1].xyz, fu);
        V += lerp(a, b, fv);
        return FB_Mirror(V);
    }

    Varyings CapeVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(CapeVertex(v.positionOS.xyz));
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
            Cull Off
            ZWrite On
            ZTest LEqual
            Blend Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex CapeVert
            #pragma fragment CapeFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 CapeFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float4 t = FB_SAMPLE(albedo_tex, sampler_TrilinearRepeat, i.uv) * albedo;
                FBSurface s = FB_GodotSurface(i.positionWS, FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0)));
                s.albedo = FB_ApplyDecals(t.rgb, i.positionWS, s.normalWS);
                s.roughness = roughness;
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
            Cull Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex CapeShadowVert
            #pragma fragment CapeShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings CapeShadowVert(Attributes v)
            {
                Varyings o = CapeVert(v);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - o.positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(o.positionWS, o.normalWS, lightDirectionWS)));
                return o;
            }

            float4 CapeShadowFrag(Varyings i) : SV_Target
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
            Cull Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex CapeVert
            #pragma fragment CapeDepthFrag
            #pragma multi_compile_instancing

            float4 CapeDepthFrag(Varyings i) : SV_Target
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
