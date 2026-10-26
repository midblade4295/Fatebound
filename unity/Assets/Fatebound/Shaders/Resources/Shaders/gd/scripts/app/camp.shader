// Port of res://scripts/app/camp.gdshader (Home's camp painting, camp_scene.gd): the campfire's light flickering over
// everything near it, the lanterns and torches each a little; the two big banners rippling (still where they're held);
// the towers' pennants fluttering. All in the painting's px; motion 0 (Reduce Motion): still.
// canvas_item, blend_mix (default) -> Godot's canvas mix blend. The 2D contract (FateboundCanvas.hlsl): Godot UV from
// uv0, TEXTURE = _MainTex through FB_CanvasTex (Godot's texel values), the clip rectangle. vertex() only copies COLOR
// (the vertex colour * modulate) into `tint`: that is i.color here. Uniform arrays (lamps, cloth, pennants) are set with
// SetVectorArray; the int counts are floats. Nothing else differs from Godot.
Shader "Fatebound/gd/scripts/app/camp"
{
    Properties
    {
        [HideInInspector] _MainTex ("Texture", 2D) = "white" {}
        [HideInInspector] _SrgbTex ("Texture is sRGB", Float) = 1
        [HideInInspector] _AlphaTex ("Texture is alpha only", Float) = 0
        paint_size ("paint_size", Vector) = (1024, 2048, 0, 0)
        motion ("motion", Float) = 1
        clock ("clock", Float) = 0
        fire ("fire", Vector) = (497, 880, 360, 0)
        fire_flick ("fire_flick", Float) = 0
        lamp_n ("lamp_n", Float) = 0
        cloth_n ("cloth_n", Float) = 0
        pennant_n ("pennant_n", Float) = 0
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
            float4 lamps[6];        // x, y, reach, phase
            float lamp_n;
            float4 cloth[2];        // the banners: x0, y0, x1, y1 (held along the top)
            float cloth_n;
            float4 pennants[6];     // x0 (the pole), y0, x1, y1
            float pennant_n;

            FBCanvasV2F vert(FBCanvasIn v) { return FB_CanvasVert(v); }

            float4 frag(FBCanvasV2F i) : SV_Target
            {
                FB_CanvasClip(i);
                float2 UV = FB_CanvasGodotUV(i.uv0);
                float4 tint = i.color;
                float2 p = UV * paint_size;
                float2 q = p;
                int clothN = (int)cloth_n;
                int pennantN = (int)pennant_n;
                int lampN = (int)lamp_n;
                for (int k = 0; k < 2; k++)
                {
                    if (k >= clothN)
                    {
                        break;
                    }
                    float4 r = cloth[k];
                    if (p.x > r.x && p.x < r.z && p.y > r.y && p.y < r.w)
                    {
                        float2 f = (p - r.xy) / (r.zw - r.xy);
                        float hold = smoothstep(0.0, 0.18, f.x) * smoothstep(0.0, 0.18, 1.0 - f.x) * smoothstep(0.0, 0.25, f.y)
                            * smoothstep(0.0, 0.06, 1.0 - f.y);
                        float w = sin(clock * 1.5 + p.y * 0.028 + float(k) * 2.1) + 0.45 * sin(clock * 2.7 + p.y * 0.05 + float(k));
                        q.x += motion * 2.6 * hold * f.y * w;
                        q.y += motion * 1.2 * hold * f.y * sin(clock * 1.9 + p.x * 0.06 + float(k));
                    }
                }
                for (int j = 0; j < 6; j++)
                {
                    if (j >= pennantN)
                    {
                        break;
                    }
                    float4 r = pennants[j];
                    if (p.x > r.x && p.x < r.z && p.y > r.y && p.y < r.w)
                    {
                        float u = (p.x - r.x) / (r.z - r.x);
                        float vv = (p.y - r.y) / (r.w - r.y);
                        float edge = smoothstep(0.0, 0.2, vv) * smoothstep(0.0, 0.2, 1.0 - vv);
                        q.y += motion * 2.2 * u * edge * sin(clock * 7.0 - p.x * 0.3 + float(j) * 1.3);
                    }
                }
                float4 c = FB_CanvasTex(FB_CanvasUnityUV(q / paint_size));
                float warm = clamp((c.r - c.b) * 1.6 + 0.3, 0.0, 1.0);
                float d = length(p - fire.xy) / fire.z;
                float light = 0.17 * fire_flick * exp(-d * d * 1.6);
                for (int m = 0; m < 6; m++)
                {
                    if (m >= lampN)
                    {
                        break;
                    }
                    float4 l = lamps[m];
                    float dl = length(p - l.xy) / l.z;
                    float fl = sin(clock * 9.3 + l.w) * 0.6 + sin(clock * 15.1 + l.w * 1.7) * 0.4;
                    light += 0.12 * fl * exp(-dl * dl * 2.0);
                }
                c.rgb *= 1.0 + motion * light * warm;
                return c * tint;
            }
            ENDCG
        }
    }
}
