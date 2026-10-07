class_name Toon
## 卡通渲染材质：色块着色 + 外描边（next_pass 外扩背面）。

static var _cache := {}


static func mat(color: Color, outline: bool = true, outline_color: Color = Pal.OUTLINE_PROP,
		width: float = 0.022, rim: float = 0.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.75
	m.metallic_specular = 0.3
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.6
	# 预先打开自发光（黑色），受击闪白时只改颜色即可
	m.emission_enabled = true
	m.emission = Color.BLACK
	if outline:
		m.next_pass = outline_mat(outline_color, width)
	return m


## 共享的无描边道具材质（墙、地面等大量使用时复用）
static func prop(color: Color) -> StandardMaterial3D:
	var key := "p" + color.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.roughness = 0.9
		_cache[key] = m
	return _cache[key]


## 共享的带描边道具材质
static func prop_outlined(color: Color, outline_color: Color = Pal.OUTLINE_PROP, width := 0.02) -> StandardMaterial3D:
	var key := "po" + color.to_html() + outline_color.to_html() + str(width)
	if not _cache.has(key):
		_cache[key] = mat(color, true, outline_color, width, 0.15)
	return _cache[key]


static func outline_mat(color: Color, width: float) -> StandardMaterial3D:
	var o := StandardMaterial3D.new()
	o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	o.cull_mode = BaseMaterial3D.CULL_FRONT
	o.grow = true
	o.grow_amount = width
	o.albedo_color = color
	return o


## 发光材质（霓虹、子弹、灯）
static func glow(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "g" + color.to_html() + str(energy)
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_cache[key] = m
	return _cache[key]


static func glass(color: Color = Color(0.6, 0.85, 1.0, 0.22)) -> StandardMaterial3D:
	var key := "glass" + color.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.1
		m.metallic_specular = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache[key] = m
	return _cache[key]
