// Port of res://scripts/siege/fx_trail.gdshader (the ribbon a weapon leaves in a swing, weapon_fx_root.gd): UV.x its
// age, UV.y base of the blade (0) to the tip (1), the vertex alpha how fast the blade moved there.
// render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled -> transparent,
// Godot's add blend, no depth write, both faces. COLOR is the vertex colour (times a MultiMesh's instance colour, as
// Godot; 1 for a plain mesh). Nothing differs from Godot.
Shader "Fatebound/gd/scripts/siege/fx_trail"
{
    Properties
    {
        tint ("tint", Color) = (1.0, 0.8, 0.4, 1.0)
        energy ("energy", Float) = 1
        [HideInInspector] _InstColor ("Instance Color", Color) = (1, 1, 1, 1)
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 tint;
        float energy;
    CBUFFER_END

    UNITY_INSTANCING_BUFFER_START(FBPerInstance)
        UNITY_DEFINE_INSTANCED_PROP(float4, _InstColor)
    UNITY_INSTANCING_BUFFER_END(FBPerInstance)

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS : NORMAL;
        float4 color : COLOR;
        float2 uv : TEXCOORD0;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float2 uv : TEXCOORD0;
        float3 positionWS : TEXCOORD1;
        float3 normalWS : TEXCOORD2;
        float4 color : COLOR;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    Varyings TrailVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(v.normalOS);
        o.uv = v.uv;
        o.color = v.color * UNITY_ACCESS_INSTANCED_PROP(FBPerInstance, _InstColor);
        return o;
    }

    float4 TrailFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
    {
        UNITY_SETUP_INSTANCE_ID(i);
        float age = clamp(i.uv.x, 0.0, 1.0);
        float across = clamp(i.uv.y, 0.0, 1.0);
        float fade = pow(1.0 - age, 2.5);
        float edge = pow(smoothstep(0.0, 1.0, across), 1.6);       // a crescent: bright along the tip's path
        float3 c = lerp(tint.rgb, 1.0, 0.6 * (1.0 - age) * across * across * across);
        float3 albedo = FB_ApplyDecals(c, i.positionWS, FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0)));
        return float4(albedo, clamp(fade * edge * i.color.a * energy * 0.7, 0.0, 1.0));
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
            #pragma vertex TrailVert
            #pragma fragment TrailFrag
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
    FallBack Off
}
