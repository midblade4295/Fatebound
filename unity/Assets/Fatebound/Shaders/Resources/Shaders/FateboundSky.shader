// Fatebound (Unity port): Godot 4's ProceduralSkyMaterial (scene/resources/sky_material.cpp, its generated sky shader)
// as a URP skybox: the sky's top / horizon gradient by the view's elevation (sky_curve), the sun's glow toward the main
// light out to sun_angle_max (sun_curve), the ground's horizon / bottom gradient below (ground_curve), each colour
// times its energy multiplier. Colours arrive linear (MaterialCache.ForSky); the result goes into the HDR scene buffer
// like the rest of the 3D. (No sky cover texture: the game's skies have none.)
Shader "Fatebound/ProceduralSky"
{
    Properties
    {
        _SkyTop ("Sky top", Color) = (0.385, 0.454, 0.55, 1)
        _SkyHorizon ("Sky horizon", Color) = (0.646, 0.656, 0.67, 1)
        _SkyCurve ("Sky curve", Float) = 0.15
        _SkyEnergy ("Sky energy", Float) = 1
        _GroundBottom ("Ground bottom", Color) = (0.2, 0.169, 0.133, 1)
        _GroundHorizon ("Ground horizon", Color) = (0.646, 0.656, 0.67, 1)
        _GroundCurve ("Ground curve", Float) = 0.02
        _GroundEnergy ("Ground energy", Float) = 1
        _SunAngleMax ("Sun angle max (degrees)", Float) = 30
        _SunCurve ("Sun curve", Float) = 0.15
    }
    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" "RenderPipeline"="UniversalPipeline" }
        Cull Off ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
            float4 _SkyTop, _SkyHorizon, _GroundBottom, _GroundHorizon;
            float _SkyCurve, _SkyEnergy, _GroundCurve, _GroundEnergy, _SunAngleMax, _SunCurve;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 dir : TEXCOORD0; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.dir = v.positionOS.xyz;
                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                float3 eye = normalize(i.dir);
                const float HALF_PI_F = 1.5707963;
                float v_angle = acos(clamp(eye.y, -1.0, 1.0));
                float c = 1.0 - v_angle / HALF_PI_F;
                float3 sky = lerp(_SkyHorizon.rgb, _SkyTop.rgb, saturate(1.0 - pow(max(1.0 - c, 0.0), 1.0 / max(_SkyCurve, 0.0001))));
                sky *= _SkyEnergy;
                // the main light (LIGHT0): its glow out to sun_angle_max (a sun of size 0: Godot's default angular distance)
                float3 toSun = _MainLightPosition.xyz;
                if (dot(toSun, toSun) > 0.0)
                {
                    float sunMax = radians(_SunAngleMax);
                    float sun_angle = acos(clamp(dot(normalize(toSun), eye), -1.0, 1.0));
                    if (sun_angle < sunMax)
                    {
                        float c2 = sun_angle / sunMax;
                        sky = lerp(_MainLightColor.rgb, sky, saturate(1.0 - pow(max(1.0 - c2, 0.0), 1.0 / max(_SunCurve, 0.0001))));
                    }
                }
                c = (v_angle - HALF_PI_F) / HALF_PI_F;
                float3 ground = lerp(_GroundHorizon.rgb, _GroundBottom.rgb, saturate(1.0 - pow(max(1.0 - c, 0.0), 1.0 / max(_GroundCurve, 0.0001))));
                ground *= _GroundEnergy;
                return float4(eye.y >= 0.0 ? sky : ground, 1.0);
            }
            ENDHLSL
        }
    }
    Fallback Off
}
