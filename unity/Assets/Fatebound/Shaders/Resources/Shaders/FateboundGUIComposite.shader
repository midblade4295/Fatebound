// Fatebound: puts the GUI's image (a raw texture holding Godot's sRGB values) on the screen. The screen is an sRGB
// target in a linear project, so the values are decoded here and the hardware encodes them back unchanged.
Shader "Hidden/Fatebound/GUIComposite"
{
    Properties
    {
        _MainTex ("GUI", 2D) = "black" {}
    }
    SubShader
    {
        Tags { "Queue"="Overlay" "RenderType"="Opaque" }
        Cull Off ZWrite Off ZTest Always Blend Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            sampler2D _MainTex;
            struct a2v { float4 vertex : POSITION; float2 uv : TEXCOORD0; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
            v2f vert(a2v v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.uv = v.uv; return o; }
            float4 frag(v2f i) : SV_Target
            {
                float4 c = tex2D(_MainTex, i.uv);
                #ifndef UNITY_COLORSPACE_GAMMA
                c.rgb = lerp(pow(max((c.rgb + 0.055) / 1.055, 0.0), 2.4), c.rgb / 12.92, step(c.rgb, 0.04045));
                #endif
                c.a = 1.0;
                return c;
            }
            ENDCG
        }
    }
}
