class_name Briefing
extends Control
## 任务简报 = 局长的投影仪：案件档案 + 平面图 + 警员证 + 局长交代任务。

const LINES := [
	"豆包，欢迎加入 P.A.W. 特警队。这是你的第一个案子。",
	"凌晨两点，喵喵便利店被[color=#B07CFF]黑眼圈帮[/color]洗劫，店员[color=#3DD6C6]小米[/color]被困在员工休息室。",
	"先清理店面，再破门救人。记住 —— 我们是特警，不是打手。[color=#FFB347]能铐就铐！[/color]",
]

var board: Control
var _speech: RichTextLabel
var _line := 0
var _chars := 0.0
var _flash: ColorRect
var _card: OfficerCard
var _threat: Label
var _intel_count: Control
var _picker: DiffPicker


func _ready() -> void:
	Style.full_rect(self)
	Sfx.music("menu")
	var bg := ColorRect.new()
	bg.color = Pal.NAVY_DARK
	Style.full_rect(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	board = Control.new()
	board.anchor_left = 0.5
	board.anchor_right = 0.5
	board.anchor_top = 0.5
	board.anchor_bottom = 0.5
	board.offset_left = -960
	board.offset_right = 960
	board.offset_top = -540
	board.offset_bottom = 540
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)

	var beam := Beam.new()
	beam.size = Vector2(1920, 1080)
	board.add_child(beam)
	_build_screen()
	_card = OfficerCard.new()
	_card.base = 0.6
	_card.position = Vector2(1400, -64)
	board.add_child(_card)
	_picker = DiffPicker.new()
	_picker.position = Vector2(1380, 452)
	_picker.changed.connect(_on_diff)
	board.add_child(_picker)
	_build_speech()
	_build_buttons()

	_flash = ColorRect.new()
	_flash.color = Color.BLACK
	Style.full_rect(_flash)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_callback(func(): Sfx.play("radio", -4.0))
	for a in [0.3, 0.9, 0.1, 0.7, 0.0]:
		tw.tween_property(_flash, "color:a", a, 0.06)
	tw.tween_callback(func(): _flash.visible = false)


func _build_screen() -> void:
	var scr := Control.new()
	scr.position = Vector2(80, 70)
	scr.size = Vector2(1270, 710)
	scr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(scr)
	var p := Style.panel(Color("16233F"), 12, 4, Color("2C4170"))
	p.size = scr.size
	scr.add_child(p)
	var no := Style.label("案件 #001  ·  紧急出勤", 26, Pal.ORANGE, Style.title_font())
	no.position = Vector2(44, 26)
	scr.add_child(no)
	var t := Style.label("午夜便利店", 76, Pal.CREAM, Style.title_font())
	t.position = Vector2(40, 56)
	scr.add_child(t)
	var meta := Style.label("毛绒市 樱花街 17 号  ·  凌晨 02:13  ·  威胁等级", 24, Color(Pal.CREAM, 0.65), Style.body_font())
	meta.position = Vector2(44, 150)
	scr.add_child(meta)
	_threat = Style.label("", 24, Pal.YELLOW, Style.body_font())
	_threat.position = Vector2(560, 150)
	scr.add_child(_threat)
	_update_threat()
	var map := MapSchematic.new()
	map.position = Vector2(40, 200)
	map.size = Vector2(700, 480)
	scr.add_child(map)

	var intel := VBoxContainer.new()
	intel.position = Vector2(780, 200)
	intel.size = Vector2(450, 480)
	intel.add_theme_constant_override("separation", 10)
	intel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(intel)
	intel.add_child(_head("已知情报"))
	_intel_count = _bullet("", Color("B07CFF"))
	intel.add_child(_intel_count)
	_update_threat()
	intel.add_child(_bullet("浣熊开枪前会亮起[红色激光]", Pal.RED))
	intel.add_child(_bullet("人质：店员 · 仓鼠小米（员工休息室）", Pal.TEAL))
	intel.add_child(_bullet("员工休息室门已反锁", Pal.ORANGE))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	intel.add_child(sp)
	intel.add_child(_head("行动目标"))
	intel.add_child(_bullet("① 清除店面与仓库的匪徒", Pal.CREAM))
	intel.add_child(_bullet("② 破门进入员工休息室", Pal.CREAM))
	intel.add_child(_bullet("③ 制服劫持者，解救人质", Pal.CREAM))
	intel.add_child(_bullet("加分：制服匪徒、完美换弹、零误伤", Pal.YELLOW))
	var scan := Style.shader_rect("res://shaders/scanlines.gdshader")
	scr.add_child(scan)


func _update_threat() -> void:
	var n := int(Game.diff_info().stars)
	_threat.text = "★".repeat(n) + "☆".repeat(5 - n) + ("  鬼畜!!" if n == 5 else "")
	_threat.add_theme_color_override("font_color", Game.diff_info().color)
	if _intel_count:
		(_intel_count.get_child(1) as Label).text = "匪徒约 %d 名：老鼠小毛贼 + 浣熊打手" % Level.bandit_count(Game.difficulty)


func _on_diff(d: String) -> void:
	Game.set_difficulty(d)
	_update_threat()
	if d == "insane":
		Game.shake(0.5)
		_threat.pivot_offset = _threat.size * 0.5
		var tw := _threat.create_tween()
		tw.tween_property(_threat, "scale", Vector2(1.35, 1.35), 0.06)
		tw.tween_property(_threat, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)


func _head(t: String) -> Control:
	var l := Style.label(t, 32, Pal.ORANGE, Style.title_font())
	return l


func _bullet(t: String, dot: Color) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := Style.panel(dot, 6, 2, Pal.INK)
	d.custom_minimum_size = Vector2(14, 14)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(d)
	var l := Style.label(t, 23, Pal.CREAM, Style.body_font())
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(410, 0)
	hb.add_child(l)
	return hb


func _build_speech() -> void:
	var box := Control.new()
	box.position = Vector2(80, 820)
	box.size = Vector2(1270, 200)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	board.add_child(box)
	var p := Style.panel(Color("0B1120"), 20, 4, Pal.INK, 10)
	p.size = box.size
	box.add_child(p)
	var pr := Portrait.new()
	pr.species = "chief"
	pr.bg = Pal.NAVY_LIGHT
	pr.position = Vector2(24, 24)
	pr.size = Vector2(150, 150)
	box.add_child(pr)
	var nb := Style.panel(Pal.ORANGE, 12, 3, Pal.INK)
	nb.position = Vector2(200, -20)
	nb.size = Vector2(200, 44)
	box.add_child(nb)
	var nl := Style.label("局长 · 老灰", 28, Pal.INK, Style.title_font())
	nl.position = Vector2(222, -18)
	box.add_child(nl)
	_speech = RichTextLabel.new()
	_speech.bbcode_enabled = true
	_speech.scroll_active = false
	_speech.position = Vector2(200, 46)
	_speech.size = Vector2(1030, 120)
	_speech.add_theme_font_override("normal_font", Style.body_font())
	_speech.add_theme_font_size_override("normal_font_size", 30)
	_speech.add_theme_color_override("default_color", Pal.CREAM)
	_speech.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_speech)
	var hint := Style.label("点击继续 ▼", 20, Color(Pal.CREAM, 0.45), Style.body_font())
	hint.position = Vector2(1120, 160)
	box.add_child(hint)
	box.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_advance()
	)
	_show_line(0)


func _show_line(i: int) -> void:
	_line = i
	_speech.text = LINES[i]
	_speech.visible_characters = 0
	_chars = 0.0


func _advance() -> void:
	if _speech.visible_characters >= 0 and _speech.visible_characters < _speech.get_total_character_count():
		_chars = 9999.0
		_speech.visible_characters = -1
		return
	if _line < LINES.size() - 1:
		Sfx.play("ui_click", -8.0)
		_show_line(_line + 1)


func _build_buttons() -> void:
	var go := StickerButton.new("出发！", "primary", 56)
	go.position = Vector2(1400, 790)
	go.custom_minimum_size = Vector2(440, 110)
	go.pressed.connect(func(): Game.goto("level"))
	board.add_child(go)
	var k := Style.label("" if Game.touch else "Enter", 20, Color(Pal.CREAM, 0.5), Style.num_font())
	k.position = Vector2(1400, 912)
	k.size = Vector2(440, 30)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(k)
	var back := StickerButton.new("返回任务板", "secondary", 28)
	back.position = Vector2(1490, 950)
	back.custom_minimum_size = Vector2(260, 64)
	back.pressed.connect(func(): Game.goto("menu"))
	board.add_child(back)
	go.grab_focus.call_deferred()


func _process(delta: float) -> void:
	var total := _speech.get_total_character_count()
	if _speech.visible_characters >= 0 and _chars < total:
		var before := int(_chars)
		_chars += delta * 30.0
		_speech.visible_characters = int(_chars)
		if int(_chars) / 2 != before / 2:
			Sfx.play("type", -16.0, 1.0, 0.15)
	elif _speech.visible_characters >= 0:
		_speech.visible_characters = -1


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1:
				_picker.pick("easy")
			KEY_2:
				_picker.pick("normal")
			KEY_3:
				_picker.pick("hard")
			KEY_4:
				_picker.pick("insane")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		Game.goto("level")
	elif event.is_action_pressed("pause"):
		Game.goto("menu")


# ------------------------------------------------------------------ 组件

class Beam extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var src := Vector2(715, -10)
		var top := Color(0.6, 0.8, 1.0, 0.16)
		var bot := Color(0.6, 0.8, 1.0, 0.03)
		draw_polygon(PackedVector2Array([src + Vector2(-50, 0), src + Vector2(50, 0), Vector2(1350, 780), Vector2(80, 780)]),
			PackedColorArray([top, top, bot, bot]))
		draw_circle(src + Vector2(0, 6), 30, Color(0.85, 0.95, 1.0, 0.8))


class MapSchematic extends Control:
	const WALLS := [
		[-12, -6, 5, -6], [-12, -6, -12, 8], [5, -10, 12, -10], [5, -10, 5, -6],
		[-12, 8, -1.6, 8], [1.6, 8, 12, 8], [12, -10, 12, 8],
		[5, -6, 5, 0], [5, 0, 5, 4.3], [5, 6.9, 5, 8], [5, 0, 8.0, 0], [9.6, 0, 12, 0],
	]
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		_t += d
		queue_redraw()

	func _w(x: float, z: float) -> Vector2:
		var sc := 15.0
		return Vector2(size.x * 0.5 + x * sc, 30 + (z + 11.0) * sc)

	func _rect(x0: float, z0: float, x1: float, z1: float, c: Color) -> void:
		var a := _w(x0, z0)
		var b := _w(x1, z1)
		draw_rect(Rect2(a, b - a), c)

	func _draw() -> void:
		draw_style_box(Style.box(Color("0E1830"), 10, 2, Color("2C4170")), Rect2(Vector2.ZERO, size))
		for i in range(1, 24):
			draw_line(Vector2(i * 30, 0), Vector2(i * 30, size.y), Color(1, 1, 1, 0.04), 1)
		for j in range(1, 16):
			draw_line(Vector2(0, j * 30), Vector2(size.x, j * 30), Color(1, 1, 1, 0.04), 1)
		_rect(-14.5, 8, 14.5, 18.5, Color(1, 1, 1, 0.05))
		_rect(-12, -6, 5, 8, Color(0.5, 0.7, 1.0, 0.12))
		_rect(5, 0, 12, 8, Color(0.5, 0.7, 1.0, 0.08))
		_rect(5, -10, 12, 0, Color(1.0, 0.5, 0.3, 0.12))
		for w in WALLS:
			draw_line(_w(w[0], w[1]), _w(w[2], w[3]), Pal.CREAM, 4)
		for sx in [-9.5, -6.5, -3.5]:
			_rect(sx - 0.45, -2.95, sx + 0.45, 3.45, Color(1, 1, 1, 0.25))
		_rect(0.6, 2.55, 4.4, 3.45, Color(1.0, 0.7, 0.4, 0.4))
		var f := Style.title_font()
		HudWidgets.text(self, f, _w(-8.5, 7.0), "店面", 24, Color(Pal.CREAM, 0.7))
		HudWidgets.text(self, f, _w(6.6, 7.2), "仓库", 22, Color(Pal.CREAM, 0.7))
		HudWidgets.text(self, f, _w(6.0, -8.0), "员工休息室", 22, Color(Pal.CREAM, 0.7))
		HudWidgets.text(self, f, _w(-4.0, 17.4), "樱花街", 22, Color(Pal.CREAM, 0.4))
		# 门（闪烁）
		var blink := 0.6 + 0.4 * sin(_t * 6.0)
		draw_line(_w(8.0, 0), _w(9.6, 0), Color(Pal.ORANGE, blink), 8)
		# 敌人
		for s in Level.SPAWNS:
			var p: Vector3 = s[1]
			var c := Color("B07CFF")
			if s[2] == "staff":
				c = Color(c, 0.45)
			var r := 7.0 if s[0] != "rat" else 5.0
			draw_circle(_w(p.x, p.z), r + 2.0, Pal.INK)
			draw_circle(_w(p.x, p.z), r, c)
		var hp := Level.HOSTAGE_POS
		draw_circle(_w(hp.x, hp.z), 10.0 + 3.0 * sin(_t * 5.0), Color(Pal.TEAL, 0.35))
		draw_circle(_w(hp.x, hp.z), 7.0, Pal.TEAL)
		# 路线（虚线流动）
		var route := [Vector2(0, 14.5), Vector2(0, 7.0), Vector2(-1.5, 4.5), Vector2(4.0, 5.6), Vector2(8.8, 4.8), Vector2(8.8, 0.8), Vector2(9.6, -5.2)]
		var off := fmod(_t * 40.0, 24.0)
		for i in route.size() - 1:
			var a := _w(route[i].x, route[i].y)
			var b := _w(route[i + 1].x, route[i + 1].y)
			var l := a.distance_to(b)
			var dir := (b - a) / l
			var d := -off
			while d < l:
				var s0 := maxf(d, 0.0)
				var s1 := minf(d + 12.0, l)
				if s1 > s0:
					draw_line(a + dir * s0, a + dir * s1, Pal.ORANGE, 4)
				d += 24.0
		var st := _w(0, 14.5)
		draw_circle(st, 9, Pal.ORANGE)
		HudWidgets.text(self, Style.title_font(), st + Vector2(14, 8), "你在这里", 20, Pal.ORANGE)
		# 图例
		var ly := size.y - 22
		draw_circle(Vector2(20, ly - 6), 6, Color("B07CFF"))
		HudWidgets.text(self, Style.body_font(), Vector2(32, ly), "匪徒", 18, Color(Pal.CREAM, 0.7))
		draw_circle(Vector2(96, ly - 6), 6, Pal.TEAL)
		HudWidgets.text(self, Style.body_font(), Vector2(108, ly), "人质", 18, Color(Pal.CREAM, 0.7))
		draw_line(Vector2(168, ly - 6), Vector2(188, ly - 6), Pal.ORANGE, 6)
		HudWidgets.text(self, Style.body_font(), Vector2(196, ly), "锁门", 18, Color(Pal.CREAM, 0.7))


## 难度选择：初级 / 中级 / 高级（鬼畜）
class DiffPicker extends Control:
	signal changed(d: String)
	const BW := 116.0
	const BH := 100.0
	const GAP := 8.0
	var _t := 0.0
	var _pop := {}
	var _hover := -1

	func _ready() -> void:
		size = Vector2(BW * 4 + GAP * 3, 330)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func pick(d: String) -> void:
		if d == Game.difficulty:
			return
		_pop[d] = 1.0
		Sfx.play("ui_click", -4.0, 0.8 if d == "insane" else 1.1)
		if d == "insane":
			Sfx.play("alarm", -10.0, 1.6)
		changed.emit(d)

	func _btn_rect(i: int) -> Rect2:
		return Rect2(Vector2(i * (BW + GAP), 48), Vector2(BW, BH))

	func _gui_input(e: InputEvent) -> void:
		var pos := Vector2(-1, -1)
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pos = e.position
		elif e is InputEventScreenTouch and e.pressed:
			pos = e.position
		if e is InputEventMouseMotion:
			_hover = -1
			for i in 4:
				if _btn_rect(i).has_point(e.position):
					_hover = i
		if pos.x < 0:
			return
		for i in 4:
			if _btn_rect(i).grow(4).has_point(pos):
				pick(Game.DIFF_ORDER[i])
				accept_event()

	func _process(d: float) -> void:
		_t += d
		for k in _pop.keys():
			_pop[k] = maxf(0.0, _pop[k] - d * 4.0)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _hover >= 0 else Control.CURSOR_ARROW
		queue_redraw()

	func _draw() -> void:
		var tf := Style.title_font()
		HudWidgets.text(self, tf, Vector2(2, 32), "选择难度", 30, Pal.ORANGE)
		HudWidgets.text(self, Style.body_font(), Vector2(150, 30), "各难度单独排行" if Game.touch else "各难度单独排行 · 按 1-4", 18, Color(Pal.CREAM, 0.45))
		for i in 4:
			var id: String = Game.DIFF_ORDER[i]
			var info: Dictionary = Game.DIFFS[id]
			var sel := id == Game.difficulty
			var r := _btn_rect(i)
			var c: Color = info.color
			var pop: float = _pop.get(id, 0.0)
			var off := Vector2.ZERO
			if sel:
				r = r.grow(4.0 + pop * 8.0)
				if id == "insane":
					# 鬼畜：选中后一直抖
					off = Vector2(randf_range(-2.5, 2.5), randf_range(-2.0, 2.0))
			elif i == _hover:
				off.y = -3
			r.position += off
			draw_style_box(Style.box(Color(0, 0, 0, 0.35), 16), Rect2(r.position + Vector2(5, 7), r.size))
			var bg := c if sel else Color("1A2748")
			if sel and id == "insane" and fmod(_t, 0.24) < 0.12:
				bg = Color("FF4D6D")
			draw_style_box(Style.box(bg, 16, 4, Pal.INK if sel else Color(c, 0.7)), r)
			var fg := Pal.INK if sel else c
			HudWidgets.text(self, tf, r.position + Vector2(0, 52), info.name, 36, fg, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			var tag: String = info.tag
			HudWidgets.text(self, tf, r.position + Vector2(0, 84), tag, 22, Color(fg, 0.75), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			if sel:
				draw_colored_polygon(Style.star_points(r.position + Vector2(r.size.x - 6, 6), 16, 7), Pal.CREAM)
		var info2: Dictionary = Game.diff_info()
		var y := 186.0
		for l in info2.desc:
			HudWidgets.text(self, Style.body_font(), Vector2(4, y), "· " + String(l), 21, Color(Pal.CREAM, 0.88))
			y += 29.0


## 可翻面的警员证
class OfficerCard extends Control:
	var base := 1.0
	var _back := false
	var _flip := 1.0
	var _t := 0.0

	func _ready() -> void:
		size = Vector2(420, 640)
		pivot_offset = size * 0.5
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		rotation = deg_to_rad(2.0)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("paper", -8.0, 1.4)
			var tw := create_tween()
			tw.tween_property(self, "_flip", 0.0, 0.12).set_ease(Tween.EASE_IN)
			tw.tween_callback(func(): _back = not _back)
			tw.tween_property(self, "_flip", 1.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			accept_event()

	func _process(d: float) -> void:
		_t += d
		scale = Vector2(maxf(_flip, 0.02), 1.0) * base
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(Style.box(Color(0, 0, 0, 0.35), 24), Rect2(Vector2(10, 14), size))
		draw_style_box(Style.box(Pal.CREAM, 24, 5, Pal.INK), r)
		draw_style_box(Style.box(Pal.NAVY, 20), Rect2(Vector2(5, 5), Vector2(size.x - 10, 92)))
		HudWidgets.text(self, Style.num_font(), Vector2(28, 50), "P.A.W.", 34, Pal.ORANGE)
		HudWidgets.text(self, Style.title_font(), Vector2(28, 84), "毛绒市警局 · 警员证", 24, Pal.CREAM)
		draw_colored_polygon(Style.star_points(Vector2(360, 50), 30, 13), Pal.YELLOW)
		if not _back:
			var pc := Vector2(size.x * 0.5, 236)
			draw_circle(pc, 112, Pal.INK)
			draw_circle(pc, 106, Pal.NAVY_LIGHT)
			Portrait.draw_face(self, pc + Vector2(0, 14), 82, "shiba")
			HudWidgets.text(self, Style.title_font(), Vector2(0, 412), "豆包", 72, Pal.INK, HORIZONTAL_ALIGNMENT_CENTER, size.x)
			HudWidgets.text(self, Style.title_font(), Vector2(0, 458), "柴犬 · 突击手", 28, Color(Pal.INK, 0.65), HORIZONTAL_ALIGNMENT_CENTER, size.x)
			HudWidgets.text(self, Style.num_font(), Vector2(0, 500), "NO. PAW-0427", 22, Pal.ORANGE_DARK, HORIZONTAL_ALIGNMENT_CENTER, size.x)
			for i in 34:
				var w := 2.0 if (i * 7) % 3 != 0 else 5.0
				draw_rect(Rect2(Vector2(70 + i * 8.4, 530), Vector2(w, 54)), Pal.INK)
			HudWidgets.text(self, Style.body_font(), Vector2(0, 622), "点击翻面查看属性", 18, Color(Pal.INK, 0.4), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		else:
			var stats := [["火力", 4], ["机动", 4], ["防御", 2], ["技能", 3]]
			for i in stats.size():
				var y := 150 + i * 62
				HudWidgets.text(self, Style.title_font(), Vector2(34, y + 30), stats[i][0], 32, Pal.INK)
				for k in 5:
					var c := Pal.ORANGE if k < stats[i][1] else Color(Pal.INK, 0.12)
					draw_style_box(Style.box(c, 6, 2, Pal.INK if k < stats[i][1] else Color(0, 0, 0, 0)), Rect2(Vector2(130 + k * 54, y + 4), Vector2(46, 32)))
			HudWidgets.text(self, Style.title_font(), Vector2(34, 432), "武器", 28, Pal.ORANGE_DARK)
			HudWidgets.text(self, Style.body_font(), Vector2(34, 468), "P-30 突击步枪 · 30 发", 24, Pal.INK)
			HudWidgets.text(self, Style.title_font(), Vector2(34, 516), "技能 · 破门冲撞 [Q]", 28, Pal.ORANGE_DARK)
			HudWidgets.text(self, Style.body_font(), Vector2(34, 552), "向前猛冲，撞飞匪徒、撞开门。", 22, Pal.INK)
			HudWidgets.text(self, Style.body_font(), Vector2(34, 584), "破门瞬间触发子弹时间。", 22, Pal.INK)
			HudWidgets.text(self, Style.body_font(), Vector2(0, 622), "口头禅：“汪！冲就完了！”", 18, Color(Pal.INK, 0.45), HORIZONTAL_ALIGNMENT_CENTER, size.x)
