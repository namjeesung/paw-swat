class_name PauseMenu
extends CanvasLayer
## 暂停菜单：背景模糊 + 从右侧滑出的“对讲机”。

var level: Level
var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _device: Control
var _open := false
var _tw: Tween
var _first: Button


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_bg = Style.shader_rect("res://shaders/blur.gdshader", {"amount": 0.0})
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg_mat = _bg.material
	add_child(_bg)

	var title := Style.label("行动暂停", 96, Pal.CREAM, Style.title_font(), 20, Pal.INK)
	title.position = Vector2(120, 120)
	_bg.add_child(title)
	var sub := Style.label("对讲机已接通 · 局长在线待命", 28, Color(Pal.CREAM, 0.7), Style.body_font())
	sub.position = Vector2(126, 250)
	_bg.add_child(sub)
	var help := StickerButton.new("操作说明 ？", "ghost", 34)
	help.position = Vector2(126, 320)
	help.pressed.connect(_open_help)
	_bg.add_child(help)
	var tips := Style.label("小贴士：击倒匪徒即永久制服，并会迅速消散。\n翻滚有无敌帧，子弹时间里你比世界更快。", 24, Color(Pal.CREAM, 0.55), Style.body_font())
	tips.position = Vector2(126, 860)
	_bg.add_child(tips)

	_device = Control.new()
	_device.anchor_left = 1
	_device.anchor_right = 1
	_device.anchor_top = 0.5
	_device.anchor_bottom = 0.5
	_device.offset_left = -560
	_device.offset_right = -80
	_device.offset_top = -400
	_device.offset_bottom = 400
	_device.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_device)
	_build_device()


func _build_device() -> void:
	# 天线
	var ant := Style.panel(Pal.INK, 10)
	ant.position = Vector2(330, -90)
	ant.size = Vector2(36, 140)
	_device.add_child(ant)
	var tipc := Style.panel(Pal.RED, 14, 4, Pal.INK)
	tipc.position = Vector2(326, -104)
	tipc.size = Vector2(44, 28)
	_device.add_child(tipc)
	# 机身
	var body := Style.panel(Pal.NAVY, 48, 6, Pal.INK, 18)
	body.size = Vector2(480, 800)
	_device.add_child(body)
	var stripe := Style.panel(Pal.ORANGE, 0)
	stripe.position = Vector2(6, 92)
	stripe.size = Vector2(468, 14)
	_device.add_child(stripe)
	# 喇叭格栅
	for i in 5:
		var g := Style.panel(Color("0E1626"), 6)
		g.position = Vector2(110, 26 + i * 12)
		g.size = Vector2(260, 6)
		_device.add_child(g)
	# 屏幕
	var lcd := Style.panel(Color("1F4A47"), 14, 4, Pal.INK)
	lcd.position = Vector2(40, 130)
	lcd.size = Vector2(400, 120)
	_device.add_child(lcd)
	var l1 := Style.label("CH-01  P.A.W.", 30, Pal.TEAL, Style.num_font())
	l1.position = Vector2(64, 144)
	_device.add_child(l1)
	var l2 := Style.label("待命中 …", 32, Pal.TEAL, Style.title_font())
	l2.position = Vector2(64, 190)
	_device.add_child(l2)

	var vb := VBoxContainer.new()
	vb.position = Vector2(56, 280)
	vb.size = Vector2(368, 300)
	vb.add_theme_constant_override("separation", 16)
	_device.add_child(vb)
	var b1 := StickerButton.new("继续行动", "primary", 34)
	b1.pressed.connect(close)
	vb.add_child(b1)
	_first = b1
	var b2 := StickerButton.new("重新开始", "secondary", 30)
	b2.pressed.connect(func(): Game.goto("level"))
	vb.add_child(b2)
	var b3 := StickerButton.new("返回任务板", "secondary", 30)
	b3.pressed.connect(func(): Game.goto("menu"))
	vb.add_child(b3)

	var opts := VBoxContainer.new()
	opts.position = Vector2(56, 572)
	opts.size = Vector2(368, 180)
	opts.add_theme_constant_override("separation", 6)
	_device.add_child(opts)
	opts.add_child(_slider("音效", "sfx", "SFX"))
	opts.add_child(_slider("音乐", "music", "Music"))
	var shake := CheckButton.new()
	shake.text = "屏幕震动"
	shake.button_pressed = float(Game.settings.shake) > 0.0
	shake.add_theme_font_override("font", Style.title_font())
	shake.add_theme_font_size_override("font_size", 26)
	shake.add_theme_color_override("font_color", Pal.CREAM)
	shake.add_theme_color_override("font_hover_color", Pal.ORANGE)
	shake.add_theme_color_override("font_pressed_color", Pal.CREAM)
	shake.toggled.connect(func(on): Game.settings.shake = 1.0 if on else 0.0)
	opts.add_child(shake)
	var touch_opts := VBoxContainer.new()
	touch_opts.name = "TouchOptions"
	touch_opts.visible = Game.touch
	opts.add_child(touch_opts)
	Game.input_mode_changed.connect(func(enabled: bool): touch_opts.visible = enabled)
	var mode := CheckButton.new()
	mode.text = "松手射击（荒野乱斗式）"
	mode.button_pressed = Game.settings.get("aim_mode", "lock") == "release"
	mode.add_theme_font_override("font", Style.title_font())
	mode.add_theme_font_size_override("font_size", 26)
	mode.add_theme_color_override("font_color", Pal.CREAM)
	mode.add_theme_color_override("font_pressed_color", Pal.YELLOW)
	mode.toggled.connect(func(on): Game.settings.aim_mode = "release" if on else "lock")
	touch_opts.add_child(mode)
	var vib := CheckButton.new()
	vib.text = "震动反馈"
	vib.button_pressed = bool(Game.settings.vibrate)
	vib.add_theme_font_override("font", Style.title_font())
	vib.add_theme_font_size_override("font_size", 26)
	vib.add_theme_color_override("font_color", Pal.CREAM)
	vib.add_theme_color_override("font_pressed_color", Pal.CREAM)
	vib.toggled.connect(func(on): Game.settings.vibrate = on)
	touch_opts.add_child(vib)


func _slider(text: String, key: String, bus: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var l := Style.label(text, 26, Pal.CREAM, Style.title_font())
	l.custom_minimum_size = Vector2(70, 0)
	hb.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Game.settings[key])
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 32)
	s.add_theme_stylebox_override("slider", Style.box(Color("0E1626"), 6, 2, Pal.INK))
	s.add_theme_stylebox_override("grabber_area", Style.box(Pal.ORANGE, 6))
	s.add_theme_stylebox_override("grabber_area_highlight", Style.box(Pal.ORANGE.lightened(0.2), 6))
	s.value_changed.connect(func(v):
		Game.settings[key] = v
		Sfx.set_volume(bus, v)
		Sfx.play("ui_hover", -8.0)
	)
	hb.add_child(s)
	return hb


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if _open:
			close()
		elif level and not level.finished:
			open()


func is_open() -> bool:
	return _open


func open() -> void:
	if level and level.hud and level.hud.touch:
		level.hud.touch.release_all()
	if _open:
		return
	_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("radio", -4.0)
	if _tw:
		_tw.kill()
	_tw = create_tween().set_parallel().set_ignore_time_scale(true)
	_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tw.tween_property(_bg_mat, "shader_parameter/amount", 1.0, 0.25)
	_tw.tween_property(_device, "offset_left", -560.0, 0.35).from(200.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_device, "offset_right", -80.0, 0.35).from(680.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_device, "rotation", 0.0, 0.35).from(0.2)
	_first.grab_focus.call_deferred()


func close() -> void:
	if not _open:
		return
	if level and level.hud and level.hud.touch:
		level.hud.touch.release_all()
	_open = false
	Game.save_settings()
	if _help:
		_help.visible = false
	Sfx.play("ui_click", -6.0)
	if _tw:
		_tw.kill()
	_tw = create_tween().set_parallel().set_ignore_time_scale(true)
	_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tw.tween_property(_bg_mat, "shader_parameter/amount", 0.0, 0.18)
	_tw.tween_property(_device, "offset_left", 200.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tw.tween_property(_device, "offset_right", 680.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tw.chain().tween_callback(func():
		visible = false
		get_tree().paused = false
		if not Game.touch:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	)


# ------------------------------------------------------------------ 操作说明页

var _help: Control


func _open_help() -> void:
	if _help == null:
		_build_help()
	_help.visible = true
	Sfx.play("paper", -6.0)


func _build_help() -> void:
	_help = ColorRect.new()
	(_help as ColorRect).color = Color(Pal.NAVY_DARK, 0.97)
	Style.full_rect(_help)
	_help.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_help)
	var title := Style.label("操作说明", 64, Pal.YELLOW, Style.title_font(), 12)
	title.position = Vector2(60, 30)
	_help.add_child(title)
	var close := StickerButton.new("返回", "primary", 32)
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.offset_left = -240
	close.offset_right = -60
	close.offset_top = 36
	close.offset_bottom = 110
	close.pressed.connect(func(): _help.visible = false)
	_help.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 50
	scroll.offset_top = 130
	scroll.offset_right = -50
	scroll.offset_bottom = -30
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_help.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(grid)
	for id in Tips.ORDER:
		grid.add_child(_help_card(id))


func _help_card(id: String) -> Control:
	var tip := Tips.get_tip(id)
	var card := PanelContainer.new()
	var sb := Style.box(Pal.NAVY, 18, 3, Pal.NAVY_LIGHT)
	sb.content_margin_left = 16
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	card.add_child(hb)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(84, 84)
	icon.draw.connect(func():
		icon.draw_circle(Vector2(42, 42), 40, Pal.INK)
		icon.draw_circle(Vector2(42, 42), 36, Pal.CREAM)
		Tips.draw_icon(icon, Vector2(42, 42), 34, tip[0])
	)
	hb.add_child(icon)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	vb.add_child(Style.label(tip[1], 30, Pal.YELLOW, Style.title_font()))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_font_override("normal_font", Style.body_font())
	body.add_theme_font_override("bold_font", Style.body_font())
	body.add_theme_font_size_override("normal_font_size", 22)
	body.add_theme_font_size_override("bold_font_size", 22)
	body.add_theme_color_override("default_color", Pal.CREAM)
	body.text = Tips.rich(tip[2])
	vb.add_child(body)
	return card
