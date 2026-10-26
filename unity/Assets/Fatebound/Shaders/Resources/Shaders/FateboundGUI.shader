// Fatebound GUI: everything the GUI framework draws (Fatebound.GUI's render batches, built into meshes by GuiCanvas),
// in Godot's 2D colour space (FateboundCanvas.hlsl): sRGB values, blended as Godot blends them.
// uv0.z = mode (0 plain, 1 SDF text), uv0.w = SDF outline shift. SDF text: alpha = smoothstep around 0.5 - outline,
// one screen pixel wide.
Shader "Fatebound/GUI"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src", Float) = 5
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst", Float) = 10
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOp ("Op", Float) = 0
        _SrgbTex ("Texture is sRGB", Float) = 1
        _AlphaTex ("Texture is alpha only", Float) = 0
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "IgnoreProjector"="True" "RenderType"="Transparent" }
        Cull Off
        Lighting Off
        ZWrite Off
        ZTest Always
        // Godot's canvas blending: colour by the blend mode, alpha always one / one-minus-source-alpha
        Blend [_SrcBlend] [_DstBlend], One OneMinusSrcAlpha
        BlendOp [_BlendOp], Add

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "FateboundCanvas.hlsl"

            FBCanvasV2F vert(FBCanvasIn v) { return FB_CanvasVert(v); }

            float4 frag(FBCanvasV2F i) : SV_Target
            {
                FB_CanvasClip(i);
                float4 c = i.color;
                if (i.uv0.z > 0.5)
                {
                    float d = tex2D(_MainTex, i.uv0.xy).a;
                    float w = max(fwidth(d) * 0.75, 1e-4);
                    float edge = 0.5 - i.uv0.w;
                    c.a *= smoothstep(edge - w, edge + w, d);
                }
                else
                {
                    c *= FB_CanvasTex(i.uv0.xy);
                }
                return c;
            }
            ENDCG
        }
    }
}
