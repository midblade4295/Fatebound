// Port of res://scripts/siege/tower.gdshader (the 5v5's towers, towers.gd): a Meshy model in its side's colours from one
// texture (red: its saturated blues turned deep red), breaking as it loses health -- cells whose stage (UV2.x) is at or
// under the instance's "broken" collapse to a point; cracks (box-mapped in the model's own space) spread with "dmg";
// the inside of the shell is dark rubble; the brazier's glow mask while "lit".
// render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx -> opaque, lit, both
// faces.
// As Godot: obj_pos / obj_nrm are Godot's object-space VERTEX / NORMAL (the crack box mapping lands where Godot puts
// it); the collapse runs in the shadow and depth passes too (no shadow from a fallen piece); broken / dmg / lit are
// instance uniforms (per renderer, MaterialPropertyBlock). Godot's DO_SIDE_CHECK turns NORMAL round on a back face and
// the shader turns it back (NORMAL = -NORMAL when !FRONT_FACING): the inside is lit with the outward normal, as here.
// glow_tex and crack_tex have no source_color: read raw (FB_Raw).
Shader "Fatebound/gd/scripts/siege/tower"
{
    Properties
    {
        albedo_tex ("albedo_tex", 2D) = "white" {}
        glow_tex ("glow_tex", 2D) = "black" {}
        crack_tex ("crack_tex", 2D) = "black" {}
        team ("team", Float) = 0
        hue_range ("hue_range", Vector) = (195.0, 258.0, 0, 0)
        sat_range ("sat_range", Vector) = (0.42, 0.58, 0, 0)
        glow_energy ("glow_energy", Float) = 1.8
        crack_tiles ("crack_tiles", Float) = 1.25
        inside_color ("inside_color", Color) = (0.42, 0.37, 0.32, 1)
        broken ("broken (instance)", Float) = 0
        dmg ("dmg (instance)", Float) = 0
        lit ("lit (instance)", Float) = 1
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float team;
        float4 hue_range;
        float4 sat_range;
        float glow_energy;
        float crack_tiles;
        float4 inside_color;
        float broken;
        float dmg;
        float lit;
    CBUFFER_END

    TEXTURE2D(albedo_tex);
    TEXTURE2D(glow_tex);
    TEXTURE2D(crack_tex);

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
        float3 obj_pos : TEXCOORD3;
        float3 obj_nrm : TEXCOORD4;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    float3 tower_rgb2hsv(float3 c)
    {
        float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
        float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
        float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
        float d = q.x - min(q.w, q.y);
        return float3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
    }

    float3 tower_hsv2rgb(float3 c)
    {
        float3 p = abs(frac(c.xxx + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
        return c.z * lerp(1.0, clamp(p - 1.0, 0.0, 1.0), c.y);
    }

    Varyings TowerVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.obj_pos = FB_Mirror(v.positionOS.xyz);
        o.obj_nrm = FB_Mirror(v.normalOS);
        float3 p = v.positionOS.xyz;
        if (v.uv2.x < broken + 0.5)           // (stages are whole numbers; the half allows for vertex compression)
        {
            p = float3(0.0, 0.0, 0.0);        // (the whole triangle collapses: nothing drawn, no shadow)
        }
        o.positionWS = TransformObjectToWorld(p);
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
            #pragma vertex TowerVert
            #pragma fragment TowerFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 TowerFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                bool front = IS_FRONT_VFACE(frontFace, true, false);
                float3 col = FB_SAMPLE(albedo_tex, sampler_TrilinearRepeat, i.uv).rgb;
                if ((int)team != 0)
                {
                    float3 s = pow(max(col, 0.0), 1.0 / 2.2);
                    float3 h = tower_rgb2hsv(s);
                    float deg = h.x * 360.0;
                    float w = smoothstep(hue_range.x - 8.0, hue_range.x + 4.0, deg) * (1.0 - smoothstep(hue_range.y - 4.0, hue_range.y + 8.0, deg));
                    w *= smoothstep(sat_range.x, sat_range.y, h.y);
                    float3 swapped = tower_hsv2rgb(float3(358.0 / 360.0, min(h.y * 1.05, 1.0), h.z * 0.95));
                    col = pow(lerp(s, swapped, w), 2.2);
                }
                float3 glow = col * FB_Raw(FB_SAMPLE(glow_tex, sampler_TrilinearRepeat, i.uv)).r * glow_energy * lit;
                if (dmg > 0.001)
                {
                    float3 bw = pow(abs(i.obj_nrm), 4.0);
                    bw /= (bw.x + bw.y + bw.z + 1.0e-5);
                    float3 p = i.obj_pos * crack_tiles;
                    float2 cx = FB_Raw(FB_SAMPLE(crack_tex, sampler_TrilinearRepeat, p.zy)).rg;
                    float2 cy = FB_Raw(FB_SAMPLE(crack_tex, sampler_TrilinearRepeat, p.xz)).rg;
                    float2 cz = FB_Raw(FB_SAMPLE(crack_tex, sampler_TrilinearRepeat, p.xy)).rg;
                    float2 c = cx * bw.x + cy * bw.y + cz * bw.z;
                    float show = smoothstep(c.y - 0.06, c.y + 0.06, dmg * 1.08);
                    col *= 1.0 - 0.9 * c.x * show;
                }
                // NORMAL as fragment() receives it (DO_SIDE_CHECK), then the shader's own turn on back faces
                float3 N = FB_SideNormal(normalize(i.normalWS), front ? 1.0 : -1.0);
                if (!front)
                {
                    col = inside_color.rgb;
                    glow = 0.0;
                    N = -N;
                }
                FBSurface surf = FB_GodotSurface(i.positionWS, N);
                surf.albedo = FB_ApplyDecals(col, i.positionWS, N);
                surf.roughness = 0.8;
                surf.specular = 0.4;
                surf.emission = glow;
                float3 c2 = FB_Shade(surf, GetNormalizedScreenSpaceUV(i.positionCS));
                c2 = FB_MixFog(c2, i.positionWS);
                return float4(c2, 1.0);
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
            #pragma vertex TowerShadowVert
            #pragma fragment TowerShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings TowerShadowVert(Attributes v)
            {
                Varyings o = TowerVert(v);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - o.positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(o.positionWS, o.normalWS, lightDirectionWS)));
                return o;
            }

            float4 TowerShadowFrag(Varyings i) : SV_Target
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
            #pragma vertex TowerVert
            #pragma fragment TowerDepthFrag
            #pragma multi_compile_instancing

            float4 TowerDepthFrag(Varyings i) : SV_Target
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
