// Port of res://scripts/app/war_land.gdshader (the war map's land, war_land_view.gd): its painted colours, each place
// tinted with the house holding it, white borders between places (none along a ridge), the picked place lit and
// outlined, a battle's land pulsing orange, cloud shadows; cut to an oval (disc) on Home's table.
// render_mode specular_disabled (diffuse_burley, cull_back by default) -> opaque with discard (the disc), lit.
// As Godot: `world` is to_map * MODEL_MATRIX * VERTEX in Godot's space (to_map in Godot's column layout; unset -- Unity's
// zero matrix -- is taken as Godot's default mat4(1.0)). region_id (filter_nearest) and region_lin (filter_linear) have
// no mipmaps (LOD 0) and no source_color: read raw (FB_Raw), so R * 255 is the place's index again. cloud_tex raw too.
// holder[18] / battle[18] are uniform arrays outside UnityPerMaterial (SetVectorArray / SetFloatArray); unset = zeros,
// as Godot's.
Shader "Fatebound/gd/scripts/app/war_land"
{
    Properties
    {
        color_tex ("color_tex", 2D) = "white" {}
        region_id ("region_id", 2D) = "white" {}
        region_lin ("region_lin", 2D) = "white" {}
        cloud_tex ("cloud_tex", 2D) = "white" {}
        picked ("picked", Float) = -1
        wind ("wind", Vector) = (0.012, 0.006, 0, 0)
        cloud_strength ("cloud_strength", Float) = 0.28
        disc ("disc", Vector) = (0, 0, 0, 0)
        glow ("glow", Float) = 0
        tint ("tint", Float) = 0.16
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float picked;
        float4 wind;
        float cloud_strength;
        float4 disc;
        float glow;
        float tint;
    CBUFFER_END

    float4x4 to_map;        // Godot's mat4 (SetMatrix, Godot's column layout); unset (all zero) = identity
    float4 holder[18];      // the colour of the house holding each place (a = 0: nobody)
    float battle[18];       // 1: a battle is on there

    TEXTURE2D(color_tex);
    TEXTURE2D(region_id);
    TEXTURE2D(region_lin);
    TEXTURE2D(cloud_tex);

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
        float3 world : TEXCOORD3;      // Godot's to_map * MODEL_MATRIX * VERTEX
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    float3 LandToMap(float3 positionWS)
    {
        float4x4 m = to_map;
        if (m._m33 == 0.0 && m._m00 == 0.0)
        {
            m = float4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        }
        return mul(m, float4(FB_Mirror(positionWS), 1.0)).xyz;
    }

    Varyings LandVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(v.normalOS);
        o.uv = v.uv;
        o.world = LandToMap(o.positionWS);
        return o;
    }

    void LandClip(Varyings i)
    {
        if (disc.x > 0.0 && length(i.world.xz / disc.xy) > 1.0)
        {
            discard;
        }
    }
    ENDHLSL

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "TransparentCutout" "Queue" = "AlphaTest" }

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
            #pragma vertex LandVert
            #pragma fragment LandFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 LandFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                LandClip(i);
                float TIME = _FB_Time;
                float2 UV = i.uv;
                float3 col = FB_SAMPLE(color_tex, sampler_TrilinearRepeat, UV).rgb;
                int id = (int)(FB_Raw(FB_SAMPLE_LOD(region_id, sampler_PointRepeat, UV, 0.0)).r * 255.0 + 0.5);
                float4 lin = FB_Raw(FB_SAMPLE_LOD(region_lin, sampler_LinearRepeat, UV, 0.0));
                float edge = lin.g * 0.4;                         // table units to the nearest border
                float ridge = lin.b;
                if (id < 18)
                {
                    float4 hc = holder[id];
                    col = lerp(col, hc.rgb * 0.9 + col * 0.25, hc.a * tint);
                    // the border: a soft white line with the holder's colour along its inside
                    float border = (1.0 - smoothstep(0.008, 0.022, edge)) * (1.0 - ridge);
                    float inner = (1.0 - smoothstep(0.03, 0.14, edge)) * hc.a;
                    col = lerp(col, hc.rgb * 1.15, inner * 0.7);
                    col = lerp(col, float3(0.97, 0.95, 0.88), border * 0.7);
                    float pulse = 0.5 + 0.5 * sin(TIME * 4.0);
                    if (battle[id] > 0.5)
                    {
                        col = lerp(col, float3(1.0, 0.45, 0.12), 0.16 + 0.14 * pulse);
                        col = lerp(col, float3(1.0, 0.62, 0.2), (1.0 - smoothstep(0.03, 0.12, edge)) * (0.5 + 0.4 * pulse));
                    }
                    if (id == (int)picked)
                    {
                        col *= 1.16;
                        col = lerp(col, float3(1.0, 1.0, 0.92), (1.0 - smoothstep(0.02, 0.09, edge)) * (0.65 + 0.3 * pulse));
                    }
                }
                // clouds passing over
                float c = FB_Raw(FB_SAMPLE(cloud_tex, sampler_TrilinearRepeat, i.world.xz * 0.045 + TIME * wind.xy)).r;
                col *= 1.0 - cloud_strength * smoothstep(0.52, 0.78, c);

                FBSurface s = FB_GodotSurface(i.positionWS, normalize(i.normalWS));
                s.albedo = FB_ApplyDecals(col, i.positionWS, s.normalWS);
                s.emission = col * glow;
                s.roughness = 0.95;
                s.specularOn = 0.0;
                float3 lit = FB_Shade(s, GetNormalizedScreenSpaceUV(i.positionCS));
                lit = FB_MixFog(lit, i.positionWS);
                return float4(lit, 1.0);
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
            #pragma vertex LandShadowVert
            #pragma fragment LandShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings LandShadowVert(Attributes v)
            {
                Varyings o = LandVert(v);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - o.positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(o.positionWS, o.normalWS, lightDirectionWS)));
                return o;
            }

            float4 LandShadowFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                LandClip(i);
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
            #pragma vertex LandVert
            #pragma fragment LandDepthFrag
            #pragma multi_compile_instancing

            float4 LandDepthFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                LandClip(i);
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
