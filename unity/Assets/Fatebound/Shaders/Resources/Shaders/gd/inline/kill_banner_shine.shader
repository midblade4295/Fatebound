// Port of the inline canvas shader kill_banner.gd builds from SHINE_CODE (a light sweeping across a kill banner's painted
// title, on its TextureRect).
// canvas_item, blend_mix (default) -> Godot's canvas mix blend.
// As Godot, including its double texture: fragment()'s COLOR already holds vertex colour * TEXTURE at UV, and the code
// multiplies it by texture(TEXTURE, UV) again (c = texture * COLOR) -- kept, it is what Godot draws.
Shader "Fatebound/gd/inline/kill_banner_shine"
{
    Properties
    {
        [HideInInspector] _MainTex ("Texture", 2D) = "white" {}
        [HideInInspector] _SrgbTex ("Texture is sRGB", Float) = 1
        [HideInInspector] _AlphaTex ("Texture is alpha only", Float) = 0
        sweep ("sweep", Float) = -1
        width ("width", Float) = 0.11
        strength ("strength", Float) = 0.75
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "IgnoreProjector" = "True" "RenderType" = "Transparent" }
        Cull Off
        Lighting Off
        ZWrite Off
        ZTest Always
        Blend SrcAlpha OneMinusSrcAlpha, One OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "../../FateboundCanvas.hlsl"

            float sweep;
            float width;
            float strength;

            FBCanvasV2F vert(FBCanvasIn v) { return FB_CanvasVert(v); }

            float4 frag(FBCanvasV2F i) : SV_Target
            {
                FB_CanvasClip(i);
                float2 UV = FB_CanvasGodotUV(i.uv0);
                float4 tex = FB_CanvasTex(i.uv0.xy);
                float4 COL = i.color * tex;                     // Godot's COLOR on entry
                float4 c = tex * COL;
                float d = (UV.x + UV.y * 0.4) / 1.4 - sweep;
                float b = smoothstep(width, 0.0, abs(d)) * strength;
                c.rgb += float3(1.0, 0.95, 0.82) * b * c.a;
                return c;
            }
            ENDCG
        }
    }
}
