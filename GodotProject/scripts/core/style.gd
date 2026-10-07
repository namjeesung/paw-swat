class_name Style
## 字体与 UI 样式工厂。所有界面都从这里取字体/面板，保证风格统一。

static var _fonts := {}


static func _font(path: String) -> Font:
	if not _fonts.has(path):
		var f: FontFile = load(path)
		# 标题/数字字体缺字时回落到思源黑体
		if not path.ends_with("NotoSansSC-Medium.ttf") and not path.ends_with("NotoSansSC-Black.ttf"):
			var fb: Font = load("res://assets/fonts/NotoSansSC-Black.ttf")
			f.fallbacks = [fb]
		_fonts[path] = f
	return _fonts[path]


## 标题字体：站酷快乐体（圆润可爱）
static func title_font() -> Font:
	return _font("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")


## 正文字体
static func body_font() -> Font:
	return _font("res://assets/fonts/NotoSansSC-Medium.ttf")


## 粗体正文
static func bold_font() -> Font:
	return _font("res://assets/fonts/NotoSansSC-Black.ttf")


## 数字 / 英文招牌字体
static func num_font() -> Font:
	return _font("res://assets/fonts/Bungee-Regular.ttf")


static func label(text: String, size: int, color: Color = Pal.CREAM, font: Font = null,
		outline: int = 0, outline_color: Color = Pal.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func box(bg: Color, radius: int = 14, border: int = 0, border_color: Color = Pal.INK,
		shadow: int = 0, shadow_offset := Vector2(0, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	if shadow > 0:
		s.shadow_size = shadow
		s.shadow_offset = shadow_offset
		s.shadow_color = Color(0, 0, 0, 0.35)
	s.anti_aliasing = true
	return s


static func panel(bg: Color, radius: int = 14, border: int = 0, border_color: Color = Pal.INK,
		shadow: int = 0) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", box(bg, radius, border, border_color, shadow))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## 键帽小标签，如 [E]
static func keycap(key: String, size: int = 22) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := box(Pal.CREAM, 6, 2, Pal.INK, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 0
	sb.content_margin_bottom = 2
	sb.border_width_bottom = 5
	pc.add_theme_stylebox_override("panel", sb)
	pc.add_child(label(key, size, Pal.INK, num_font()))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pc


static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
	return c


static func shader_rect(shader_path: String, params := {}) -> ColorRect:
	var r := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	for k in params:
		m.set_shader_parameter(k, params[k])
	r.material = m
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full_rect(r)
	return r


## 椭圆多边形点
static func ellipse_points(c: Vector2, rx: float, ry: float, seg: int = 28, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in seg:
		var a := TAU * i / seg
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts


static func star_points(c: Vector2, r_out: float, r_in: float, points: int = 5, rot := -PI / 2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var r := r_out if i % 2 == 0 else r_in
		var a := rot + PI * i / points
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Prepare the exact font cache/atlas before transition text is revealed.
## Each job is one character fill or outline at one subpixel position.
## Use the same Font shaping/drawing path as Labels, including fallbacks,
## viewport oversampling, and atlas upload, on an unattached scratch canvas.
## The 2 ms budget is soft: one font call is indivisible. No gameplay pause.
static func prewarm_text(owner: Node, specs: Array) -> void:
	var jobs: Array = []
	var seen := {}
	for spec in specs:
		var font: Font = spec[0]
		var size: int = spec[2]
		var sampling: float = spec[4] if spec.size() > 4 else owner.get_viewport().get_oversampling()
		for character in String(spec[1]):
			for outline in [0, int(spec[3])]:
				for offset in [0.0, 0.25, 0.5, 0.75]:
					var key := "%d:%s:%d:%d:%s:%s" % [font.get_instance_id(), character, size, outline, sampling, offset]
					if not seen.has(key):
						seen[key] = true
						jobs.append([font, character, size, outline, sampling, Vector2(offset, 0)])
	var canvas := RenderingServer.canvas_item_create()
	var index := 0
	while index < jobs.size() and is_instance_valid(owner) and owner.is_inside_tree():
		await owner.get_tree().process_frame
		if not is_instance_valid(owner) or not owner.is_inside_tree():
			break
		var start := Time.get_ticks_usec()
		var count := 0
		while index < jobs.size() and count < 8:
			var job: Array = jobs[index]
			var font: Font = job[0]
			if int(job[3]) == 0:
				font.draw_string(canvas, job[5], job[1], HORIZONTAL_ALIGNMENT_LEFT, -1, job[2], Color(1, 1, 1, 0), 3, TextServer.DIRECTION_AUTO, TextServer.ORIENTATION_HORIZONTAL, job[4])
			else:
				font.draw_string_outline(canvas, job[5], job[1], HORIZONTAL_ALIGNMENT_LEFT, -1, job[2], job[3], Color(1, 1, 1, 0), 3, TextServer.DIRECTION_AUTO, TextServer.ORIENTATION_HORIZONTAL, job[4])
			index += 1
			count += 1
			if Time.get_ticks_usec() - start >= 2000:
				break
		RenderingServer.canvas_item_clear(canvas)
	RenderingServer.free_rid(canvas)
