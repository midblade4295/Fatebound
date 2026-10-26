// Fatebound (Unity port): what every 2D (canvas) shader shares. The GUI draws into a raw (non-sRGB) render texture
// in Godot's own 2D colour space: colours, textures and blending are sRGB-encoded values exactly as in Godot's 2D
// renderer (no linear conversion), and the composite pass (Fatebound/GUIComposite) puts that image on the screen.
//  * Vertex input (GuiCanvas meshes): POSITION in canvas pixels, y up; COLOR = Godot's vertex colour * modulate
//    (sRGB values); TEXCOORD0 = (u, v, mode, aux) with v already flipped for Unity's bottom-up textures (Godot's
//    UV = (u, 1 - v)); TEXCOORD1 = the clip rectangle in canvas pixels (x0, y0, x1, y1, y up).
//  * Unity decodes sRGB textures (and the 3D viewports' sRGB textures) to linear when sampling: FB_CANVAS_TEX encodes
//    them back, so a shader sees Godot's texel values. _SrgbTex says whether _MainTex is such a texture; a canvas
//    shader's own sampler2D uniforms are images loaded by the game (sRGB): use FB_CANVAS_SRGB on what they return.
//  * TIME is _FB_Time (Godot's TIME: seconds, rolling over every 3600 s).
#ifndef FATEBOUND_CANVAS_INCLUDED
#define FATEBOUND_CANVAS_INCLUDED

#include "UnityCG.cginc"

float _FB_Time;
float4 _FB_CanvasSize;   // the GUI target in pixels: (w, h, 1/w, 1/h) -- Godot's 1 / SCREEN_PIXEL_SIZE
sampler2D _MainTex;
float4 _MainTex_TexelSize;
float _SrgbTex;          // 1: _MainTex is sRGB (decoded by the sampler) -> encode back
float _AlphaTex;         // 1: _MainTex is alpha-only (rgb reads as white, like Godot's L8A8 / R8 masks)

struct FBCanvasIn
{
    float4 vertex : POSITION;
    float4 color : COLOR;
    float4 uv0 : TEXCOORD0;
    float4 uv1 : TEXCOORD1;
};

struct FBCanvasV2F
{
    float4 pos : SV_POSITION;
    float4 color : COLOR;
    float4 uv0 : TEXCOORD0;      // xy: Unity texture coordinate, z: mode, w: aux
    float4 clip : TEXCOORD1;
    float2 canvasPos : TEXCOORD2;
};

float3 FB_LinearToSrgb(float3 c)
{
    c = max(c, 0.0);
    return lerp(1.055 * pow(c, 1.0 / 2.4) - 0.055, 12.92 * c, step(c, 0.0031308));
}

float3 FB_SrgbToLinear(float3 c)
{
    return lerp(pow(max((c + 0.055) / 1.055, 0.0), 2.4), c / 12.92, step(c, 0.04045));
}

#define FB_CANVAS_SRGB(t) float4(FB_LinearToSrgb((t).rgb), (t).a)

float4 FB_CanvasTex(float2 unityUV)
{
    float4 t = tex2D(_MainTex, unityUV);
    if (_SrgbTex > 0.5) t.rgb = FB_LinearToSrgb(t.rgb);
    if (_AlphaTex > 0.5) t.rgb = 1.0;
    return t;
}

// Godot UV (v down) <-> the Unity texture coordinate
float2 FB_CanvasGodotUV(float4 uv0) { return float2(uv0.x, 1.0 - uv0.y); }
float2 FB_CanvasUnityUV(float2 godotUV) { return float2(godotUV.x, 1.0 - godotUV.y); }

FBCanvasV2F FB_CanvasVert(FBCanvasIn v)
{
    FBCanvasV2F o;
    o.pos = UnityObjectToClipPos(v.vertex);
    o.canvasPos = v.vertex.xy;
    o.color = v.color;
    o.uv0 = v.uv0;
    o.clip = v.uv1;
    return o;
}

// Godot's FRAGCOORD.xy (window pixels, y down) and SCREEN_UV
float2 FB_CanvasFragCoord(FBCanvasV2F i) { return float2(i.canvasPos.x, _FB_CanvasSize.y - i.canvasPos.y); }
float2 FB_CanvasScreenUV(FBCanvasV2F i) { return FB_CanvasFragCoord(i) * _FB_CanvasSize.zw; }

void FB_CanvasClip(FBCanvasV2F i)
{
    if (i.canvasPos.x < i.clip.x || i.canvasPos.x >= i.clip.z || i.canvasPos.y < i.clip.y || i.canvasPos.y >= i.clip.w) discard;
}

#endif
