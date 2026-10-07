shader_type canvas_item;
// 软木板：颗粒噪点 + 台灯暖光 + 暗角
uniform vec4 base : source_color = vec4(0.73, 0.55, 0.37, 1.0);
uniform vec2 light_pos = vec2(0.3, 0.2);
uniform float aspect = 1.777;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV * vec2(aspect, 1.0);
	float grain = hash(floor(uv * 420.0));
	float blot = noise(uv * 18.0) * 0.6 + noise(uv * 55.0) * 0.4;
	vec3 c = base.rgb * (0.82 + 0.25 * blot);
	if (grain > 0.93) c *= 0.7;
	if (grain < 0.04) c *= 1.18;
	float l = 1.0 - smoothstep(0.0, 1.25, distance(UV * vec2(aspect, 1.0), light_pos * vec2(aspect, 1.0)));
	c *= 0.62 + 0.55 * l;
	c += vec3(0.08, 0.05, 0.0) * l;
	float vig = smoothstep(0.95, 0.35, distance(UV, vec2(0.5)));
	c *= 0.55 + 0.45 * vig;
	COLOR = vec4(c, 1.0);
}
