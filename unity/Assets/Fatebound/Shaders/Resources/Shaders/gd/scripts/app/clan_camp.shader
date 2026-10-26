// Port of res://scripts/app/clan_camp.gdshader (the clan camp's painting, clan_camp.gd): the banners' blue cloth takes
// the crest's field colour and ripples a little; the campfire's light flickers over everything near it. All in the
// painting's px; motion 0 (Reduce Motion): still.
// canvas_item, blend_mix (default) -> Godot's canvas mix blend. The 2D contract (FateboundCanvas.hlsl): Godot UV from
// uv0, TEXTURE = _MainTex through FB_CanvasTex, the clip rectangle; vertex() only copies COLOR into `tint` (i.color
// here). cloth[] is set with SetVectorArray; the int count is a float. Nothing else differs from Godot.
Shader "Fatebound/gd/scripts/app/clan_camp"
{
    Properties
    {
        [HideInInspector] _MainTex ("Texture", 2D) = "white" {}
        [HideInInspector] _SrgbTex ("Texture is sRGB", Float) = 1
        [HideInInspector] _AlphaTex ("Texture is alpha only", Float) = 0
        paint_size ("paint_size", Vector) = (1024, 2048, 0, 0)
        motion ("motion", Float) = 1
        clock ("clock", Float) = 0
        fire ("fire", Vector) = (500, 560, 300, 0)
        fire_flick ("fire_flick", Float) = 0
        cloth_n ("cloth_n", Float) = 0
        field_col ("field_col", Vector) = (0.17, 0.35, 0.76, 0)
        recolor ("recolor", Float) = 1
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

            float2 paint_size;
            float motion;
            float clock;
            float3 fire;            // x, y, reach
            float fire_flick;       // -1..1
            float4 cloth[5];        // the banners: x0, y0, x1, y1 (the cloth, its tails below y1)
            float cloth_n;
            float3 field_col;
            float recolor;

            FBCanvasV2F vert(FBCanvasIn v) { return FB_CanvasVert(v); }

            float4 frag(FBCanvasV2F i) : SV_Target
            {
                FB_CanvasClip(i);
                float2 UV = FB_CanvasGodotUV(i.uv0);
                float4 tint = i.color;
                float2 p = UV * paint_size;
                float2 q = p;
                float on_cloth = 0.0;
                int clothN = (int)cloth_n;
                for (int k = 0; k < 5; k++)
                {
                    if (k >= clothN)
                    {
                        break;
                    }
                    float4 r = cloth[k];
                    float tail = (r.w - r.y) * 0.3;
                    if (p.x > r.x - 6.0 && p.x < r.z + 6.0 && p.y > r.y - 4.0 && p.y < r.w + tail)
                    {
                        on_cloth = 1.0;
                        float2 f = (p - r.xy) / (r.zw - r.xy);
                        float hold = smoothstep(0.0, 0.3, f.y);
                        float w = sin(clock * 1.7 + p.y * 0.05 + float(k) * 2.3) + 0.4 * sin(clock * 2.9 + p.y * 0.09 + float(k));
                        q.x += motion * 1.6 * hold * clamp(f.y, 0.0, 1.3) * w;
                    }
                }
                float4 c = FB_CanvasTex(FB_CanvasUnityUV(q / paint_size));
                if (on_cloth > 0.5)
                {
                    // the painted cloth's deep blue becomes the field's colour at the same light
                    float blue = smoothstep(0.04, 0.12, c.b - max(c.r, c.g)) * smoothstep(1.9, 2.4, c.b / max(0.01, max(c.r, c.g)));
                    float lum = dot(c.rgb, float3(0.3, 0.59, 0.11));
                    float3 rec = field_col * clamp(lum / 0.17, 0.0, 2.2) * 0.92;
                    c.rgb = lerp(c.rgb, rec, blue * recolor);
                }
                float warm = clamp((c.r - c.b) * 1.6 + 0.3, 0.0, 1.0);
                float d = length(p - fire.xy) / fire.z;
                float light = 0.16 * fire_flick * exp(-d * d * 1.6);
                c.rgb *= 1.0 + motion * light * warm;
                return c * tint;
            }
            ENDCG
        }
    }
}
