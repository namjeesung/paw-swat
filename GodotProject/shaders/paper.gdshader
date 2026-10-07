shader_type canvas_item;
// 报纸：纸纹 + 边缘泛黄
uniform vec4 base : source_color = vec4(0.953, 0.922, 0.851, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	float g = hash(floor(UV * vec2(600.0, 800.0)));
	vec3 c = base.rgb * (0.965 + 0.035 * g);
	float edge = smoothstep(0.0, 0.08, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
	c *= mix(vec3(0.86, 0.78, 0.62), vec3(1.0), edge);
	COLOR = vec4(c, 1.0) * COLOR;
}
