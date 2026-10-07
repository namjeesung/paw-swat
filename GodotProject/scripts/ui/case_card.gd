class_name CaseCard
extends Control
## 任务板上的案件拍立得照片。悬停会翘起放大，未解锁的盖“机密”章。

signal chosen(card: CaseCard)

var case_no := "#001"
var title := ""
var scene := "store"
var locked := false
var base_rot := 0.0
var _hover := 0.0
var _tw: Tween
var _shake := 0.0
var _t := 0.0

const SIZE := Vector2(290, 350)


func _ready() -> void:
	size = SIZE
	pivot_offset = Vector2(SIZE.x * 0.5, 14)
	rotation = deg_to_rad(base_rot)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func _set_hover(on: bool) -> void:
	if on:
		Sfx.play("ui_hover", -8.0, 0.9 if locked else 1.1)
	z_index = 10 if on else 0
	if _tw:
		_tw.kill()
	_tw = create_tween().set_parallel()
	_tw.tween_property(self, "_hover", 1.0 if on else 0.0, 0.18)
	_tw.tween_property(self, "scale", Vector2.ONE * (1.08 if on else 1.0), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "rotation", deg_to_rad(base_rot * 0.2 if on else base_rot), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if locked:
			_shake = 1.0
			Sfx.play("ui_deny", -4.0)
		else:
			Sfx.play("ui_click", -2.0)
		chosen.emit(self)
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	_shake = maxf(0.0, _shake - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var sh := Vector2(sin(_t * 60.0) * 8.0 * _shake, 0)
	draw_set_transform(sh, 0, Vector2.ONE)
	var r := Rect2(Vector2.ZERO, SIZE)
	# 阴影随悬停加深
	var so := Vector2(8, 10) + Vector2(6, 10) * _hover
	draw_style_box(Style.box(Color(0, 0, 0, 0.32 + 0.1 * _hover), 6), Rect2(so, SIZE))
	if _hover > 0.01 and not locked:
		draw_style_box(Style.box(Color(Pal.ORANGE, 0.9 * _hover), 10), r.grow(7))
	draw_style_box(Style.box(Color("FBF8F1"), 4), r)
	var photo := Rect2(Vector2(18, 18), Vector2(SIZE.x - 36, 232))
	draw_rect(photo, Color("0E1626"))
	_draw_photo(photo)
	if locked:
		draw_rect(photo, Color(0.05, 0.07, 0.12, 0.6))
		HudWidgets.text(self, Style.num_font(), photo.position + Vector2(0, 160), "?", 120, Color(Pal.CREAM, 0.25), HORIZONTAL_ALIGNMENT_CENTER, photo.size.x)
	draw_rect(photo, Color(0, 0, 0, 0.25), false, 2.0)
	HudWidgets.text(self, Style.title_font(), Vector2(20, 292), title, 30, Pal.INK)
	HudWidgets.text(self, Style.num_font(), Vector2(20, 326), "CASE " + case_no, 18, Color(Pal.INK, 0.5))
	if not locked:
		HudWidgets.text(self, Style.title_font(), Vector2(160, 326), "可出勤 ▶", 22, Pal.ORANGE_DARK, HORIZONTAL_ALIGNMENT_RIGHT, 110)
	# 图钉
	var pin := Vector2(SIZE.x * 0.5, 8)
	draw_circle(pin + Vector2(3, 4), 13, Color(0, 0, 0, 0.3))
	draw_circle(pin, 13, Pal.INK)
	draw_circle(pin, 10.5, Pal.RED)
	draw_circle(pin + Vector2(-3.5, -3.5), 3.5, Color(1, 1, 1, 0.6))
	# 机密章
	if locked:
		draw_set_transform(sh + Vector2(150, 150), deg_to_rad(-14), Vector2.ONE)
		var sr := Rect2(Vector2(-90, -34), Vector2(180, 68))
		draw_rect(sr, Color(Pal.RED, 0.85), false, 5.0)
		draw_rect(sr.grow(-8), Color(Pal.RED, 0.85), false, 2.0)
		HudWidgets.text(self, Style.title_font(), Vector2(-90, 18), "机 密", 46, Color(Pal.RED, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 180)
		draw_set_transform(sh, 0, Vector2.ONE)


func _grad_rect(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]),
		PackedColorArray([top, top, bottom, bottom]))


func _draw_photo(p: Rect2) -> void:
	var o := p.position
	var w := p.size.x
	var h := p.size.y
	match scene:
		"store":
			_grad_rect(p, Color("101A3A"), Color("3A2E5C"))
			draw_circle(o + Vector2(w * 0.82, 40), 18, Color("FFF4D6"))
			draw_circle(o + Vector2(w * 0.82 - 7, 35), 16, Color("1A2448"))
			for i in 9:
				draw_circle(o + Vector2(fmod(i * 47.0, w), 18 + fmod(i * 23.0, 70)), 1.6, Color(1, 1, 1, 0.7))
			draw_rect(Rect2(o + Vector2(0, h - 40), Vector2(w, 40)), Color("232838"))
			var b := Rect2(o + Vector2(28, 92), Vector2(w - 56, h - 132))
			draw_rect(b, Color("F2E6CF"))
			draw_rect(Rect2(b.position - Vector2(6, 14), Vector2(b.size.x + 12, 18)), Pal.NAVY)
			draw_rect(Rect2(b.position + Vector2(14, 22), Vector2(70, 50)), Color("FFE7A3"))
			draw_rect(Rect2(b.position + Vector2(b.size.x - 84, 22), Vector2(70, 50)), Color("FFE7A3"))
			draw_rect(Rect2(b.position + Vector2(b.size.x * 0.5 - 22, 30), Vector2(44, b.size.y - 30)), Color("BFE6FF"))
			draw_rect(Rect2(o + Vector2(w * 0.5 - 70, 56), Vector2(140, 30)), Color("241A3A"))
			HudWidgets.text(self, Style.title_font(), o + Vector2(w * 0.5 - 70, 80), "喵喵 24H", 22, Color("FF7AC0"), HORIZONTAL_ALIGNMENT_CENTER, 140)
			draw_circle(o + Vector2(36, h - 34), 7, Pal.RED)
			draw_circle(o + Vector2(52, h - 34), 7, Color("3D7BFF"))
			draw_circle(o + Vector2(44, h - 34), 26, Color(1, 0.3, 0.4, 0.15))
		"dock":
			_grad_rect(p, Color("1C2B3A"), Color("47606E"))
			draw_rect(Rect2(o + Vector2(0, h - 50), Vector2(w, 50)), Color("1A2530"))
			var cols := [Color("A64B3C"), Color("3C7EA6"), Color("C9A13C"), Color("4F8F5A")]
			for i in 6:
				draw_rect(Rect2(o + Vector2(14 + (i % 3) * 78, h - 92 - (i / 3) * 34), Vector2(72, 32)), cols[i % 4])
			draw_line(o + Vector2(w - 60, h - 50), o + Vector2(w - 60, 30), Color("D9A53C"), 6)
			draw_line(o + Vector2(w - 60, 34), o + Vector2(w * 0.3, 34), Color("D9A53C"), 6)
		"hospital":
			_grad_rect(p, Color("16263A"), Color("2E4A5E"))
			draw_rect(Rect2(o + Vector2(40, 60), Vector2(w - 80, h - 60)), Color("DDE6EE"))
			draw_rect(Rect2(o + Vector2(w * 0.5 - 30, 80), Vector2(60, 18)), Pal.RED)
			draw_rect(Rect2(o + Vector2(w * 0.5 - 9, 62), Vector2(18, 54)), Pal.RED)
			for i in 4:
				draw_rect(Rect2(o + Vector2(56 + i * 46, 140), Vector2(30, 26)), Color("FFE7A3"))
		"subway":
			_grad_rect(p, Color("1A1A24"), Color("3A2A20"))
			draw_rect(Rect2(o + Vector2(-10, 90), Vector2(w + 20, 90)), Color("C9CED8"))
			draw_rect(Rect2(o + Vector2(-10, 150), Vector2(w + 20, 10)), Pal.ORANGE)
			for i in 5:
				draw_rect(Rect2(o + Vector2(10 + i * 52, 104), Vector2(38, 34)), Color("FFE7A3"))
			for i in 8:
				draw_line(o + Vector2(i * 36, h - 20), o + Vector2(i * 36 + 20, h - 20), Color("8A8F9A"), 4)
		"vault":
			_grad_rect(p, Color("2A2210"), Color("5A4518"))
			var c := o + Vector2(w * 0.5, h * 0.52)
			draw_circle(c, 82, Color("8A6A20"))
			draw_circle(c, 70, Color("D9A53C"))
			for i in 8:
				var a := TAU * i / 8.0
				draw_line(c, c + Vector2(cos(a), sin(a)) * 60, Color("8A6A20"), 6)
			draw_circle(c, 16, Color("8A6A20"))
