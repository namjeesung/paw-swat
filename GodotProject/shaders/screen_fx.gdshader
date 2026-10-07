shader_type canvas_item;
// 战斗全屏特效：子弹时间去饱和 + 色差；低血量红色暗角；受击闪红
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float bullet_time : hint_range(0.0, 1.0) = 0.0;
uniform float low_hp : hint_range(0.0, 1.0) = 0.0;
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
uniform float pulse = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);
	float ca = 0.004 * bullet_time + 0.003 * hurt;
	vec3 col;
	col.r = texture(screen_tex, uv + dir * ca).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * ca).b;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 bt = mix(col, vec3(lum) * vec3(0.85, 0.95, 1.15), 0.72);
	col = mix(col, bt, bullet_time);
	float d = length(dir * vec2(1.6, 1.0));
	float vig = smoothstep(0.45, 1.05, d);
	col = mix(col, vec3(0.05, 0.08, 0.2), vig * 0.65 * bullet_time);
	float red = vig * (low_hp * (0.55 + 0.25 * pulse)) + smoothstep(0.3, 1.0, d) * hurt * 0.7;
	col = mix(col, vec3(0.75, 0.05, 0.08), clamp(red, 0.0, 0.85));
	COLOR = vec4(col, 1.0);
}
