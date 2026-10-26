// Port of the inline canvas shader herald_intro.gd builds from SHADE_CODE (the tour's dark shade over the screen, on a
// ColorRect, with a soft-edged rounded hole where the tour is looking).
// canvas_item, blend_mix (default) -> Godot's canvas mix blend. COLOR is written outright (the ColorRect's colour and
// modulate don't reach it, as in Godot). shade is source_color: a Vector property (Godot's 2D renderer doesn't
// linearise it).
// Needs the ColorRect's UV 0..1 across it (Godot's UV for an untextured rect) -- see the report.
Shader "Fatebound/gd/inline/herald_intro_shade"
{
    Properties
    {
        [HideInInspector] _MainTex ("Texture", 2D) = "white" {}
        [HideInInspector] _SrgbTex ("Texture is sRGB", Float) = 1
        [HideInInspector] _AlphaTex ("Texture is alpha only", Float) = 0
        size ("size", Vector) = (1, 1, 0, 0)
        hole ("hole", Vector) = (0, 0, 0, 0)
        radius ("radius", Float) = 18
        soft ("soft", Float) = 8
        shade ("shade", Vector) = (0.0, 0.01, 0.04, 0.6)
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

            float2 size;
            float4 hole;            // x, y, w, h in px (w 0: none)
            float radius;
            float soft;
            float4 shade;

            FBCanvasV2F vert(FBCanvasIn v) { return FB_CanvasVert(v); }

            float4 frag(FBCanvasV2F i) : SV_Target
            {
                FB_CanvasClip(i);
                float2 UV = FB_CanvasGodotUV(i.uv0);
                float2 p = UV * size;
                float a = shade.a;
                if (hole.z > 0.5)
                {
                    float2 h = hole.zw * 0.5;
                    float r = min(radius, min(h.x, h.y));
                    float2 q = abs(p - (hole.xy + h)) - (h - r);
                    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
                    a *= smoothstep(-1.0, soft, d);
                }
                return float4(shade.rgb, a);
            }
            ENDCG
        }
    }
}
