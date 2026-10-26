// Port of the inline shader wyrm_body.gd builds (SHADER: the Grave Wyrm's body, a rigless Meshy mesh): the limbs painted
// into the vertex colours (R wings, G neck, B tail, A legs) bend about their joints -- the wings about a hinge, the neck
// about its base, the tail in a travelling wave, the legs stepping in diagonal pairs; breathing and stirring on TIME;
// the clips drive flap / sweep / pitch / yaw / reach / stride / alive / glow; soul-fire burns in the cyan of its bones.
// render_mode cull_disabled (diffuse_burley, specular_schlick_ggx by default) -> opaque, lit, both faces.
// As Godot: the whole vertex() runs in Godot's object space (VERTEX / NORMAL mirrored in, mirrored out), so the joints
// (wing_l, wing_r, neck_root, tail_root, mid_x: Godot coordinates, set raw) and the turns (rx / ry / rz, GLSL's column
// matrices written as HLSL rows) are Godot's. The shadow and depth passes bend the same way. Godot's DO_SIDE_CHECK
// turns NORMAL round on back faces.
Shader "Fatebound/gd/inline/wyrm_body_wyrm"
{
    Properties
    {
        albedo_tex ("albedo_tex", 2D) = "white" {}
        wing_l ("wing_l", Vector) = (0, 0, 0, 0)
        wing_r ("wing_r", Vector) = (0, 0, 0, 0)
        neck_root ("neck_root", Vector) = (0, 0, 0, 0)
        tail_root ("tail_root", Vector) = (0, 0, 0, 0)
        mid_x ("mid_x", Float) = 0
        rest_yaw ("rest_yaw", Float) = 0
        flap ("flap", Float) = 0
        sweep ("sweep", Float) = 0
        pitch ("pitch", Float) = 0
        yaw ("yaw", Float) = 0
        reach ("reach", Float) = 0
        stride ("stride", Float) = 0
        alive ("alive", Float) = 1
        glow ("glow", Float) = 1
        [HideInInspector] _InstColor ("Instance Color", Color) = (1, 1, 1, 1)
    }

    HLSLINCLUDE
    #include "../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 wing_l;
        float4 wing_r;
        float4 neck_root;
        float4 tail_root;
        float mid_x;
        float rest_yaw;
        float flap;
        float sweep;
        float pitch;
        float yaw;
        float reach;
        float stride;
        float alive;
        float glow;
    CBUFFER_END

    UNITY_INSTANCING_BUFFER_START(FBPerInstance)
        UNITY_DEFINE_INSTANCED_PROP(float4, _InstColor)
    UNITY_INSTANCING_BUFFER_END(FBPerInstance)

    TEXTURE2D(albedo_tex);

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
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float2 uv : TEXCOORD2;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    // GLSL rx / ry / rz (mat3 from columns), as HLSL matrices with the same rows: mul(M, v) == GLSL's M * v
    float3x3 wyrm_rx(float a) { float c = cos(a); float s = sin(a); return float3x3(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c); }
    float3x3 wyrm_ry(float a) { float c = cos(a); float s = sin(a); return float3x3(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c); }
    float3x3 wyrm_rz(float a) { float c = cos(a); float s = sin(a); return float3x3(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0); }

    // Godot's vertex(): VERTEX / NORMAL in Godot's object space; returns them in Unity's
    void WyrmVertex(float3 positionOS, float3 normalOS, float4 COL, out float3 outPos, out float3 outNormal)
    {
        float3 v = FB_Mirror(positionOS);
        float3 n = FB_Mirror(normalOS);
        float t = _FB_Time;
        float ww = COL.r;
        float nk = COL.g;
        float tl = COL.b;
        float lg = (COL.a * 255.0 - 128.0) / 127.0;
        // breathing: the ribs rise and swell
        float core = (1.0 - ww) * (1.0 - nk) * (1.0 - tl) * (1.0 - abs(lg));
        float br = (0.5 + 0.5 * sin(t * 1.25)) * alive * core * smoothstep(0.9, 1.8, v.y) * (1.0 - smoothstep(2.6, 3.2, v.y));
        v.x += (v.x - mid_x) * 0.035 * br;
        v.y += 0.05 * br;
        if (ww > 0.0)
        {
            float side = v.x > mid_x ? 1.0 : -1.0;
            float3 root = side > 0.0 ? wing_r.xyz : wing_l.xyz;
            float a = (flap + alive * (0.05 + 0.06 * sin(t * 1.25 + 0.5))) * ww * side;
            float3x3 r = mul(wyrm_rz(a), wyrm_ry(-sweep * ww * side));
            v = root + mul(r, v - root);
            n = mul(r, n);
        }
        if (nk > 0.0)
        {
            float p = pitch + alive * 0.07 * sin(t * 0.8);
            float y = rest_yaw + yaw + alive * 0.12 * sin(t * 0.45 + 1.0);
            float3x3 r = mul(wyrm_ry(y * nk), wyrm_rx(p * nk));
            v = neck_root.xyz + mul(r, v - neck_root.xyz) + float3(0.0, -0.25 * reach, reach) * nk;
            n = mul(r, n);
        }
        if (tl > 0.0)
        {
            float d = length((v - tail_root.xyz).xz);
            float a = (0.06 + 0.1 * alive) * sin(t * 1.5 - d * 1.2) * tl;
            float3x3 r = wyrm_ry(a);
            v = tail_root.xyz + mul(r, v - tail_root.xyz);
            n = mul(r, n);
        }
        if (lg != 0.0 && stride > 0.0)
        {
            float s = sin(t * 7.0) * sign(lg);
            float k = stride * abs(lg);
            v.y += k * max(0.0, s) * 0.3;
            v.z += k * s * 0.22;
        }
        outPos = FB_Mirror(v);
        outNormal = FB_Mirror(normalize(n));
    }

    Varyings WyrmVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        float3 p, n;
        WyrmVertex(v.positionOS.xyz, v.normalOS, v.color * UNITY_ACCESS_INSTANCED_PROP(FBPerInstance, _InstColor), p, n);
        o.positionWS = TransformObjectToWorld(p);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        o.normalWS = TransformObjectToWorldNormal(n);
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
            #pragma vertex WyrmVert
            #pragma fragment WyrmFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 WyrmFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float4 c = FB_SAMPLE(albedo_tex, sampler_TrilinearRepeat, i.uv);
                FBSurface s = FB_GodotSurface(i.positionWS, FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0)));
                s.albedo = FB_ApplyDecals(c.rgb, i.positionWS, s.normalWS);
                s.roughness = 0.8;
                // the cyan in its bones burns: soul-fire
                float soul = smoothstep(0.08, 0.22, min(c.g, c.b) - c.r);
                s.emission = c.rgb * soul * glow * (2.0 + 0.8 * sin(_FB_Time * 2.6));
                float3 col = FB_Shade(s, GetNormalizedScreenSpaceUV(i.positionCS));
                col = FB_MixFog(col, i.positionWS);
                return float4(col, 1.0);
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
            #pragma vertex WyrmShadowVert
            #pragma fragment WyrmShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings WyrmShadowVert(Attributes v)
            {
                Varyings o = WyrmVert(v);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - o.positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(o.positionWS, o.normalWS, lightDirectionWS)));
                return o;
            }

            float4 WyrmShadowFrag(Varyings i) : SV_Target
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
            #pragma vertex WyrmVert
            #pragma fragment WyrmDepthFrag
            #pragma multi_compile_instancing

            float4 WyrmDepthFrag(Varyings i) : SV_Target
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
