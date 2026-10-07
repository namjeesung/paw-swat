class_name HudWidgets
## 战斗 HUD 的各个自绘控件。全部用 _draw 绘制，便于做动画和统一风格。


## 实时（不受子弹时间/顿帧影响）的帧间隔
static func real_delta(delta: float) -> float:
	return minf(delta / maxf(Engine.time_scale, 0.01), 0.05)


static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 0, outline_col := Pal.INK) -> void:
	if outline > 0:
		ci.draw_string_outline(font, pos, s, align, width, size, outline, outline_col)
	ci.draw_string(font, pos, s, align, width, size, col)


static func keycap(ci: CanvasItem, center: Vector2, key: String, size := 20) -> void:
	var f := Style.num_font() if key.length() <= 2 else Style.bold_font()
	var w := f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16
	var r := Rect2(center - Vector2(w * 0.5, size * 0.75), Vector2(w, size * 1.5))
	var sb := Style.box(Pal.CREAM, 6, 2, Pal.INK)
	sb.border_width_bottom = 5
	ci.draw_style_box(sb, r)
	ci.draw_string(f, Vector2(r.position.x, center.y + size * 0.36 - 2), key, HORIZONTAL_ALIGNMENT_CENTER, w, size, Pal.INK)


# ======================================================================= 狗牌血条
class DogTag extends Control:
	var hp := 100.0
	var max_hp := 100.0
	var ghost := 100.0
	var in_cover := false
	var buff := false
	var _shake := 0.0
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func hit() -> void:
		_shake = 1.0

	var _sig := ""

	func _process(delta: float) -> void:
		var rd := HudWidgets.real_delta(delta)
		_t += rd
		if ghost > hp:
			ghost = move_toward(ghost, hp, rd * 45.0)
		else:
			ghost = hp
		_shake = maxf(0.0, _shake - rd * 3.0)
		# 轻轻摇晃用控件自身的旋转（不用重画）；内容只在数值变化 / 抖动 / 残血闪烁时重画。
		# 原来每帧重画整块狗牌（头像 + 10 段血条 + 文字），是 HUD 里最贵的一项。
		pivot_offset = Vector2(30, 70)
		rotation = -0.035 + sin(_t * 1.4) * 0.006
		var sig := "%d|%d|%d|%s|%s" % [ceili(hp), int(ghost), int(max_hp), in_cover, buff]
		if sig != _sig or _shake > 0.0 or hp / max_hp <= 0.3:
			_sig = sig
			queue_redraw()

	func _draw() -> void:
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 9.0
		draw_set_transform(off, _shake * 0.05, Vector2.ONE)
		# 珠链
		for i in 10:
			var p := Vector2(28, 70) + Vector2(-10 - i * 6.5, -12 - i * 9.0)
			draw_circle(p, 4.2, Pal.INK)
			draw_circle(p, 2.6, Pal.STEEL)
		var r := Rect2(Vector2(0, 0), Vector2(450, 166))
		draw_style_box(Style.box(Color(0, 0, 0, 0.35), 38), Rect2(r.position + Vector2(6, 9), r.size))
		draw_style_box(Style.box(Pal.STEEL, 38, 5, Pal.INK), r)
		draw_style_box(Style.box(Color(1, 1, 1, 0.35), 20), Rect2(Vector2(60, 12), Vector2(370, 14)))
		draw_circle(Vector2(30, 70), 12, Pal.INK)
		draw_circle(Vector2(30, 70), 7.5, Color("20263A"))
		# 头像
		var pc := Vector2(116, 84)
		draw_circle(pc, 62, Pal.INK)
		draw_circle(pc, 57, Pal.NAVY if not buff else Pal.ORANGE_DARK)
		Portrait.draw_face(self, pc + Vector2(0, 8), 44, "shiba")
		# 名字
		HudWidgets.text(self, Style.title_font(), Vector2(194, 60), "豆包", 42, Pal.INK)
		HudWidgets.text(self, Style.num_font(), Vector2(288, 54), "PAW-0427", 17, Color(Pal.INK, 0.55))
		# 分段血条
		var x0 := 194.0
		var y0 := 76.0
		var w := 232.0
		var h := 30.0
		var n := 10
		var gap := 4.0
		var sw := (w - gap * (n - 1)) / n
		var ratio := hp / max_hp
		var col := Pal.GREEN if ratio > 0.6 else (Pal.YELLOW if ratio > 0.3 else Pal.RED)
		if ratio <= 0.3:
			col = col.lerp(Color.WHITE, 0.25 + 0.25 * sin(_t * 12.0))
		for i in n:
			var x := x0 + i * (sw + gap)
			var seg := PackedVector2Array([Vector2(x, y0 + h), Vector2(x + 7, y0), Vector2(x + sw + 7, y0), Vector2(x + sw, y0 + h)])
			draw_colored_polygon(seg, Color("2A3350"))
			var gf := clampf(ghost / max_hp * n - i, 0.0, 1.0)
			if gf > 0.0:
				draw_colored_polygon(_part(x, y0, sw, h, gf), Color(1, 1, 1, 0.9))
			var f := clampf(ratio * n - i, 0.0, 1.0)
			if f > 0.0:
				draw_colored_polygon(_part(x, y0, sw, h, f), col)
			draw_polyline(PackedVector2Array([seg[0], seg[1], seg[2], seg[3], seg[0]]), Pal.INK, 2.5)
		HudWidgets.text(self, Style.num_font(), Vector2(194, 146), "%d" % ceili(hp), 34, Pal.INK)
		HudWidgets.text(self, Style.num_font(), Vector2(194 + Style.num_font().get_string_size("%d" % ceili(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x + 6, 146), "/ %d" % int(max_hp), 17, Color(Pal.INK, 0.5))
		if in_cover:
			var sc := Vector2(352, 128)
			var shield := PackedVector2Array([sc + Vector2(-16, -18), sc + Vector2(16, -18), sc + Vector2(16, 0), sc + Vector2(0, 18), sc + Vector2(-16, 0)])
			draw_colored_polygon(shield, Pal.TEAL)
			draw_polyline(PackedVector2Array([shield[0], shield[1], shield[2], shield[3], shield[4], shield[0]]), Pal.INK, 3)
			HudWidgets.text(self, Style.title_font(), sc + Vector2(24, 10), "掩体", 26, Pal.INK)
		elif buff:
			HudWidgets.text(self, Style.title_font(), Vector2(330, 140), "火力强化", 24, Pal.ORANGE_DARK)

	func _part(x: float, y0: float, sw: float, h: float, f: float) -> PackedVector2Array:
		var xe := sw * f
		return PackedVector2Array([Vector2(x, y0 + h), Vector2(x + 7, y0), Vector2(x + xe + 7, y0), Vector2(x + xe, y0 + h)])


# ======================================================================= 弹药面板
class AmmoPanel extends Control:
	var ammo := 30
	var mag := 30
	var reloading := false
	var reload_p := 0.0
	var window := Vector2(0.44, 0.62)
	var buff := false
	var jam := 0.0
	var weapon := "rifle"
	var special := 0
	var owned: Array = ["rifle"]
	var grenades := 0
	var _pop := 0.0
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func shot() -> void:
		_pop = 1.0

	var _sig := ""

	func _process(delta: float) -> void:
		var rd := HudWidgets.real_delta(delta)
		_t += rd
		_pop = maxf(0.0, _pop - rd * 8.0)
		jam = maxf(0.0, jam - rd)
		# 只在内容变化或有动画（弹跳 / 换弹条 / 发光脉冲）时重画
		var sig := "%d|%d|%s|%s|%d|%d|%d" % [ammo, special, weapon, reloading, owned.size(), grenades, mag]
		if sig != _sig or _pop > 0.0 or jam > 0.0 or reloading or buff or weapon != "rifle":
			_sig = sig
			queue_redraw()

	## 面板上方一条：已拥有的武器（当前高亮，Tab 切换）+ 手雷数（G）
	func _draw_strip() -> void:
		var x := 0.0
		var y := -40.0
		var f := Style.title_font()
		if owned.size() > 1:
			for id in owned:
				var w := Weapons.info(id)
				var on: bool = id == weapon
				var txt: String = w.short
				var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 24
				var col: Color = w.color if id != "rifle" else Pal.CREAM
				draw_style_box(Style.box(col if on else Color(Pal.NAVY_DARK, 0.85), 10, 3, Pal.INK if on else Color(col, 0.6)), Rect2(Vector2(x, y - 14), Vector2(tw, 36)))
				HudWidgets.text(self, f, Vector2(x, y + 12), txt, 22, Pal.INK if on else col, HORIZONTAL_ALIGNMENT_CENTER, tw)
				x += tw + 6
			HudWidgets.keycap(self, Vector2(x + 26, y + 4), "Tab", 16)
			x += 64
		if grenades > 0:
			var gx := 410.0 - 120.0
			var gy := y if x < gx - 6.0 else y - 44.0   # 武器太多放不下就叠到上一行
			draw_style_box(Style.box(Color(Pal.NAVY_DARK, 0.85), 10, 3, Color("7EE081")), Rect2(Vector2(gx, gy - 14), Vector2(120, 36)))
			HudWidgets.text(self, f, Vector2(gx + 8, gy + 12), "手雷×%d" % grenades, 22, Color("7EE081"))
			HudWidgets.keycap(self, Vector2(gx + 104, gy + 4), "G", 16)

	func _draw() -> void:
		_draw_strip()
		var r := Rect2(Vector2.ZERO, Vector2(410, 156))
		draw_style_box(Style.box(Color(0, 0, 0, 0.35), 24), Rect2(Vector2(6, 9), r.size))
		if buff:
			var a := 0.5 + 0.4 * sin(_t * 10.0)
			draw_style_box(Style.box(Color(Pal.ORANGE, a), 30), r.grow(7))
		draw_style_box(Style.box(Pal.NAVY, 24, 5, Pal.INK), r)
		if weapon != "rifle":
			var w := Weapons.info(weapon)
			draw_style_box(Style.box(Color(w.color, 0.5 + 0.3 * sin(_t * 8.0)), 30), r.grow(7))
			draw_style_box(Style.box(Pal.NAVY, 24, 5, Pal.INK), r)
			HudWidgets.text(self, Style.num_font(), Vector2(26, 92), "%d" % special, int(66 + _pop * 10), w.color, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
			HudWidgets.text(self, Style.title_font(), Vector2(28, 132), w.name, 26, w.color)
			HudWidgets.text(self, Style.title_font(), Vector2(230, 70), "神装", 40, w.color)
			return
		var col := Pal.RED if ammo <= 5 else (Pal.ORANGE if buff else Pal.CREAM)
		var big := int(66 + _pop * 10)
		var s := "%d" % ammo
		var nf := Style.num_font()
		HudWidgets.text(self, nf, Vector2(26, 92), s, big, col, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		var sw := nf.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
		HudWidgets.text(self, nf, Vector2(32 + sw, 92), "/%d" % mag, 22, Color(Pal.CREAM, 0.5))
		HudWidgets.text(self, Style.body_font(), Vector2(28, 128), "P-30 突击步枪", 18, Color(Pal.CREAM, 0.7))
		# 罐头弹药
		for i in mag:
			var row := i / 10
			var c := i % 10
			var p := Vector2(214 + c * 18.0, 22 + row * 31.0)
			var body := Rect2(p, Vector2(13, 22))
			if i < ammo:
				var can_col := Pal.RED if buff else Pal.ORANGE
				draw_rect(body, can_col)
				draw_rect(Rect2(p + Vector2(0, 7), Vector2(13, 7)), Pal.CREAM)
				draw_rect(Rect2(p, Vector2(13, 3)), can_col.lightened(0.35))
				draw_rect(body, Pal.INK, false, 2.0)
			else:
				draw_rect(body, Color(Pal.CREAM, 0.18), false, 2.0)
		# 换弹进度条
		if reloading or jam > 0.0:
			var br := Rect2(Vector2(214, 118), Vector2(176, 22))
			draw_rect(br, Color("0B1120"))
			var z0 := br.position.x + br.size.x * window.x
			var z1 := br.position.x + br.size.x * window.y
			draw_rect(Rect2(Vector2(z0, br.position.y), Vector2(z1 - z0, br.size.y)), Color(Pal.YELLOW, 0.9))
			var px := br.position.x + br.size.x * reload_p
			draw_rect(Rect2(br.position, Vector2(px - br.position.x, br.size.y)), Color(Pal.CREAM, 0.35))
			draw_rect(Rect2(Vector2(px - 2, br.position.y - 5), Vector2(5, br.size.y + 10)), Pal.CREAM if jam <= 0.0 else Pal.RED)
			draw_rect(br, Pal.INK, false, 3.0)
			var tip := "卡壳!" if jam > 0.0 else "黄区再按 R"
			HudWidgets.text(self, Style.title_font(), Vector2(214, 112), tip, 20, Pal.RED if jam > 0.0 else Pal.YELLOW)


# ======================================================================= 技能面板
class SkillPanel extends Control:
	var dash01 := 0.0
	var dash_left := 0.0
	var roll01 := 0.0
	var _t := 0.0
	var _ready_flash := 0.0
	var _was_cd := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		var rd := HudWidgets.real_delta(delta)
		_t += rd
		if _was_cd and dash01 <= 0.0:
			_ready_flash = 1.0
			Sfx.play("score", -8.0, 0.8)
		_was_cd = dash01 > 0.0
		_ready_flash = maxf(0.0, _ready_flash - rd * 2.0)
		queue_redraw()

	func _pie(c: Vector2, r: float, frac: float, col: Color) -> void:
		if frac <= 0.0:
			return
		var pts := PackedVector2Array([c])
		var seg := 32
		for i in seg + 1:
			var a := -PI / 2 + TAU * frac * float(i) / seg
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, col)

	func _draw() -> void:
		# Q 破门冲撞
		var c := Vector2(70, 66)
		var ready := dash01 <= 0.0
		if ready:
			draw_circle(c, 64 + _ready_flash * 10.0, Color(Pal.ORANGE, 0.35 + 0.2 * sin(_t * 6.0)))
		draw_circle(c, 58, Pal.INK)
		draw_circle(c, 53, Pal.ORANGE if ready else Pal.NAVY)
		var ic := Pal.INK if ready else Color(Pal.CREAM, 0.35)
		# 图标：箭头撞门
		draw_rect(Rect2(c + Vector2(14, -26), Vector2(12, 52)), ic)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-28, -8), c + Vector2(-2, -8), c + Vector2(-2, -20), c + Vector2(12, 0), c + Vector2(-2, 20), c + Vector2(-2, 8), c + Vector2(-28, 8)]), ic)
		for k in 3:
			draw_line(c + Vector2(30, -18 + k * 18), c + Vector2(40, -24 + k * 18), ic, 3)
		if not ready:
			_pie(c, 53, dash01, Color(0, 0, 0, 0.55))
			HudWidgets.text(self, Style.num_font(), c + Vector2(-40, 14), "%d" % ceili(dash_left), 40, Pal.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 80, 8)
		HudWidgets.keycap(self, c + Vector2(0, 58), "Q", 20)
		HudWidgets.text(self, Style.title_font(), c + Vector2(-60, 110), "破门冲撞", 24, Pal.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 120, 8)
		# 翻滚
		var c2 := Vector2(196, 82)
		var rready := roll01 <= 0.0
		draw_circle(c2, 42, Pal.INK)
		draw_circle(c2, 37, Pal.TEAL if rready else Pal.NAVY)
		var ic2 := Pal.INK if rready else Color(Pal.CREAM, 0.4)
		draw_arc(c2, 18, -PI * 0.9, PI * 0.6, 20, ic2, 6)
		var tip := c2 + Vector2(cos(PI * 0.6), sin(PI * 0.6)) * 18
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-12, -2), tip + Vector2(6, -10), tip + Vector2(4, 10)]), ic2)
		if not rready:
			_pie(c2, 37, roll01, Color(0, 0, 0, 0.5))
		HudWidgets.keycap(self, c2 + Vector2(0, 42), "空格", 16)
		HudWidgets.text(self, Style.title_font(), c2 + Vector2(-50, 94), "翻滚", 24, Pal.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 100, 8)


# ======================================================================= 任务目标横幅
class ObjectiveBanner extends Control:
	var title := ""
	var progress := ""
	var _flash := 0.0
	var _pop := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	var _dirty := true

	func set_objective(t: String, p: String) -> void:
		if t != title or p != progress:
			_dirty = true
		if t != title:
			_pop = 0.0
			_flash = 1.0
			if title != "":
				Sfx.play("radio", -12.0)
		elif p != progress:
			_flash = 0.7
		title = t
		progress = p

	func _process(delta: float) -> void:
		var rd := HudWidgets.real_delta(delta)
		_flash = maxf(0.0, _flash - rd * 2.5)
		_pop = minf(1.0, _pop + rd * 4.0)
		# 目标文字不变时不重画（原来每帧都重新排版、画一遍）
		if _dirty or _flash > 0.0 or _pop < 1.0:
			_dirty = false
			queue_redraw()

	func _draw() -> void:
		if title == "":
			return
		var tf := Style.title_font()
		var nf := Style.num_font()
		var tw := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
		var pw := nf.get_string_size(progress, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x if progress != "" else 0.0
		var w := 120.0 + tw + (pw + 36.0 if progress != "" else 30.0)
		var h := 64.0
		var cx := size.x * 0.5
		var s := 0.85 + 0.15 * ease(_pop, -2.0) + _flash * 0.04
		draw_set_transform(Vector2(cx, h * 0.5) * (1.0 - s), 0.0, Vector2(s, s))
		var r := Rect2(Vector2(cx - w * 0.5, 0), Vector2(w, h))
		draw_style_box(Style.box(Color(0, 0, 0, 0.35), 32), Rect2(r.position + Vector2(5, 7), r.size))
		draw_style_box(Style.box(Color(Pal.NAVY, 0.95), 32, 4, Pal.INK), r)
		var tab := Rect2(r.position + Vector2(6, 6), Vector2(96, h - 12))
		draw_style_box(Style.box(Pal.ORANGE, 26), tab)
		HudWidgets.text(self, tf, tab.position + Vector2(0, 38), "目标", 30, Pal.INK, HORIZONTAL_ALIGNMENT_CENTER, tab.size.x)
		HudWidgets.text(self, tf, r.position + Vector2(118, 45), title, 36, Pal.CREAM)
		if progress != "":
			HudWidgets.text(self, nf, r.position + Vector2(118 + tw + 18, 44), progress, 30, Pal.ORANGE)
		if _flash > 0.0:
			draw_style_box(Style.box(Color(1, 1, 1, _flash * 0.45), 32), r)


# ======================================================================= 准星
class Crosshair extends Control:
	var spread_px := 10.0
	var reload_p := -1.0
	var window := Vector2(0.44, 0.62)
	var ammo := 30
	var buff := false
	var _hit := 0.0
	var _kill := false
	var _shown_spread := 10.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func hit(kill: bool) -> void:
		_hit = 1.0
		_kill = kill or _kill and _hit > 0.5

	func _process(delta: float) -> void:
		var rd := HudWidgets.real_delta(delta)
		_hit = maxf(0.0, _hit - rd * 5.0)
		if _hit <= 0.0:
			_kill = false
		_shown_spread = lerpf(_shown_spread, spread_px, 1.0 - exp(-20.0 * rd))
		queue_redraw()

	func _draw() -> void:
		var m := get_local_mouse_position()
		var col := Pal.ORANGE if buff else Pal.CREAM
		var gap := 9.0 + _shown_spread
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var a: Vector2 = m + d * gap
			var b: Vector2 = m + d * (gap + 14.0)
			draw_line(a, b, Pal.INK, 7.0)
			draw_line(a, b, col, 3.0)
		draw_circle(m, 4.0, Pal.INK)
		draw_circle(m, 2.2, col)
		if _hit > 0.0:
			var hc := Color(Pal.RED if _kill else Color.WHITE, _hit)
			var s := 10.0 + (1.0 - _hit) * 8.0 + (6.0 if _kill else 0.0)
			for d2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var dn: Vector2 = d2.normalized()
				draw_line(m + dn * s * 0.55, m + dn * (s + 11.0), Color(Pal.INK, _hit), 7.0)
				draw_line(m + dn * s * 0.55, m + dn * (s + 11.0), hc, 3.5)
		if reload_p >= 0.0:
			var rr := 36.0
			draw_arc(m, rr, 0, TAU, 48, Color(Pal.INK, 0.7), 9.0)
			draw_arc(m, rr, -PI / 2 + window.x * TAU, -PI / 2 + window.y * TAU, 16, Pal.YELLOW, 7.0)
			draw_arc(m, rr, -PI / 2, -PI / 2 + reload_p * TAU, 40, Pal.CREAM, 3.5)
			var a2 := -PI / 2 + reload_p * TAU
			draw_circle(m + Vector2(cos(a2), sin(a2)) * rr, 6.0, Pal.INK)
			draw_circle(m + Vector2(cos(a2), sin(a2)) * rr, 4.0, Pal.CREAM)
		elif ammo <= 5:
			HudWidgets.text(self, Style.num_font(), m + Vector2(24, 38), "%d" % ammo, 24, Pal.RED, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)


# ======================================================================= 标记：目标指引 / 屏外敌人 / 受击方向
class Markers extends Control:
	var level: Level
	var target: Node3D
	var _dmg: Array = []
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func add_damage(from_world: Vector3) -> void:
		var cam := level.cam.cam
		var ps := cam.unproject_position(level.player.global_position)
		var fs := cam.unproject_position(from_world)
		var ang := (fs - ps).angle()
		_dmg.append({"a": ang, "t": 1.0})

	func _process(delta: float) -> void:
		var rd := HudWidgets.real_delta(delta)
		_t += rd
		for d in _dmg:
			d.t -= rd * 1.4
		_dmg = _dmg.filter(func(d): return d.t > 0.0)
		queue_redraw()

	func _draw() -> void:
		if level == null or level.cam == null or level.player == null:
			return
		var cam := level.cam.cam
		var vs := size
		var center := vs * 0.5
		var ps := cam.unproject_position(level.player.global_position + Vector3(0, 0.6, 0))
		for d in _dmg:
			var a: float = d.a
			var col := Color(Pal.RED, clampf(d.t, 0.0, 1.0) * 0.9)
			draw_arc(ps, 110.0, a - 0.38, a + 0.38, 18, Color(Pal.INK, col.a * 0.6), 16.0)
			draw_arc(ps, 110.0, a - 0.35, a + 0.35, 18, col, 10.0)
		# 屏外的已警觉敌人
		for e in level.enemies:
			if not e.alerted or not e.is_active():
				continue
			var sp := cam.unproject_position(e.global_position + Vector3(0, 0.8, 0))
			if Rect2(Vector2(40, 40), vs - Vector2(80, 80)).has_point(sp):
				continue
			var dir := (sp - center).normalized()
			var ep := _edge(center, dir, vs, 46.0)
			_arrow(ep, dir, 14.0, Color("B07CFF"))
		# 任务目标
		if target and is_instance_valid(target):
			var wp := target.global_position + Vector3(0, 2.2 if not (target is Door) else 2.8, 0)
			var sp2 := cam.unproject_position(wp)
			var lbl := "目标"
			if target is Door:
				lbl = "破门"
			elif target is Hostage:
				lbl = "人质"
			elif target is Enemy:
				lbl = "劫持者"
			var dist := level.player.global_position.distance_to(target.global_position)
			if Rect2(Vector2(60, 60), vs - Vector2(120, 120)).has_point(sp2):
				var bob := sin(_t * 5.0) * 6.0
				var p := sp2 + Vector2(0, bob)
				var tri := PackedVector2Array([p + Vector2(-16, -22), p + Vector2(16, -22), p + Vector2(0, 0)])
				draw_colored_polygon(tri, Pal.ORANGE)
				draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Pal.INK, 3.5)
				HudWidgets.text(self, Style.title_font(), p + Vector2(-80, -32), lbl, 28, Pal.ORANGE, HORIZONTAL_ALIGNMENT_CENTER, 160, 8)
			else:
				var dir2 := (sp2 - center).normalized()
				var ep2 := _edge(center, dir2, vs, 70.0)
				_arrow(ep2, dir2, 22.0, Pal.ORANGE)
				HudWidgets.text(self, Style.title_font(), ep2 - dir2 * 46.0 + Vector2(-60, 8), "%s %dm" % [lbl, int(dist)], 24, Pal.ORANGE, HORIZONTAL_ALIGNMENT_CENTER, 120, 8)

	func _edge(c: Vector2, dir: Vector2, vs: Vector2, margin: float) -> Vector2:
		var half := vs * 0.5 - Vector2(margin, margin)
		var tx := half.x / maxf(absf(dir.x), 0.0001)
		var ty := half.y / maxf(absf(dir.y), 0.0001)
		return c + dir * minf(tx, ty)

	func _arrow(p: Vector2, dir: Vector2, s: float, col: Color) -> void:
		var n := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([p + dir * s, p - dir * s * 0.6 + n * s * 0.8, p - dir * s * 0.6 - n * s * 0.8])
		draw_colored_polygon(tri, col)
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Pal.INK, 3.0)
