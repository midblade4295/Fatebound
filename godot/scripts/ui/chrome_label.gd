extends Label
# Polished-metal text: a vertical chrome ramp (bright top, dark horizon band, pale lower half)
# applied per glyph in a canvas shader. Dark outline/shadow passes keep their own colour.
const SHADER := """
shader_type canvas_item;
uniform float top_y = 0.0;
uniform float height = 60.0;
varying float ly;
void vertex() { ly = VERTEX.y; }
void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float t = clamp((ly - top_y) / max(height, 1.0), 0.0, 1.0);
    vec3 c = mix(vec3(1.0, 1.0, 1.0), vec3(0.70, 0.74, 0.80), smoothstep(0.05, 0.47, t));
    c = mix(c, vec3(0.34, 0.37, 0.42), smoothstep(0.46, 0.53, t));
    c = mix(c, vec3(0.93, 0.95, 0.98), smoothstep(0.53, 0.95, t));
    bool dark = COLOR.r < 0.3 && COLOR.g < 0.3 && COLOR.b < 0.3;
    COLOR = dark ? vec4(COLOR.rgb, COLOR.a * tex.a) : vec4(c, COLOR.a * tex.a);
}
"""
static var _shader: Shader

func _ready() -> void:
    if _shader == null:
        _shader = Shader.new()
        _shader.code = SHADER
    var mat := ShaderMaterial.new()
    mat.shader = _shader
    material = mat
    resized.connect(_fit)
    _fit()

func _fit() -> void:
    var f := get_theme_font("font")
    var fs := get_theme_font_size("font_size")
    if f == null or not (material is ShaderMaterial):
        return
    # Glyph band: from the cap top to the baseline, centred vertically in the label.
    var line_h := f.get_height(fs)
    var top := (size.y - line_h) * 0.5 + f.get_ascent(fs) - fs * 0.72
    (material as ShaderMaterial).set_shader_parameter("top_y", top)
    (material as ShaderMaterial).set_shader_parameter("height", fs * 0.74)
