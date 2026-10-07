shader_type canvas_item;
// 投影幕布：扫描线 + 轻微闪烁
uniform vec4 tint : source_color = vec4(0.35, 0.65, 1.0, 0.07);
uniform float flicker = 0.0;

void fragment() {
	float line = 0.5 + 0.5 * sin(UV.y * 900.0 + TIME * 6.0);
	float band = smoothstep(0.0, 0.02, fract(UV.y * 1.5 - TIME * 0.15)) ;
	vec4 c = tint;
	c.a *= (0.5 + 0.5 * line) * (0.8 + 0.2 * band) * (1.0 - flicker * 0.5);
	COLOR = c;
}
