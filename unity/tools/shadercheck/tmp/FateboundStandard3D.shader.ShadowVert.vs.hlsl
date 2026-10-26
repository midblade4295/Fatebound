
    #include "FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 _Color;
        float4 _MainTex_ST;
        float4 _UV1Scale, _UV1Offset;
        float _Metallic, _Roughness, _Specular;
        float4 _MetallicChannel, _RoughnessChannel;
        float _NormalOn, _NormalScale;
        float4 _Emission;
        float _EmissionEnergy, _EmissionOn, _EmissionOp;
        float _AOOn, _AOLightAffect;
        float4 _AOChannel;
        float _Unshaded, _DiffuseBurley, _SpecularOn, _VertexColor, _VertexColorSrgb;
        float _AlphaMode, _AlphaScissor;
        float _Billboard, _BillboardKeepScale;
        float4 _ParticlesAnim;
        float _FogOff, _ReceiveShadows;
        float _DistanceFade, _DistanceFadeMin, _DistanceFadeMax;
        float _BlendModeFog, _Grow;
        float _RimOn, _Rim, _RimTint;
    CBUFFER_END

    UNITY_INSTANCING_BUFFER_START(FBPerInstance)
        UNITY_DEFINE_INSTANCED_PROP(float4, _InstColor)
        UNITY_DEFINE_INSTANCED_PROP(float4, _InstCustom)
    UNITY_INSTANCING_BUFFER_END(FBPerInstance)

    TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
    TEXTURE2D(_MetallicTex); SAMPLER(sampler_MetallicTex);
    TEXTURE2D(_RoughnessTex); SAMPLER(sampler_RoughnessTex);
    TEXTURE2D(_NormalTex); SAMPLER(sampler_NormalTex);
    TEXTURE2D(_EmissionTex); SAMPLER(sampler_EmissionTex);
    TEXTURE2D(_AOTex); SAMPLER(sampler_AOTex);

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS : NORMAL;
        float4 tangentOS : TANGENT;
        float4 color : COLOR;
        float2 uv : TEXCOORD0;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 positionWS : TEXCOORD0;
        float3 normalWS : TEXCOORD1;
        float4 tangentWS : TEXCOORD2;
        float2 uv : TEXCOORD3;
        float4 color : COLOR;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    float3 FB_StdWorldPosition(Attributes v)
    {
        float3 p = v.positionOS.xyz;
        if (_Grow != 0) p += normalize(v.normalOS) * _Grow;
        int mode = (int)_Billboard;
        if (mode != 0) return FB_BillboardWorld(p, mode, _BillboardKeepScale, UNITY_ACCESS_INSTANCED_PROP(FBPerInstance, _InstCustom).x);
        return TransformObjectToWorld(p);
    }

    Varyings StdVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        o.positionWS = FB_StdWorldPosition(v);
        o.positionCS = TransformWorldToHClip(o.positionWS);
        int mode = (int)_Billboard;
        if (mode != 0)
        {
            // a billboard faces the camera: its normal is the view's back vector
            float4x4 iv = UNITY_MATRIX_I_V;
            o.normalWS = normalize(float3(iv._m02, iv._m12, iv._m22));
            o.tangentWS = float4(normalize(float3(iv._m00, iv._m10, iv._m20)), 1);
        }
        else
        {
            o.normalWS = TransformObjectToWorldNormal(v.normalOS);
            o.tangentWS = float4(TransformObjectToWorldDir(v.tangentOS.xyz), v.tangentOS.w * GetOddNegativeScale());
        }
        o.uv = v.uv * _UV1Scale.xy + _UV1Offset.xy;
                if ((int)_Billboard == 3) o.uv = FB_ParticleAnimUV(o.uv, UNITY_ACCESS_INSTANCED_PROP(FBPerInstance, _InstCustom).z, _ParticlesAnim.x, _ParticlesAnim.y, _ParticlesAnim.z);
        float4 c = v.color;
        if (_VertexColorSrgb > 0.5) c.rgb = SRGBToLinear(c.rgb);
        o.color = c * UNITY_ACCESS_INSTANCED_PROP(FBPerInstance, _InstColor);
        return o;
    }

    float StdAlpha(Varyings i, float2 uv)
    {
        float a = _Color.a * FB_TEX(_MainTex, uv).a;
        if (_VertexColor > 0.5) a *= i.color.a;
        return a;
    }
    

            #pragma target 3.0
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings ShadowVert(Attributes v)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                float3 positionWS = FB_StdWorldPosition(v);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                o.positionCS = ApplyShadowClamping(TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS)));
                o.uv = v.uv * _UV1Scale.xy + _UV1Offset.xy;
                if ((int)_Billboard == 3) o.uv = FB_ParticleAnimUV(o.uv, UNITY_ACCESS_INSTANCED_PROP(FBPerInstance, _InstCustom).z, _ParticlesAnim.x, _ParticlesAnim.y, _ParticlesAnim.z);
                o.color = v.color;
                return o;
            }

            float4 ShadowFrag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                int alphaMode = (int)_AlphaMode;
                if (alphaMode == 2) clip(StdAlpha(i, i.uv) - _AlphaScissor);
                return 0;
            }
            