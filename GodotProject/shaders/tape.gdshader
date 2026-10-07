shader_type canvas_item;
// 警戒线胶带：黄底，上下边缘黑黄斜纹
uniform vec2 size = vec2(3400.0, 150.0);
uniform vec4 yellow : source_color = vec4(1.0, 0.79, 0.16, 1.0);
uniform vec4 black : source_color = vec4(0.08, 0.09, 0.12, 1.0);

void fragment() {
	vec2 p = UV * size;
	float edge = 26.0;
	vec4 c = yellow;
	if (p.y < edge || p.y > size.y - edge) {
		float d = fract((p.x + p.y) / 44.0);
		c = d < 0.5 ? black : yellow;
	}
	// 轻微纸张噪点
	float n = fract(sin(dot(floor(p / 3.0), vec2(12.9898, 78.233))) * 43758.5453);
	c.rgb *= 0.94 + 0.06 * n;
	COLOR = c;
}
