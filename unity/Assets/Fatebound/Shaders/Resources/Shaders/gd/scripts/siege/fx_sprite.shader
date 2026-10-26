// Port of res://scripts/siege/fx_sprite.gdshader (weapon and spell effect sprites, on GPU particles and on plain
// quads): a grayscale painted sprite (brightness in R) added in the particle's colour, its brightest part white-hot
// (core); billboarded like BaseMaterial3D's particle billboard (turned by INSTANCE_CUSTOM.x + TIME * spin), or laid flat
// in its own plane (lie_flat); a grid x grid atlas picks a variant by INSTANCE_CUSTOM.z; pulse breathes it.
// render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled -> transparent,
// Godot's add blend, no depth write, both faces.
// As Godot: MODELVIEW_MATRIX = VIEW * mat4(normalised camera axes, MODEL[3]) * rot * scale is FB_BillboardWorld's
// particle mode (scale kept); lie_flat turns VERTEX in Godot's object space. COLOR = vertex colour * the particle's /
// instance's colour (_InstColor), INSTANCE_CUSTOM = _InstCustom. tex has no source_color: read raw (FB_Raw).
Shader "Fatebound/gd/scripts/siege/fx_sprite"
{
    Properties
    {
        tex ("tex", 2D) = "white" {}
        tint ("tint", Color) = (1, 1, 1, 1)
        grid ("grid", Float) = 1
        core ("core", Float) = 0.6
        energy ("energy", Float) = 1
        spin ("spin", Float) = 0
        pulse ("pulse", Float) = 0
        lie_flat ("lie_flat", Float) = 0
        [HideInInspector] _InstColor ("Instance Color", Color) = (1, 1, 1, 1)
        [HideInInspector] _InstCustom ("Instance Custom", Vector) = (0, 0, 0, 0)
    }

    HLSLINCLUDE
    #include "../../../FateboundCommon3D.hlsl"

    CBUFFER_START(UnityPerMaterial)
        float4 tint;
        float grid;
        float core;
        float energy;
        float spin;
        float pulse;
        float lie_flat;
    CBUFFER_END

    UNITY_INSTANCING_BUFFER_START(FBPerInstance)
        UNITY_DEFINE_INSTANCED_PROP(float4, _InstColor)
        UNITY_DEFINE_INSTANCED_PROP(float4, _InstCustom)
    UNITY_INSTANCING_BUFFER_END(FBPerInstance)

    TEXTURE2D(tex);

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
        float3 normalWS : TEXCOORD2;       // (for the decals' normal fade)
        float4 color : COLOR;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    Varyings SpriteVert(Attributes v)
    {
        Varyings o = (Varyings)0;
        UNITY_SETUP_INSTANCE_ID(v);
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        float4 custom = UNITY_ACCESS_INSTANCED_PROP(FBPerInstance, _InstCustom);      // Godot's INSTANCE_CUSTOM
        float a = custom.x + _FB_Time * spin;
        float3 positionWS;
        if (lie_flat > 0.5)
        {
            // VERTEX = (rot * vec4(VERTEX, 1.0)).xyz, rot's GLSL columns (cos, -sin, 0), (sin, cos, 0), (0, 0, 1)
            float3 V = FB_Mirror(v.positionOS.xyz);
            V = float3(cos(a) * V.x + sin(a) * V.y, -sin(a) * V.x + cos(a) * V.y, V.z);
            positionWS = TransformObjectToWorld(FB_Mirror(V));
            o.normalWS = TransformObjectToWorldNormal(v.normalOS);            // (NORMAL itself isn't turned)
        }
        else
        {
            positionWS = FB_BillboardWorld(v.positionOS.xyz, 3, 1.0, a);
            // MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX): the normal through the same camera-facing basis
            o.normalWS = FB_BillboardWorld(v.normalOS, 3, 1.0, a) - FB_BillboardWorld(float3(0.0, 0.0, 0.0), 3, 1.0, a);
        }
        o.positionWS = positionWS;
        o.positionCS = TransformWorldToHClip(positionWS);
        float2 uv = v.uv;
        if (grid > 1.5)
        {
            float n = grid * grid;
            float f = min(floor(custom.z * n), n - 1.0);
            uv = (uv + float2(FB_Mod(f, grid), floor(f / grid))) / grid;
        }
        o.uv = uv;
        o.color = v.color * UNITY_ACCESS_INSTANCED_PROP(FBPerInstance, _InstColor);
        return o;
    }

    float4 SpriteFrag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
    {
        UNITY_SETUP_INSTANCE_ID(i);
        float l = FB_Raw(FB_SAMPLE(tex, sampler_TrilinearClamp, i.uv)).r;
        float p = 1.0 - pulse + pulse * (0.5 + 0.5 * sin(_FB_Time * 2.6));
        float3 c = lerp(i.color.rgb * tint.rgb, 1.0, smoothstep(0.55, 1.0, l) * core);
        // the colour in ALBEDO, the strength in ALPHA (blend_add adds ALBEDO * ALPHA)
        float3 albedo = FB_ApplyDecals(c * energy, i.positionWS, FB_SideNormal(normalize(i.normalWS), IS_FRONT_VFACE(frontFace, 1.0, -1.0)));
        return float4(albedo, clamp(l * i.color.a * tint.a * p, 0.0, 1.0));
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
            #pragma vertex SpriteVert
            #pragma fragment SpriteFrag
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
    FallBack Off
}
