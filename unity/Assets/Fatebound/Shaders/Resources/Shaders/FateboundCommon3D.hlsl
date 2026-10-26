// Fatebound (Unity port): what every 3D shader shares -- Godot's conventions on top of URP.
//  * Mesh UVs are Godot's (v down). Unity textures are stored bottom-up: sample through FB_TEX / FB_UV.
//  * Lighting is Godot 4's forward lighting (scene_forward_lights_inc.glsl): Lambert or Burley diffuse, Schlick-GGX
//    specular, omni falloff (1 - (d/r)^4)^2 / d, the flat ambient colour the game uses (AMBIENT_SOURCE_COLOR), Godot's
//    fog (exponential or depth, height fog, sun scatter). Light colour * energy arrive from Unity lights (linear).
//  * Tonemapping, glow and adjustments are applied afterwards by the viewport's post pass (Fatebound/Post).
//  * The renderer sets the _FB_* globals per camera (its world's Environment).
#ifndef FATEBOUND_COMMON_3D_INCLUDED
#define FATEBOUND_COMMON_3D_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// ---- per camera (its world's Environment) ----
float4 _FB_Ambient;        // rgb: ambient light colour * energy (linear); a: unused
float4 _FB_FogColor;       // rgb: fog light colour * energy (linear); a: 1 when fog is on
float4 _FB_FogParams;      // x: density, y: sun scatter, z: height, w: height density
float4 _FB_FogDepth;       // x: depth begin, y: depth end, z: depth curve, w: 1 = depth fog (else exponential)
float  _FB_Time;           // Godot's TIME (seconds, wraps like Godot's: rendering/limits/time/time_rollover_secs)

#define FB_PI 3.14159265358979323846

// Godot UV <-> Unity texture coordinate
#define FB_UV(uv) float2((uv).x, 1.0 - (uv).y)
#define FB_TEX(tex, uv) SAMPLE_TEXTURE2D(tex, sampler##tex, FB_UV(uv))
#define FB_TEX_LOD(tex, uv, lod) SAMPLE_TEXTURE2D_LOD(tex, sampler##tex, FB_UV(uv), lod)

float FB_SchlickFresnel(float u)
{
    float m = 1.0 - u;
    float m2 = m * m;
    return m2 * m2 * m;
}

float FB_D_GGX(float cos_theta_m, float alpha)
{
    float a = cos_theta_m * alpha;
    float k = alpha / (1.0 - cos_theta_m * cos_theta_m + a * a);
    return k * k * (1.0 / FB_PI);
}

float FB_V_GGX(float NdotL, float NdotV, float alpha)
{
    return 0.5 / lerp(2.0 * NdotL * NdotV, NdotL + NdotV, alpha);
}

float3 FB_F0(float metallic, float specular, float3 albedo)
{
    float dielectric = 0.16 * specular * specular;
    return lerp(dielectric.xxx, albedo, metallic.xxx);
}

struct FBSurface
{
    float3 albedo;
    float  alpha;
    float  metallic;
    float  roughness;
    float  specular;       // 0..1 (Godot's specular, 0.5 default)
    float3 emission;
    float  ao;
    float3 normalWS;
    float3 positionWS;
    float  diffuseBurley;  // 1: DIFFUSE_BURLEY, 0: Lambert
    float  specularOn;     // 0: SPECULAR_DISABLED
    float  receiveShadows;
};

// One light's contribution, Godot's light_compute (diffuse and specular separately).
// specAmount: Godot uploads light_specular (0.5 default) for directional lights and light_specular * 2 for omni/spot.
void FB_LightCompute(float3 N, float3 L, float3 V, float3 lightColor, float attenuation, float specAmount, FBSurface s,
                     inout float3 diffuse, inout float3 specular)
{
    float NdotL = min(dot(N, L), 1.0);
    float cNdotL = max(NdotL, 0.0);
    float NdotV = dot(N, V);
    float cNdotV = max(NdotV, 1e-4);
    float3 H = normalize(V + L);
    float cLdotH = clamp(dot(L, H), 0.0, 1.0);
    float cNdotH = clamp(dot(N, H), 0.0, 1.0);
    float diffuse_brdf_NL;
    if (s.diffuseBurley > 0.5)
    {
        float FD90_minus_1 = 2.0 * cLdotH * cLdotH * s.roughness - 0.5;
        float FdV = 1.0 + FD90_minus_1 * FB_SchlickFresnel(cNdotV);
        float FdL = 1.0 + FD90_minus_1 * FB_SchlickFresnel(cNdotL);
        diffuse_brdf_NL = (1.0 / FB_PI) * FdV * FdL * cNdotL;
    }
    else diffuse_brdf_NL = cNdotL * (1.0 / FB_PI);
    // (Godot uploads light energy * PI: the 1/PI above cancels it, as in Godot)
    diffuse += lightColor * FB_PI * diffuse_brdf_NL * attenuation;
    if (s.specularOn > 0.5 && s.roughness > 0.0)
    {
        float alpha_ggx = s.roughness * s.roughness;
        float D = FB_D_GGX(cNdotH, alpha_ggx);
        float G = FB_V_GGX(cNdotL, cNdotV, alpha_ggx);
        float cLdotH5 = FB_SchlickFresnel(cLdotH);
        float3 f0 = FB_F0(s.metallic, s.specular, s.albedo);
        float f90 = clamp(dot(f0, (50.0 * 0.33).xxx), s.metallic, 1.0);
        float3 F = f0 + (f90 - f0) * cLdotH5;
        float3 specular_brdf_NL = cNdotL * D * F * G;
        specular += specular_brdf_NL * lightColor * FB_PI * attenuation * specAmount;
    }
}

float3 FB_AdditionalLightPosition(uint lightIndex)
{
#if USE_STRUCTURED_BUFFER_FOR_LIGHT_DATA
    return _AdditionalLightsBuffer[lightIndex].position.xyz;
#else
    return _AdditionalLightsPosition[lightIndex].xyz;
#endif
}

// Godot's lighting for a surface: every light, the ambient light, emission. Unshaded surfaces don't come here.
float3 FB_Shade(FBSurface s, float2 normalizedScreenSpaceUV)
{
    float3 N = normalize(s.normalWS);
    float3 V = normalize(GetWorldSpaceViewDir(s.positionWS));
    float3 diffuse = 0, specular = 0;

    float4 shadowCoord = TransformWorldToShadowCoord(s.positionWS);
    Light main = GetMainLight(shadowCoord);
    float mainShadow = s.receiveShadows > 0.5 ? main.shadowAttenuation : 1.0;
    FB_LightCompute(N, main.direction, V, main.color, main.distanceAttenuation * mainShadow, 0.5, s, diffuse, specular);

#if defined(_ADDITIONAL_LIGHTS)
    InputData inputData = (InputData)0;
    inputData.positionWS = s.positionWS;
    inputData.normalizedScreenSpaceUV = normalizedScreenSpaceUV;
    uint lightCount = GetAdditionalLightsCount();
    LIGHT_LOOP_BEGIN(lightCount)
        Light light = GetAdditionalLight(lightIndex, s.positionWS);
        // URP's falloff is (1 - (d/r)^4)^2 / d^2; Godot's (omni_attenuation 1) is (1 - (d/r)^4)^2 / d
        float d = length(FB_AdditionalLightPosition(
#if USE_CLUSTER_LIGHT_LOOP
            lightIndex
#else
            GetPerObjectLightIndex(lightIndex)
#endif
            ) - s.positionWS);
        FB_LightCompute(N, light.direction, V, light.color, light.distanceAttenuation * d, 1.0, s, diffuse, specular);
    LIGHT_LOOP_END
#endif

    float3 ambient = _FB_Ambient.rgb * s.ao;
    float3 color = (diffuse + ambient) * s.albedo * (1.0 - s.metallic) + specular + s.emission;
    return color;
}

// Godot's fog (fog_process): rgb = the fog colour, a = how much of it. viewPos: the fragment in view space.
float4 FB_Fog(float3 positionWS)
{
    if (_FB_FogColor.a < 0.5) return float4(0, 0, 0, 0);
    float3 viewPos = TransformWorldToView(positionWS);
    float3 fogColor = _FB_FogColor.rgb;
    if (_FB_FogParams.y > 0.001)
    {
        float3 view = normalize(positionWS - GetCameraPositionWS());
        Light main = GetMainLight();
        float lightAmount = pow(max(dot(view, main.direction), 0.0), 8.0);    // (main.direction points at the light)
        fogColor += main.color * FB_PI * lightAmount * _FB_FogParams.y;       // (Godot's light energy carries PI)
    }
    float dist = length(viewPos);
    float fogAmount;
    if (_FB_FogDepth.w > 0.5)
    {
        float fog_z = smoothstep(_FB_FogDepth.x, _FB_FogDepth.y, dist);
        fogAmount = pow(fog_z, _FB_FogDepth.z) * _FB_FogParams.x;
    }
    else fogAmount = 1.0 - exp(min(0.0, -dist * _FB_FogParams.x));
    if (abs(_FB_FogParams.w) >= 0.0001)
    {
        float y_dist = positionWS.y - _FB_FogParams.z;
        float vfog = 1.0 - exp(min(0.0, y_dist * _FB_FogParams.w));
        fogAmount = max(vfog, fogAmount);
    }
    return float4(fogColor, saturate(fogAmount));
}

// Billboards (BaseMaterial3D billboard modes): the object's axes replaced by the camera's (Godot's
// MODELVIEW = VIEW * mat4(INV_VIEW[0], INV_VIEW[1], INV_VIEW[2], MODEL[3])). Unity's view space is Godot's (see
// Conv.cs), so UNITY_MATRIX_I_V's columns are the camera's right/up/back in Unity world; the object-space point is
// Godot's mirrored, so its x goes back through -x. mode 1: BILLBOARD_ENABLED, 2: FIXED_Y, 3: PARTICLES (the camera's
// axes normalized, then turned by INSTANCE_CUSTOM.x about the view axis). The object's scale is kept only with
// billboard_keep_scale, as in Godot (a particle's scale needs it too).
float3 FB_BillboardWorld(float3 positionOS, int mode, float keepScale, float particleAngle)
{
    float4x4 m = GetObjectToWorldMatrix();
    float3 origin = float3(m._m03, m._m13, m._m23);
    float3 sx = float3(m._m00, m._m10, m._m20), sy = float3(m._m01, m._m11, m._m21), sz = float3(m._m02, m._m12, m._m22);
    float3 scale = keepScale > 0.5 ? float3(length(sx), length(sy), length(sz)) : float3(1, 1, 1);
    float4x4 iv = UNITY_MATRIX_I_V;
    float3 right = float3(iv._m00, iv._m10, iv._m20);
    float3 up = float3(iv._m01, iv._m11, iv._m21);
    float3 back = float3(iv._m02, iv._m12, iv._m22);
    if (mode == 2)
    {
        // Godot: right = normalize(cross(Y, back)), back = normalize(cross(cam_right, Y)) -- in the mirrored space a
        // cross product changes sign
        float3 y = float3(0, 1, 0);
        float3 r2 = -normalize(cross(y, back));
        float3 b2 = -normalize(cross(right, y));
        right = r2;
        up = y;
        back = b2;
    }
    float3 g = float3(-positionOS.x, positionOS.y, positionOS.z) * scale;     // the point in Godot's object space
    if (mode == 3)
    {
        right = normalize(right);
        up = normalize(up);
        back = normalize(back);
        float c = cos(particleAngle), s = sin(particleAngle);
        g = float3(c * g.x + s * g.y, -s * g.x + c * g.y, g.z);
    }
    return origin + right * g.x + up * g.y + back * g.z;
}

// BILLBOARD_PARTICLES' flipbook: the UV of frame floor(INSTANCE_CUSTOM.z * frames) (Godot UVs, v down)
float2 FB_ParticleAnimUV(float2 uv, float animPhase, float hFrames, float vFrames, float loop)
{
    float total = hFrames * vFrames;
    float frame = floor(animPhase * total);
    if (loop < 0.5) frame = clamp(frame, 0.0, total - 1.0);
    else frame = frame - total * floor(frame / total);
    uv /= float2(hFrames, vFrames);
    uv += float2(fmod(frame, hFrames) / hFrames, floor((frame + 0.5) / hFrames) / vFrames);
    return uv;
}

// ---------------------------------------------------------------------------------------------------------------------
// Helpers for the ported Godot shaders (Shaders/Resources/Shaders/gd/).

// Godot's space <-> Unity's: X mirrored (points, directions, normals alike; its own inverse).
float3 FB_Mirror(float3 v) { return float3(-v.x, v.y, v.z); }

// GLSL's mod (x - y * floor(x / y): takes the sign of y), not HLSL's fmod (truncates toward zero).
float FB_Mod(float x, float y) { return x - y * floor(x / y); }
float2 FB_Mod(float2 x, float2 y) { return x - y * floor(x / y); }
float3 FB_Mod(float3 x, float3 y) { return x - y * floor(x / y); }

// Sampling at a Godot UV (v down) with a given sampler (the shader's own sampler hints: URP's global inline samplers
// sampler_{Point,Linear,Trilinear}{Clamp,Repeat}).
#define FB_SAMPLE(tex, smp, godotUV) SAMPLE_TEXTURE2D(tex, smp, FB_UV(godotUV))
#define FB_SAMPLE_LOD(tex, smp, godotUV, lod) SAMPLE_TEXTURE2D_LOD(tex, smp, FB_UV(godotUV), lod)

// A texture read by a Godot shader WITHOUT source_color: Godot hands the shader the stored (sRGB-encoded) texel values,
// Unity's sampler decodes the game's colour images (sRGB textures: every RGBA image UnityGuiHost uploads, and imported
// images by default) to linear -- encode back. Alpha is never decoded. (A texture created linear would be brightened.)
float4 FB_Raw(float4 t) { return float4(LinearToSRGB(saturate(t.rgb)), t.a); }

// Godot's MODEL_MATRIX[3].xyz (the node's, or a MultiMesh instance's / particle's, origin) in Godot's world space.
float3 FB_GodotModelOrigin()
{
    float4x4 m = GetObjectToWorldMatrix();
    return float3(-m._m03, m._m13, m._m23);
}

// Godot's (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz for a Godot object-space point: the point in Godot's world space.
float3 FB_GodotWorldPos(float3 positionGodotOS) { return FB_Mirror(TransformObjectToWorld(FB_Mirror(positionGodotOS))); }

// Godot's (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz (the model matrix, not its inverse transpose), in Godot's world space.
float3 FB_GodotWorldDir(float3 dirGodotOS) { return FB_Mirror(TransformObjectToWorldDir(FB_Mirror(dirGodotOS), false)); }

// Godot's DO_SIDE_CHECK (cull_disabled / cull_front): NORMAL turned round on back faces before fragment() runs.
float3 FB_SideNormal(float3 n, float facing) { return facing > 0 ? n : -n; }

// A surface with Godot's spatial defaults: ALBEDO 1, ALPHA 1, METALLIC 0, ROUGHNESS 1, SPECULAR 0.5, AO 1, no emission;
// diffuse_burley and specular_schlick_ggx (the default render modes), shadows received.
FBSurface FB_GodotSurface(float3 positionWS, float3 normalWS)
{
    FBSurface s = (FBSurface)0;
    s.albedo = 1.0;
    s.alpha = 1.0;
    s.metallic = 0.0;
    s.roughness = 1.0;
    s.specular = 0.5;
    s.emission = 0.0;
    s.ao = 1.0;
    s.normalWS = normalWS;
    s.positionWS = positionWS;
    s.diffuseBurley = 1.0;
    s.specularOn = 1.0;
    s.receiveShadows = 1.0;
    return s;
}

// Godot's fixed fog over a fragment's final colour (the scene shader mixes it in for every blend mode, unshaded too,
// unless fog_disabled).
float3 FB_MixFog(float3 color, float3 positionWS)
{
    float4 fog = FB_Fog(positionWS);
    return lerp(color, fog.rgb, fog.a);
}

// Godot's normal map (NORMAL_MAP, NORMAL_MAP_DEPTH): RG unpacked, Z rebuilt, mixed over the normal by the depth --
// scene_forward_mobile.glsl, in world space (tangent and binormal as the mesh gives them, unnormalised per MikkTSpace).
float3 FB_ApplyNormalMap(float3 normalWS, float3 tangentWS, float3 binormalWS, float3 normalMap, float depth)
{
    float2 xy = normalMap.xy * 2.0 - 1.0;
    float z = sqrt(max(0.0, 1.0 - dot(xy, xy)));
    return normalize(lerp(normalWS, tangentWS * xy.x + binormalWS * xy.y + normalWS * z, depth));
}

// ---- Decals (Godot's Decal node, as scene_forward_mobile.glsl applies them: before lighting, to the albedo) ----
// The renderer sets, per camera, the nearest FB_MAX_DECALS decals of its world: _FB_DecalXf maps a Unity world point
// to Godot's uv_local (xz 0..1 across the box, y -1..1 bottom to top), _FB_DecalModulate is the modulate (linear rgb,
// alpha * distance fade), _FB_DecalParams (albedo_mix, upper_fade, lower_fade, normal_fade), _FB_DecalUp the box's up
// axis in Unity world. A shader calls FB_ApplyDecals on its albedo with the geometric (vertex) normal.
#define FB_MAX_DECALS 4
float4 _FB_DecalCount;
float4x4 _FB_DecalXf[FB_MAX_DECALS];
float4 _FB_DecalModulate[FB_MAX_DECALS];
float4 _FB_DecalParams[FB_MAX_DECALS];
float4 _FB_DecalUp[FB_MAX_DECALS];
TEXTURE2D(_FB_DecalTex0); TEXTURE2D(_FB_DecalTex1); TEXTURE2D(_FB_DecalTex2); TEXTURE2D(_FB_DecalTex3);
SamplerState sampler_FB_linear_clamp;

float4 FB_DecalSample(int i, float2 uv)
{
    float2 u = FB_UV(uv);
    if (i == 0) return SAMPLE_TEXTURE2D_LOD(_FB_DecalTex0, sampler_FB_linear_clamp, u, 0);
    if (i == 1) return SAMPLE_TEXTURE2D_LOD(_FB_DecalTex1, sampler_FB_linear_clamp, u, 0);
    if (i == 2) return SAMPLE_TEXTURE2D_LOD(_FB_DecalTex2, sampler_FB_linear_clamp, u, 0);
    return SAMPLE_TEXTURE2D_LOD(_FB_DecalTex3, sampler_FB_linear_clamp, u, 0);
}

float3 FB_ApplyDecals(float3 albedo, float3 positionWS, float3 geoNormalWS)
{
    int n = (int)_FB_DecalCount.x;
    [unroll] for (int i = 0; i < FB_MAX_DECALS; i++)
    {
        if (i >= n) break;
        float3 uvl = mul(_FB_DecalXf[i], float4(positionWS, 1.0)).xyz;
        if (any(uvl < float3(0.0, -1.0, 0.0)) || any(uvl > float3(1.0, 1.0, 1.0))) continue;
        float4 prm = _FB_DecalParams[i];
        float fade = pow(1.0 - abs(uvl.y), uvl.y > 0.0 ? prm.y : prm.z);
        if (prm.w > 0.0) fade *= smoothstep(prm.w, 1.0, dot(normalize(geoNormalWS), _FB_DecalUp[i].xyz) * 0.5 + 0.5);
        float4 da = FB_DecalSample(i, uvl.xz) * _FB_DecalModulate[i];
        da.a *= fade;
        albedo = lerp(albedo, da.rgb, da.a * prm.x);
    }
    return albedo;
}

#endif
