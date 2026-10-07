class_name StickerButton
extends Button
## “贴纸”风格按钮：粗描边 + 厚底边（按下时下沉）+ 悬停放大微转 + 音效。

var kind := "primary"
var _tw: Tween


func _init(txt := "", k := "primary", font_size := 34) -> void:
	text = txt
	kind = k
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_override("font", Style.title_font())
	add_theme_font_size_override("font_size", font_size)
	var bg := Pal.ORANGE
	var fg := Pal.INK
	match k:
		"secondary":
			bg = Pal.NAVY_LIGHT
			fg = Pal.CREAM
		"ghost":
			bg = Pal.CREAM
			fg = Pal.INK
		"danger":
			bg = Pal.RED
			fg = Pal.CREAM
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, fg)
	add_theme_color_override("font_pressed_color", fg)
	add_theme_color_override("font_disabled_color", Color(fg, 0.4))
	add_theme_stylebox_override("normal", _sb(bg, 9, 0))
	add_theme_stylebox_override("hover", _sb(bg.lightened(0.12), 9, 0))
	add_theme_stylebox_override("pressed", _sb(bg.darkened(0.08), 4, 5))
	add_theme_stylebox_override("disabled", _sb(Color(bg, 0.35), 9, 0))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_corner_radius_all(20)
	focus.set_border_width_all(3)
	focus.border_color = Pal.CREAM
	focus.set_expand_margin_all(6)
	add_theme_stylebox_override("focus", focus)


func _sb(bg: Color, bottom: int, push: int) -> StyleBoxFlat:
	var s := Style.box(bg, 16, 4, Pal.INK)
	s.border_width_bottom = bottom
	s.content_margin_left = 30
	s.content_margin_right = 30
	s.content_margin_top = 8 + push
	s.content_margin_bottom = 10 - push
	return s


func _ready() -> void:
	resized.connect(func(): pivot_offset = size * 0.5)
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	focus_entered.connect(_hover.bind(true))
	focus_exited.connect(_hover.bind(false))
	button_down.connect(func(): Sfx.play("ui_click", -4.0))


func _hover(on: bool) -> void:
	if disabled:
		return
	if on:
		Sfx.play("ui_hover", -10.0, 1.0, 0.1)
	if _tw:
		_tw.kill()
	_tw = create_tween().set_ignore_time_scale(true).set_parallel()
	_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tw.tween_property(self, "scale", Vector2.ONE * (1.06 if on else 1.0), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "rotation", deg_to_rad(-1.5) if on else 0.0, 0.14)
