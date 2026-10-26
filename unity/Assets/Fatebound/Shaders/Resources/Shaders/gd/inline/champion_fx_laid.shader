// Port of the inline canvas shader champion_fx.gd builds from LAID_SHADER (a champion window's laid-over effect sprites --
// smoke, leaves, feathers, shards, snow: brightness-only sprites drawn over the painting in their tint instead of added).
// (Not in the brief's list; the game uses it: champion_window.gd -> champion_fx.gd setup(..., add = false).)
// canvas_item, blend_mix (default) -> Godot's canvas mix blend. vertex() only copies COLOR (vertex colour * modulate)
// into `tint` (i.color); TEXTURE through FB_CanvasTex. Nothing differs from Godot.
Shader "Fatebound/gd/inline/champion_fx_laid"
{
    Properties
    {
        [HideInInspector] _MainTex ("Texture", 2D) = "white" {}
        [HideInInspector] _SrgbTex ("Texture is sRGB", Float) = 1
        [HideInInspector] _AlphaTex ("Texture is alpha only", Float) = 0
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

            FBCanvasV2F vert(FBCanvasIn v) { return FB_CanvasVert(v); }

            float4 frag(FBCanvasV2F i) : SV_Target
            {
                FB_CanvasClip(i);
                float4 tint = i.color;
                float l = FB_CanvasTex(i.uv0.xy).r;
                return float4(tint.rgb * (0.55 + 0.6 * l), tint.a * smoothstep(0.03, 0.45, l));
            }
            ENDCG
        }
    }
}
