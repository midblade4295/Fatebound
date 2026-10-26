// Port of res://scripts/app/title_rays.gdshader (the light bursting out from behind the title, title_screen.gd): soft
// rays turning slowly round the middle, fading out to the edge; power 0 draws nothing.
// canvas_item, render_mode blend_add -> Godot's canvas add blend (colour SrcAlpha/One, alpha SrcAlpha/One). COLOR is
// replaced outright (no vertex colour, no texture), as in Godot. Nothing differs from Godot.
Shader "Fatebound/gd/scripts/app/title_rays"
{
    Properties
    {
        [HideInInspector] _MainTex ("Texture", 2D) = "white" {}
        [HideInInspector] _SrgbTex ("Texture is sRGB", Float) = 1
        [HideInInspector] _AlphaTex ("Texture is alpha only", Float) = 0
        spin ("spin", Float) = 0
        power ("power", Float) = 0
        tint ("tint", Vector) = (1.0, 0.76, 0.38, 0)
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "IgnoreProjector" = "True" "RenderType" = "Transparent" }
        Cull Off
        Lighting Off
        ZWrite Off
        ZTest Always
        Blend SrcAlpha One, SrcAlpha One

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "../../../FateboundCanvas.hlsl"

            float spin;
            float power;
            float3 tint;

            FBCanvasV2F vert(FBCanvasIn v) { return FB_CanvasVert(v); }

            float4 frag(FBCanvasV2F i) : SV_Target
            {
                FB_CanvasClip(i);
                float2 UV = FB_CanvasGodotUV(i.uv0);
                float2 p = UV - 0.5;
                float r = length(p) * 2.0;
                float a = atan2(p.y, p.x);
                float rays = pow(0.5 + 0.5 * sin(a * 9.0 + spin), 4.0) * 0.75 + pow(0.5 + 0.5 * sin(a * 5.0 - spin * 1.6 + 1.3), 6.0) * 0.6;
                float fall = smoothstep(1.0, 0.25, r) * smoothstep(0.0, 0.18, r);
                return float4(tint * rays * fall * power, 1.0);
            }
            ENDCG
        }
    }
}
