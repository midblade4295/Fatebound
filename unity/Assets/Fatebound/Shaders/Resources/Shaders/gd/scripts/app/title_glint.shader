// Port of res://scripts/app/title_glint.gdshader (a gold glint sweeping across the title's lettering, title_screen.gd on
// title_logo.gd's base layer): `sweep` is the bright band's place along the diagonal.
// canvas_item, blend_mix (default) -> Godot's canvas mix blend. COLOR starts as Godot's does: vertex colour * modulate *
// TEXTURE at UV (FB_CanvasTex). Nothing differs from Godot.
Shader "Fatebound/gd/scripts/app/title_glint"
{
    Properties
    {
        [HideInInspector] _MainTex ("Texture", 2D) = "white" {}
        [HideInInspector] _SrgbTex ("Texture is sRGB", Float) = 1
        [HideInInspector] _AlphaTex ("Texture is alpha only", Float) = 0
        sweep ("sweep", Float) = -1
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
            #include "../../../FateboundCanvas.hlsl"

            float sweep;

            FBCanvasV2F vert(FBCanvasIn v) { return FB_CanvasVert(v); }

            float4 frag(FBCanvasV2F i) : SV_Target
            {
                FB_CanvasClip(i);
                float2 UV = FB_CanvasGodotUV(i.uv0);
                float4 COL = i.color * FB_CanvasTex(i.uv0.xy);       // Godot's COLOR on entry
                float d = (UV.x + UV.y * 0.5) / 1.5;
                float band = smoothstep(0.075, 0.0, abs(d - sweep));
                COL.rgb += float3(1.0, 0.95, 0.78) * band * 0.8 * COL.a;
                return COL;
            }
            ENDCG
        }
    }
}
