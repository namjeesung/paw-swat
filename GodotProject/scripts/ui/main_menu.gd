class_name MainMenu
extends Control
## 主菜单 = 警局任务板：软木板、案件照片、红线、便利贴、小队名单。

const CASES := [
	{"no": "#001", "title": "序章 · 午夜便利店", "scene": "store", "locked": false, "pos": Vector2(96, 400), "rot": -4.0},
	{"no": "#002", "title": "雾港码头", "scene": "dock", "locked": true, "pos": Vector2(440, 448), "rot": 3.0},
	{"no": "#003", "title": "宠物医院人质事件", "scene": "hospital", "locked": true, "pos": Vector2(784, 384), "rot": -2.0},
	{"no": "#004", "title": "地铁追击", "scene": "subway", "locked": true, "pos": Vector2(1128, 452), "rot": 4.0},
	{"no": "#005", "title": "金罐储备库", "scene": "vault", "locked": true, "pos": Vector2(1472, 420), "rot": -3.0},
]
const TEAM := [
	["shiba", "豆包", "柴犬 · 突击手", false],
	["cat_black", "夜影", "黑猫 · 射手", true],
	["golden", "大福", "金毛 · 盾卫", true],
	["calico", "铃铛", "三花 · 技术员", true],
]

var board: Control
var _cards: Array[CaseCard] = []
var _strings: Control
var _toast: Label
var _toast_tw: Tween


func _ready() -> void:
	Style.full_rect(self)
	Sfx.music("menu")
	var bg := Style.shader_rect("res://shaders/cork.gdshader")
	add_child(bg)
	resized.connect(func(): (bg.material as ShaderMaterial).set_shader_parameter("aspect", size.x / maxf(size.y, 1.0)))

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

	_build_title()
	_build_note()
	_strings = StringLayer.new()
	_strings.menu = self
	_strings.size = Vector2(1920, 1080)
	board.add_child(_strings)
	for c in CASES:
		var card := CaseCard.new()
		card.case_no = c.no
		card.title = c.title
		card.scene = c.scene
		card.locked = c.locked
		card.base_rot = c.rot
		card.position = c.pos
		card.chosen.connect(_on_case)
		board.add_child(card)
		_cards.append(card)
	_build_team()
	_build_buttons()

	_toast = Style.label("", 30, Pal.CREAM, Style.title_font(), 10)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(560, 330)
	_toast.size = Vector2(800, 40)
	_toast.modulate.a = 0.0
	board.add_child(_toast)

	var ver := Style.label("v0.1 原型 · 序章可玩 · 美术为程序化占位", 18, Color(Pal.INK, 0.55), Style.body_font())
	ver.position = Vector2(760, 1042)
	board.add_child(ver)
	_intro_anim()


func _build_title() -> void:
	var paper := Control.new()
	paper.position = Vector2(70, 40)
	paper.size = Vector2(780, 270)
	paper.rotation = deg_to_rad(-2.0)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(paper)
	var shadow := Style.panel(Color(0, 0, 0, 0.3), 6)
	shadow.position = Vector2(10, 12)
	shadow.size = paper.size
	paper.add_child(shadow)
	var p := Style.panel(Pal.CREAM, 6, 0)
	p.size = paper.size
	paper.add_child(p)
	var band := Style.panel(Pal.NAVY, 0)
	band.position = Vector2(0, 0)
	band.size = Vector2(780, 18)
	paper.add_child(band)
	var t := Style.label("爪爪特警", 132, Pal.NAVY, Style.title_font(), 0)
	t.position = Vector2(36, 14)
	paper.add_child(t)
	var en := Style.label("PAW S.W.A.T.", 44, Pal.ORANGE, Style.num_font())
	en.position = Vector2(42, 168)
	paper.add_child(en)
	var tag := Style.label("毛绒市警局 · 特别行动档案", 28, Color(Pal.INK, 0.75), Style.title_font())
	tag.position = Vector2(420, 176)
	paper.add_child(tag)
	var line := Style.label("可爱的猫狗特警 × 硬核的战术破门", 22, Color(Pal.INK, 0.55), Style.body_font())
	line.position = Vector2(44, 224)
	paper.add_child(line)
	# 红色印章
	var stamp := StampMark.new()
	stamp.position = Vector2(670, 96)
	paper.add_child(stamp)
	for x in [24.0, 756.0]:
		var pin := PinMark.new()
		pin.position = Vector2(x, 30)
		paper.add_child(pin)


func _build_note() -> void:
	var note := Control.new()
	note.position = Vector2(1480, 44)
	note.size = Vector2(380, 330)
	note.rotation = deg_to_rad(3.0)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(note)
	var sh := Style.panel(Color(0, 0, 0, 0.28), 2)
	sh.position = Vector2(8, 12)
	sh.size = note.size
	note.add_child(sh)
	var p := Style.panel(Color("FFE27A"), 2)
	p.size = note.size
	note.add_child(p)
	var tape := Style.panel(Color(1, 1, 1, 0.45), 2)
	tape.position = Vector2(130, -14)
	tape.size = Vector2(120, 30)
	tape.rotation = deg_to_rad(-4)
	note.add_child(tape)
	var t := Style.label("出勤须知", 40, Pal.INK, Style.title_font())
	t.position = Vector2(26, 20)
	note.add_child(t)
	var lines := [
		["WASD", "移动"], ["鼠标", "瞄准 / 左键射击"], ["右键", "精准瞄准"], ["空格", "翻滚（无敌）"],
		["R", "换弹 · 黄区再按 = 完美"], ["Q", "破门冲撞"], ["E", "破门 / 救人"],
	]
	if Game.touch:
		lines = [
			["左手", "按住拖动 = 移动"], ["开火", "按住 = 自动瞄准射击"], ["拖动", "开火键拖动 = 手动瞄准"],
			["翻滚", "无敌闪避子弹"], ["换弹", "黄区再点 = 完美换弹"], ["冲撞", "撞飞匪徒 / 撞开门"], ["互动", "破门 / 救人"],
		]
	for i in lines.size():
		var row := HBoxContainer.new()
		row.position = Vector2(26, 80 + i * 34)
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k := Style.keycap(lines[i][0], 18)
		k.custom_minimum_size = Vector2(70, 0)
		row.add_child(k)
		row.add_child(Style.label(lines[i][1], 22, Pal.INK, Style.body_font()))
		note.add_child(row)


func _build_team() -> void:
	var box := Control.new()
	box.position = Vector2(70, 820)
	box.size = Vector2(860, 200)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(box)
	var sh := Style.panel(Color(0, 0, 0, 0.3), 10)
	sh.position = Vector2(8, 10)
	sh.size = box.size
	box.add_child(sh)
	var p := Style.panel(Pal.NAVY, 10, 4, Pal.INK)
	p.size = box.size
	box.add_child(p)
	var t := Style.label("P.A.W. 小队", 30, Pal.ORANGE, Style.title_font())
	t.position = Vector2(24, 12)
	box.add_child(t)
	for i in TEAM.size():
		var m: Array = TEAM[i]
		var x := 24 + i * 208
		var pr := Portrait.new()
		pr.species = m[0]
		pr.dim = m[3]
		pr.bg = Pal.NAVY_LIGHT
		pr.position = Vector2(x, 58)
		pr.size = Vector2(96, 96)
		box.add_child(pr)
		var n := Style.label(m[1] if not m[3] else "？？？", 28, Pal.CREAM if not m[3] else Color(Pal.CREAM, 0.4), Style.title_font())
		n.position = Vector2(x + 102, 72)
		box.add_child(n)
		var r := Style.label(m[2] if not m[3] else "待入队", 18, Color(Pal.CREAM, 0.6), Style.body_font())
		r.position = Vector2(x + 102, 112)
		box.add_child(r)


func _build_buttons() -> void:
	var start := StickerButton.new("开始行动  ▶", "primary", 46)
	start.position = Vector2(1430, 840)
	start.custom_minimum_size = Vector2(420, 96)
	start.pressed.connect(func(): Game.goto("briefing"))
	board.add_child(start)
	var quit := StickerButton.new("下班回家", "secondary", 28)
	quit.position = Vector2(1530, 960)
	quit.custom_minimum_size = Vector2(220, 60)
	quit.pressed.connect(func(): get_tree().quit())
	quit.visible = not OS.has_feature("web")
	board.add_child(quit)
	start.grab_focus.call_deferred()
	var lb := StickerButton.new("排行榜", "ghost", 28)
	lb.position = Vector2(1250, 960)
	lb.custom_minimum_size = Vector2(220, 60)
	lb.pressed.connect(func(): Game.goto("leaderboard"))
	board.add_child(lb)


func _on_case(card: CaseCard) -> void:
	if card.locked:
		_show_toast("「%s」档案尚未解锁 —— 先完成序章！" % card.title)
		return
	Game.goto("briefing")


func _show_toast(t: String) -> void:
	_toast.text = t
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.1)
	_toast_tw.tween_interval(1.6)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.3)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		Game.goto("briefing")


## 入场：照片依次“啪”地钉上
func _intro_anim() -> void:
	for i in _cards.size():
		var c := _cards[i]
		var target := c.position
		c.position = target + Vector2(0, -60)
		c.modulate.a = 0.0
		var tw := c.create_tween()
		tw.tween_interval(0.25 + i * 0.09)
		tw.tween_callback(func(): Sfx.play("paper", -14.0, 1.3))
		tw.tween_property(c, "modulate:a", 1.0, 0.12)
		tw.parallel().tween_property(c, "position", target, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func card_pins() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for c in _cards:
		pts.append(c.position + Vector2(CaseCard.SIZE.x * 0.5, 8).rotated(c.rotation))
	return pts


# ------------------------------------------------------------------ 装饰小件

class StringLayer extends Control:
	var menu: MainMenu

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var pins := menu.card_pins()
		for i in pins.size() - 1:
			var a: Vector2 = pins[i]
			var b: Vector2 = pins[i + 1]
			var pts := PackedVector2Array()
			for k in 17:
				var t := k / 16.0
				var p := a.lerp(b, t)
				p.y += sin(t * PI) * 34.0
				pts.append(p)
			draw_polyline(pts, Color(0, 0, 0, 0.25), 5.0, true)
			draw_polyline(pts, Color("C8102E"), 3.0, true)


class PinMark extends Control:
	func _draw() -> void:
		draw_circle(Vector2(3, 4), 12, Color(0, 0, 0, 0.3))
		draw_circle(Vector2.ZERO, 12, Pal.INK)
		draw_circle(Vector2.ZERO, 9.5, Pal.ORANGE)
		draw_circle(Vector2(-3, -3), 3, Color(1, 1, 1, 0.6))


class StampMark extends Control:
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, deg_to_rad(-12), Vector2.ONE)
		var c := Color(Pal.RED, 0.8)
		draw_arc(Vector2.ZERO, 46, 0, TAU, 40, c, 4.0)
		draw_arc(Vector2.ZERO, 38, 0, TAU, 40, c, 2.0)
		HudWidgets.text(self, Style.title_font(), Vector2(-46, 12), "绝密", 32, c, HORIZONTAL_ALIGNMENT_CENTER, 92)
