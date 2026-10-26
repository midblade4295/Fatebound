// Port of res://assets/vfx/effectblocks/shockwave.gdshader (the EffectBlocks shockwave adapted for Fatebound; siege_view.gd's
// shockwave(): a torus growing over the blast, bending the screen outward from the ring's own centre on screen).
// render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled -> transparent (ALPHA, screen
// texture), Godot's mix blend, no depth write, both faces. Fog is NOT disabled: Godot's fog is mixed over it, as here.
// Differences from Godot:
//  * hint_screen_texture is URP's opaque texture (_CameraOpaqueTexture, the scene copied after the opaques and the sky,
//    as Godot copies it before the transparent pass): the camera must have the opaque texture on (URP asset "Opaque
//    Texture" / UniversalAdditionalCameraData.requiresColorTexture), else this samples a grey/black default.
//    Sampled at LOD 0, bilinear, as textureLod(..., 0.0) does.
//  * "outward" is taken between the ring's centre and the fragment in Unity's screen-UV space (both through the same
//    projection, ComputeScreenPos-style), so no y flip is needed (Godot flips clip-space y to its y-down SCREEN_UV).
//    The noise hashes Unity's SCREEN_UV (y up): the same noise, mirrored.
//  * fade is an instance uniform (per renderer, MaterialPropertyBlock).
Shader "Fatebound/gd/assets/vfx/effectblocks/shockwave"
{
    Properties
    {
        distortion_intensity ("distortion_intensity", Range(0, 1)) = 0.1
        noise_influence ("noise_influence", Range(0, 1)) = 0.273
        fade ("fade (instance)", Float) = 1
    }

    HLSLINCLUDE
    #include "../../../../FateboundCommon3D.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float distortion_intensity;
        float noise_influence;
        float fade;
    CBUFFER_END

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS : NORMAL;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float4 center_scr : TEXCOORD2;     // the ring's centre, Godot's center_clip -- as a screen position
        float4 frag_scr : TEXCOORD3;       // this vertex, Godot's frag_clip -- as a screen position
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    // ComputeScreenPos: clip position -> homogeneous screen-UV position (xy / w = the UV the screen textures are read at)
    float4 ShockScreenPos(float4 positionCS)
    {
        float4 o = positionCS * 0.5;
        o.xy = float2(o.x, o.y * _ProjectionParams.x) + o.w;
        o.zw = positionCS.zw;
        return o;
    }

    float shock_random(float2 uv)
    {
        return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453123);
    }

    Varyings ShockVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(v.normalOS);
        o.center_scr = ShockScreenPos(TransformWorldToHClip(TransformObjectToWorld(float3(0.0, 0.0, 0.0))));
        o.frag_scr = ShockScreenPos(o.positionCS);
        return o;
    }

    float4 ShockFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
    {
        UNITY_SETUP_INSTANCE_ID(i);
        float2 SCREEN_UV = GetNormalizedScreenSpaceUV(i.positionCS);
        // the ring's centre and this fragment, both in the same screen space; their difference is "outward"
        float2 c = i.center_scr.xy / i.center_scr.w;
        float2 f = i.frag_scr.xy / i.frag_scr.w;
        float2 out_dir = f - c;
        float len_d = length(out_dir);
        out_dir = len_d > 0.0001 ? out_dir / len_d : float2(0.0, 0.0);
        float noise = 1.0 + (shock_random(SCREEN_UV) * 2.0 - 1.0) * noise_influence;
        float3 N = FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0));
        float3 VIEW = normalize(GetWorldSpaceViewDir(i.positionWS));
        float band = pow(clamp(abs(dot(N, VIEW)), 0.0, 1.0), 0.6);   // strongest mid-band
        float2 offset = out_dir * distortion_intensity * 0.55 * noise * band * fade;
        float3 col = SampleSceneColor(SCREEN_UV + offset);
        float3 albedo = FB_ApplyDecals(col, i.positionWS, N);
        return float4(FB_MixFog(albedo, i.positionWS), clamp(band * fade * 1.4, 0.0, 1.0));
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
            #pragma vertex ShockVert
            #pragma fragment ShockFrag
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
    FallBack Off
}
