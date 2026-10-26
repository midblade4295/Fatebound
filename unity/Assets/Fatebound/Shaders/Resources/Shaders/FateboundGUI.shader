// Fatebound GUI: everything the GUI framework draws (Fatebound.GUI's render batches, built into meshes by GuiCanvas).
// uv0.xy = texture coordinate, uv0.z = mode (0 plain, 1 SDF text), uv0.w = SDF outline shift; uv1 = clip rectangle in
// canvas pixels (x0, y0, x1, y1). Colours are Godot's (sRGB); in a linear project they are linearised here and the
// textures by the sampler. SDF text: alpha = smoothstep around 0.5 - outline, one screen pixel wide.
Shader "Fatebound/GUI"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src", Float) = 5
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst", Float) = 10
        _SdfAlpha ("Texture is SDF alpha", Float) = 0
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "IgnoreProjector"="True" "RenderType"="Transparent" "PreviewType"="Plane" }
        Cull Off
        Lighting Off
        ZWrite Off
        ZTest [unity_GUIZTestMode]
        Blend [_SrcBlend] [_DstBlend], One OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float4 color : COLOR;
                float4 uv0 : TEXCOORD0;
                float4 uv1 : TEXCOORD1;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 color : COLOR;
                float4 uv0 : TEXCOORD0;
                float4 clip : TEXCOORD1;
                float2 canvasPos : TEXCOORD2;
            };

            sampler2D _MainTex;
            float4 _MainTex_TexelSize;

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.canvasPos = v.vertex.xy;
                o.color = v.color;
                #ifndef UNITY_COLORSPACE_GAMMA
                o.color.rgb = GammaToLinearSpace(saturate(v.color.rgb));
                #endif
                o.uv0 = v.uv0;
                o.clip = v.uv1;
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                if (i.canvasPos.x < i.clip.x || i.canvasPos.x >= i.clip.z || i.canvasPos.y < i.clip.y || i.canvasPos.y >= i.clip.w) discard;
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
                    c *= tex2D(_MainTex, i.uv0.xy);
                }
                return c;
            }
            ENDCG
        }
    }
}
