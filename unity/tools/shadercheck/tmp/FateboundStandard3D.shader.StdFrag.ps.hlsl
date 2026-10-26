
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
            #pragma vertex StdVert
            #pragma fragment StdFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            float4 StdFrag(Varyings i, float facing : VFACE) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float2 uv = i.uv;
                float4 tex = FB_TEX(_MainTex, uv);
                float3 albedo = _Color.rgb * tex.rgb;
                float alpha = _Color.a * tex.a;
                if (_VertexColor > 0.5) { albedo *= i.color.rgb; alpha *= i.color.a; }
                albedo = FB_ApplyDecals(albedo, i.positionWS, i.normalWS);
                int alphaMode = (int)_AlphaMode;
                if (alphaMode == 2) clip(alpha - _AlphaScissor);
                if (alphaMode == 3)
                {
                    // alpha hash: a stable per-pixel threshold
                    float h = frac(sin(dot(floor(i.positionCS.xy), float2(12.9898, 78.233))) * 43758.5453);
                    clip(alpha - h);
                }
                if (_DistanceFade > 0.5)
                {
                    float d = distance(GetCameraPositionWS(), i.positionWS);
                    float f = smoothstep(_DistanceFadeMin, _DistanceFadeMax, d);
                    if (_DistanceFadeMin > _DistanceFadeMax) f = 1.0 - smoothstep(_DistanceFadeMax, _DistanceFadeMin, d);
                    if ((int)_DistanceFade == 1) alpha *= f;
                    else
                    {
                        float h = frac(sin(dot(floor(i.positionCS.xy), float2(12.9898, 78.233))) * 43758.5453);
                        clip(f - h);
                    }
                }
                float3 color;
                if (_Unshaded > 0.5)
                {
                    color = albedo;
                }
                else
                {
                    FBSurface s = (FBSurface)0;
                    s.albedo = albedo;
                    s.alpha = alpha;
                    s.metallic = _Metallic * dot(FB_TEX(_MetallicTex, uv), _MetallicChannel);
                    s.roughness = _Roughness * dot(FB_TEX(_RoughnessTex, uv), _RoughnessChannel);
                    s.specular = _Specular;
                    s.ao = _AOOn > 0.5 ? dot(FB_TEX(_AOTex, uv), _AOChannel) : 1.0;
                    s.positionWS = i.positionWS;
                    float3 n = normalize(i.normalWS) * (facing > 0 ? 1.0 : -1.0);
                    if (_NormalOn > 0.5)
                    {
                        float3 nm = FB_TEX(_NormalTex, uv).xyz * 2.0 - 1.0;
                        nm.xy *= _NormalScale;
                        nm.z = sqrt(saturate(1.0 - dot(nm.xy, nm.xy)));
                        float3 t = normalize(i.tangentWS.xyz);
                        float3 b = cross(n, t) * i.tangentWS.w;
                        n = normalize(t * nm.x + b * nm.y + n * nm.z);
                    }
                    s.normalWS = n;
                    float3 em = 0;
                    if (_EmissionOn > 0.5)
                    {
                        float3 et = FB_TEX(_EmissionTex, uv).rgb;
                        em = (_EmissionOp > 0.5 ? _Emission.rgb * et : _Emission.rgb + et) * _EmissionEnergy;
                    }
                    s.emission = em;
                    s.diffuseBurley = _DiffuseBurley;
                    s.specularOn = _SpecularOn;
                    s.receiveShadows = _ReceiveShadows;
                    color = FB_Shade(s, GetNormalizedScreenSpaceUV(i.positionCS));
                }
                if (_FogOff < 0.5)
                {
                    float4 fog = FB_Fog(i.positionWS);
                    int bm = (int)_BlendModeFog;
                    if (bm == 0) color = lerp(color, fog.rgb, fog.a);
                    else if (bm == 3) color = lerp(color, 1.0, fog.a);
                    else color *= 1.0 - fog.a;
                }
                if (alphaMode == 0 || alphaMode == 2 || alphaMode == 3) alpha = 1.0;
                return float4(color, alpha);
            }
            