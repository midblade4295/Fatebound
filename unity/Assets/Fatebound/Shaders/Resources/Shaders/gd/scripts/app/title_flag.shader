// Port of res://scripts/app/title_flag.gdshader (one of the title's two flags, title_logo.gd, waving): the cloth moved by
// its distance from its pole -- a wave running out to the free edge, a little pull toward the pole on each crest, the
// folds lit and shaded with it. All in the texture's own px; pole is the pole's line as (y, x) points by y.
// canvas_item, blend_mix (default) -> Godot's canvas mix blend. The 2D contract (FateboundCanvas.hlsl): Godot UV from
// uv0, TEXTURE = _MainTex through FB_CanvasTex, the clip rectangle; vertex() only copies COLOR into `tint` (i.color).
// pole[10] is a vec2 array in Godot: a float4 array here (SetVectorArray, each point in .xy). Nothing else differs.
Shader "Fatebound/gd/scripts/app/title_flag"
{
    Properties
    {
        [HideInInspector] _MainTex ("Texture", 2D) = "white" {}
        [HideInInspector] _SrgbTex ("Texture is sRGB", Float) = 1
        [HideInInspector] _AlphaTex ("Texture is alpha only", Float) = 0
        tex_px ("tex_px", Vector) = (160, 370, 0, 0)
        pole_n ("pole_n", Float) = 2
        side ("side", Float) = 1
        amp ("amp", Float) = 6
        wave ("wave", Float) = 95
        speed ("speed", Float) = 1.1
        reach ("reach", Float) = 140
        t ("t", Float) = 0
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

            float2 tex_px;
            float4 pole[10];        // Godot's vec2 pole[10]: (y, x) in .xy
            float pole_n;
            float side;             // 1: the cloth lies to the left of its pole; -1: to the right
            float amp;              // px of swing at the cloth's far edge (0: still)
            float wave;             // px from crest to crest
            float speed;            // waves a second
            float reach;            // px from the pole to the full swing
            float t;                // the clock (title_logo.gd runs it)

            float flag_pole_x(float y)
            {
                float x = pole[0].y;
                int n = (int)pole_n;
                for (int k = 0; k < 9; k++)
                {
                    if (k + 1 < n && y >= pole[k].x)
                    {
                        float f = clamp((y - pole[k].x) / max(pole[k + 1].x - pole[k].x, 0.001), 0.0, 1.0);
                        x = lerp(pole[k].y, pole[k + 1].y, f);
                    }
                }
                return x;
            }

            FBCanvasV2F vert(FBCanvasIn v) { return FB_CanvasVert(v); }

            float4 frag(FBCanvasV2F i) : SV_Target
            {
                FB_CanvasClip(i);
                float2 UV = FB_CanvasGodotUV(i.uv0);
                float4 tint = i.color;
                float2 p = UV * tex_px;
                float d = (flag_pole_x(p.y) - p.x) * side;
                float w = smoothstep(6.0, 40.0, d) * (0.3 + 0.7 * clamp(d / reach, 0.0, 1.0));
                float ph = 6.2831853 * (d / wave - speed * t);
                float gust = 0.8 + 0.2 * sin(t * 0.9);
                float a = amp * gust * w;
                float2 disp = float2(side * a * 0.3 * (1.0 - cos(ph)), a * sin(ph));
                float4 c = FB_CanvasTex(FB_CanvasUnityUV((p - disp) / tex_px));
                c.rgb *= 1.0 + 0.03 * a * cos(ph);
                return c * tint;
            }
            ENDCG
        }
    }
}
