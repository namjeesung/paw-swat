shader_type canvas_item;
// 暂停菜单背景：模糊 + 压暗
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(0.05, 0.08, 0.15, 1.0);

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 2.5 * amount).rgb;
	vec2 px = SCREEN_PIXEL_SIZE * 3.0 * amount;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), 2.5 * amount).rgb;
	c += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0.0), 2.5 * amount).rgb;
	c += textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), 2.5 * amount).rgb;
	c += textureLod(screen_tex, SCREEN_UV - vec2(0.0, px.y), 2.5 * amount).rgb;
	c /= 5.0;
	c = mix(c, tint.rgb, 0.55 * amount);
	COLOR = vec4(c, 1.0);
}
