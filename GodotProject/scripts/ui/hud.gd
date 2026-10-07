class_name Hud
extends CanvasLayer
## 战斗 HUD：狗牌血条(左下) / 罐头弹药(右下) / 技能(右下偏左) / 目标(顶部) /
## 无线电(左上) / 计时(右上) / 准星 / 互动提示 / 得分飘字 / 屏幕特效。

var level: Level
var root: Control
var radio: Radio

var _fx: ColorRect
var _fx_mat: ShaderMaterial
var _markers: HudWidgets.Markers
var _tag: HudWidgets.DogTag
var _ammo: HudWidgets.AmmoPanel
var _skills: HudWidgets.SkillPanel
var _objective: HudWidgets.ObjectiveBanner
var _cross: HudWidgets.Crosshair
var touch: TouchControls
var _tips: TipCards
var _combo := 0
var diff_l: Label
var _combo_t := 0.0
var _combo_label: Label
var _combo_sub: Label
var _flash_rect: ColorRect
var _bars: Array[ColorRect] = []
var _cinema_t := 0.0
var _prompt: PanelContainer
var _prompt_key: Label
var _prompt_text: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_tw: Tween
var _feed: VBoxContainer
var _shield_label: Label
var _timer: Label
var _bt_banner: Control
var _bt := 0.0
var _bt_target := 0.0
var _hurt := 0.0
var _heart := 0.0
var _pulse := 0.0
var _esc_label: Control
var _case_label: Control


func _anchor(c: Control, ax: float, ay: float, x: float, y: float, w: float, h: float) -> Control:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h
	return c


func _ready() -> void:
	layer = 10
	root = Control.new()
	Style.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_fx = Style.shader_rect("res://shaders/screen_fx.gdshader")
	_fx_mat = _fx.material
	root.add_child(_fx)

	_markers = HudWidgets.Markers.new()
	_markers.level = level
	Style.full_rect(_markers)
	root.add_child(_markers)

	_tag = HudWidgets.DogTag.new()
	root.add_child(_anchor(_tag, 0, 1, 64, -206, 460, 170))

	_ammo = HudWidgets.AmmoPanel.new()
	root.add_child(_anchor(_ammo, 1, 1, -446, -196, 412, 158))

	_skills = HudWidgets.SkillPanel.new()
	root.add_child(_anchor(_skills, 1, 1, -720, -206, 250, 190))

	_objective = HudWidgets.ObjectiveBanner.new()
	root.add_child(_anchor(_objective, 0.5, 0, -600, 26, 1200, 70))

	radio = Radio.new()
	root.add_child(_anchor(radio, 0, 0, 28, 40, Radio.W, Radio.H))

	_timer = Style.label("00:00.0", 34, Pal.CREAM, Style.num_font(), 10)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_anchor(_timer, 1, 0, -330, 30, 300, 44))
	var di := Game.diff_info()
	var case_l := Style.label("案件 #001 · 午夜便利店 · ", 20, Color(Pal.CREAM, 0.7), Style.body_font(), 8)
	_case_label = case_l
	case_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_anchor(case_l, 1, 0, -540, 76, 400, 30))
	diff_l = Style.label("%s·%s" % [di.name, di.tag], 22, di.color, Style.title_font(), 8)
	root.add_child(_anchor(diff_l, 1, 0, -136, 74, 110, 30))
	var esc := Style.label("ESC 暂停", 18, Color(Pal.CREAM, 0.45), Style.body_font(), 6)
	_esc_label = esc
	esc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_anchor(esc, 1, 0, -230, 104, 200, 26))

	_feed = VBoxContainer.new()
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.add_theme_constant_override("separation", 6)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_anchor(_feed, 1, 0.5, -420, -260, 390, 230))

	_shield_label = Style.label("", 30, Color("60DFFF"), Style.title_font(), 8)
	_shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shield_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_anchor(_shield_label, 1, 0, -480, 140, 450, 48))
	_shield_label.visible = false
	_build_prompt()
	_build_toast()
	_build_bt_banner()

	_cross = HudWidgets.Crosshair.new()
	Style.full_rect(_cross)
	root.add_child(_cross)
	_build_combo()
	_tips = TipCards.new()
	# 放左侧、局长对讲下面：不挡屏幕中间的战场
	root.add_child(_anchor(_tips, 0, 0, 30, 200, TipCards.W, TipCards.H))
	for i in 2:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if i == 1:
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
		root.add_child(bar)
		_bars.append(bar)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Style.full_rect(_flash_rect)
	root.add_child(_flash_rect)
	touch = TouchControls.new()
	touch.level = level
	Style.full_rect(touch)
	root.add_child(touch)
	Game.input_mode_changed.connect(_apply_input_mode)
	_apply_input_mode(Game.touch)


## 手机 / 平板布局：底部两角留给拇指，信息集中到顶部
func _apply_input_mode(enabled: bool) -> void:
	touch.set_enabled(enabled)
	_ammo.visible = not enabled
	_skills.visible = not enabled
	_cross.visible = not enabled
	_esc_label.visible = not enabled
	_prompt_key.get_parent().visible = not enabled
	_tag.scale = Vector2.ONE * (0.8 if enabled else 1.0)
	if enabled:
		_anchor(_tag, 0, 0, 24, 18, 460, 170)
		_anchor(radio, 0, 0, 28, 176, Radio.W, Radio.H)
		_anchor(_tips, 0, 0, 30, 332, TipCards.W, TipCards.H)
		_anchor(_timer, 1, 0, -470, 30, 300, 44)
		_anchor(_case_label, 1, 0, -700, 76, 400, 30)
		_anchor(diff_l, 1, 0, -296, 74, 110, 30)
		_anchor(_feed, 1, 0.5, -440, -400, 390, 230)
		_anchor(_combo_label.get_parent(), 0, 0.5, 40, -16, 300, 140)
	else:
		_anchor(_tag, 0, 1, 64, -206, 460, 170)
		_anchor(radio, 0, 0, 28, 40, Radio.W, Radio.H)
		_anchor(_tips, 0, 0, 30, 200, TipCards.W, TipCards.H)
		_anchor(_timer, 1, 0, -330, 30, 300, 44)
		_anchor(_case_label, 1, 0, -540, 76, 400, 30)
		_anchor(diff_l, 1, 0, -136, 74, 110, 30)
		_anchor(_feed, 1, 0.5, -420, -260, 390, 230)
		_anchor(_combo_label.get_parent(), 1, 0.5, -330, -20, 300, 140)


func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	var sb := Style.box(Color(Pal.NAVY, 0.95), 14, 3, Pal.INK)
	sb.content_margin_left = 10
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_prompt.add_theme_stylebox_override("panel", sb)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_child(hb)
	var key := Style.keycap("E", 24)
	_prompt_key = key.get_child(0)
	hb.add_child(key)
	_prompt_text = Style.label("", 28, Pal.CREAM, Style.title_font())
	hb.add_child(_prompt_text)
	_prompt.visible = false
	root.add_child(_prompt)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	var sb := Style.box(Pal.RED, 18, 4, Pal.INK)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	_toast.add_theme_stylebox_override("panel", sb)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = Style.label("", 32, Pal.CREAM, Style.title_font())
	_toast.add_child(_toast_label)
	_toast.modulate.a = 0.0
	root.add_child(_anchor(_toast, 0.5, 0.68, -300, 0, 600, 56))


func _build_bt_banner() -> void:
	_bt_banner = Control.new()
	_bt_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_anchor(_bt_banner, 0.5, 0.2, -400, 0, 800, 120))
	var t := Style.label("子 弹 时 间", 76, Pal.CREAM, Style.title_font(), 18, Pal.NAVY_DARK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(800, 90)
	_bt_banner.add_child(t)
	var s := Style.label("— BREACH & CLEAR —", 26, Pal.TEAL, Style.num_font(), 8, Pal.NAVY_DARK)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.position = Vector2(0, 88)
	s.size = Vector2(800, 32)
	_bt_banner.add_child(s)
	_bt_banner.modulate.a = 0.0


# ------------------------------------------------------------------ 每帧同步

func _process(delta: float) -> void:
	if level == null or level.player == null:
		return
	var rd := HudWidgets.real_delta(delta)
	var p := level.player
	_shield_label.visible = p.shield_t > 0.0 and not p.dead and not level.finished
	_shield_label.text = "护盾 · 无敌 %.1f秒" % p.shield_t
	_shield_label.add_theme_color_override("font_color", Pal.ORANGE if p.shield_t <= 1.0 else Color("60DFFF"))
	_tag.hp = p.hp
	_tag.max_hp = p.max_hp
	_tag.in_cover = p.in_cover
	_tag.buff = p.buff_t > 0.0
	_ammo.ammo = p.ammo
	_ammo.reloading = p.reloading
	_ammo.reload_p = p.reload_progress()
	_ammo.window = p.perfect_window()
	_ammo.buff = p.buff_t > 0.0
	_skills.dash01 = p.dash_cd / Player.DASH_CD
	_skills.dash_left = p.dash_cd
	_skills.roll01 = clampf(p.roll_cd / (Player.ROLL_TIME + Player.ROLL_CD), 0.0, 1.0)
	_cross.spread_px = rad_to_deg(p.current_spread()) * 7.0
	_cross.reload_p = p.reload_progress() if p.reloading else -1.0
	_cross.window = p.perfect_window()
	_cross.ammo = p.ammo
	_cross.buff = p.buff_t > 0.0
	_cross.visible = not Game.touch and not level.finished and not p.dead
	var tt := level.t
	_timer.text = "%02d:%04.1f" % [int(tt / 60.0), fmod(tt, 60.0)]

	_update_prompt()

	_bt = move_toward(_bt, _bt_target, rd * 4.0)
	_fx_mat.set_shader_parameter("bullet_time", _bt)
	_bt_banner.modulate.a = move_toward(_bt_banner.modulate.a, 1.0 if _bt_banner_on else 0.0, rd * 5.0)
	_bt_banner.scale = Vector2.ONE * (1.0 + (1.0 - _bt_banner.modulate.a) * 0.3)
	_bt_banner.pivot_offset = Vector2(400, 60)
	_hurt = maxf(0.0, _hurt - rd * 2.5)
	_fx_mat.set_shader_parameter("hurt", _hurt)
	var low := 0.0 if p.dead else clampf(1.0 - p.hp / 40.0, 0.0, 1.0)
	_fx_mat.set_shader_parameter("low_hp", low)
	if low > 0.0 and not level.finished:
		_heart -= rd
		if _heart <= 0.0:
			_heart = 0.85
			_pulse = 1.0
			Sfx.play("heartbeat", -6.0 + low * 6.0, 1.0, 0.0)
	_pulse = maxf(0.0, _pulse - rd * 2.5)
	_fx_mat.set_shader_parameter("pulse", _pulse)
	_fx.visible = _bt > 0.001 or _hurt > 0.001 or low > 0.001
	_ammo.weapon = p.weapon
	_ammo.special = p.special_ammo
	_ammo.owned = p.owned_weapons()
	_ammo.grenades = p.grenades
	# 连杀计数
	_combo_t -= rd
	if _combo_t <= 0.0 and _combo > 0:
		_combo = 0
	var ca := 1.0 if _combo >= 3 else 0.0
	_combo_label.modulate.a = move_toward(_combo_label.modulate.a, ca, rd * 6.0)
	_combo_sub.modulate.a = _combo_label.modulate.a
	_combo_label.scale = _combo_label.scale.lerp(Vector2.ONE, 1.0 - exp(-12.0 * rd))
	# 电影黑边（镜头指引时）
	_cinema_t -= rd
	var bh := 70.0 if _cinema_t > 0.0 else 0.0
	for i in 2:
		var b := _bars[i]
		var cur := b.size.y
		var nh := lerpf(cur, bh, 1.0 - exp(-8.0 * rd))
		b.size = Vector2(root.size.x, nh)
		b.position = Vector2(0, 0 if i == 0 else root.size.y - nh)
	_flash_rect.color.a = maxf(0.0, _flash_rect.color.a - rd * 1.2)


func _update_prompt() -> void:
	var it := level.best_interactable()
	if it == null:
		_prompt.visible = false
		return
	var enabled: bool = it.interact_enabled()
	_prompt_text.text = it.interact_text()
	_prompt_key.text = "E"
	var sb := _prompt.get_theme_stylebox("panel") as StyleBoxFlat
	sb.bg_color = Color(Pal.NAVY, 0.95) if enabled else Color("3A3F4F", 0.95)
	_prompt_text.add_theme_color_override("font_color", Pal.CREAM if enabled else Color(Pal.CREAM, 0.6))
	var sp := level.cam.cam.unproject_position(it.interact_pos() + Vector3(0, 1.9, 0))
	_prompt.reset_size()
	_prompt.position = sp - Vector2(_prompt.size.x * 0.5, _prompt.size.y)
	_prompt.visible = true


# ------------------------------------------------------------------ 事件

func set_objective(title: String, progress: String) -> void:
	_objective.set_objective(title, progress)


func set_target(n: Node3D) -> void:
	_markers.target = n


func on_player_hit(from: Vector3, _dmg: float) -> void:
	_tag.hit()
	_markers.add_damage(from)
	_hurt = 1.0


func hitmarker(kill: bool) -> void:
	_cross.hit(kill)


func on_shot() -> void:
	_ammo.shot()


func on_roll() -> void:
	pass


func reload_jam() -> void:
	_ammo.jam = 0.6


var _bt_banner_on := false


func set_bullet_time(active: bool, banner := true) -> void:
	_bt_target = 1.0 if active else 0.0
	_bt_banner_on = active and banner


func toast(text: String) -> void:
	_toast_label.text = text
	if _toast_tw:
		_toast_tw.kill()
	_toast.pivot_offset = _toast.size * 0.5
	_toast.scale = Vector2.ONE * 1.3
	_toast_tw = create_tween().set_ignore_time_scale(true)
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.08)
	_toast_tw.parallel().tween_property(_toast, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tw.tween_interval(1.4)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.3)


func score_popup(text: String, pts: int) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	var l := Style.label(text, 28, Pal.CREAM, Style.title_font(), 10)
	var n := Style.label("+%d" % pts, 30, Pal.ORANGE, Style.num_font(), 10)
	row.add_child(l)
	row.add_child(n)
	_feed.add_child(row)
	while _feed.get_child_count() > 5:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	row.modulate.a = 0.0
	var tw := row.create_tween().set_ignore_time_scale(true)
	tw.tween_property(row, "modulate:a", 1.0, 0.12)
	tw.tween_interval(1.8)
	tw.tween_property(row, "modulate:a", 0.0, 0.4)
	tw.tween_callback(row.queue_free)
	Sfx.play("score", -10.0)


## 任务完成 / 失败的大横幅
func mission_banner(success: bool, sub: String) -> void:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_anchor(box, 0.5, 0.42, -520, -110, 1040, 220))
	var band := ColorRect.new()
	band.color = Color(Pal.NAVY_DARK, 0.88)
	band.position = Vector2(-2000, 20)
	band.size = Vector2(5040, 180)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(band)
	var t := Style.label("任务完成" if success else "行动失败", 110, Pal.ORANGE if success else Pal.RED, Style.title_font(), 22, Pal.INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(1040, 140)
	t.position = Vector2(0, 14)
	box.add_child(t)
	var s := Style.label(sub, 32, Pal.CREAM, Style.title_font(), 8)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.size = Vector2(1040, 44)
	s.position = Vector2(0, 148)
	box.add_child(s)
	box.pivot_offset = Vector2(520, 110)
	box.scale = Vector2(1.6, 1.6)
	box.modulate.a = 0.0
	var tw := box.create_tween().set_ignore_time_scale(true)
	tw.tween_property(box, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(box, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Game.shake(0.4)


# ------------------------------------------------------------------ 神装 / 僵尸潮 / 连杀

func _build_combo() -> void:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Game.touch:
		# 左侧新手提示卡下面（提示卡在 y 332~500）
		_anchor(box, 0, 0.5, 40, -16, 300, 140)
	else:
		_anchor(box, 1, 0.5, -330, -20, 300, 140)
	root.add_child(box)
	_combo_label = Style.label("×0", 84, Pal.YELLOW, Style.num_font(), 18)
	_combo_label.size = Vector2(300, 100)
	_combo_label.pivot_offset = Vector2(60, 50)
	_combo_label.modulate.a = 0.0
	box.add_child(_combo_label)
	_combo_sub = Style.label("连 杀", 30, Pal.CREAM, Style.title_font(), 10)
	_combo_sub.position = Vector2(8, 96)
	_combo_sub.modulate.a = 0.0
	box.add_child(_combo_sub)


func add_kill() -> void:
	_combo += 1
	_combo_t = 2.6
	_combo_label.text = "×%d" % _combo
	_combo_label.scale = Vector2.ONE * 1.5
	var c := Pal.YELLOW
	if _combo >= 30:
		c = Color("FF4FD8")
	elif _combo >= 15:
		c = Pal.RED
	elif _combo >= 8:
		c = Pal.ORANGE
	_combo_label.add_theme_color_override("font_color", c)
	if _combo in [10, 20, 30, 50, 80]:
		var words := {10: "火力全开！", 20: "势不可挡！", 30: "超神！", 50: "传说特警！", 80: "猫狗之神！"}
		toast(words[_combo])
		Sfx.play("perfect", -6.0, 1.3, 0.0)


## 切换神装：弹药面板弹一下
func on_weapon_switch(_id: String) -> void:
	_ammo.shot()


## 获得神装的大横幅
func weapon_banner(id: String) -> void:
	var w := Weapons.info(id)
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_anchor(box, 0.5, 0.74, -420, -60, 840, 130))
	var bg := Style.panel(Color(Pal.NAVY_DARK, 0.92), 24, 5, w.color)
	bg.size = Vector2(840, 130)
	box.add_child(bg)
	var tag := Style.label("获得神装" if id != "gatling" else "神器降临", 26, Pal.INK, Style.title_font())
	var tagbg := Style.panel(w.color, 12)
	tagbg.position = Vector2(30, -20)
	tagbg.size = Vector2(150, 42)
	box.add_child(tagbg)
	tag.position = Vector2(48, -18)
	box.add_child(tag)
	var nm := Style.label(w.name, 52, w.color, Style.title_font(), 12)
	nm.position = Vector2(34, 22)
	box.add_child(nm)
	var desc := Style.label(w.desc, 26, Pal.CREAM, Style.body_font())
	desc.position = Vector2(38, 86)
	box.add_child(desc)
	box.pivot_offset = Vector2(420, 65)
	box.scale = Vector2(1.4, 1.4)
	box.modulate.a = 0.0
	var tw := box.create_tween().set_ignore_time_scale(true)
	tw.tween_property(box, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.8)
	tw.tween_property(box, "modulate:a", 0.0, 0.3)
	tw.tween_callback(box.queue_free)


## Prepared during ordinary level entry, long before the rescue/horde.
## Keep these exact text/size/outline combinations in sync with wave_banner,
## fire_shout and Cutscene.PixelCanvas._texts. Nothing is shown or played.
func prewarm_transition_text() -> void:
	Style.prewarm_text(self, [
		[Style.title_font(), "僵尸鼠来袭！", 110, 22],
		[Style.title_font(), "实验罐头泄漏 · 保护小米", 30, 8],
		[Style.num_font(), "FIRE!", 220, 40],
		[Style.title_font(), "神器组装中...", 18, 6, 1.0],
		[Style.title_font(), "神器装备！", 24, 8, 1.0],
		[Style.title_font(), "罐头加特林", 22, 8, 1.0],
		[Style.num_font(), "FIRE!", 52, 12, 1.0],
	])


## 僵尸来袭横幅
func wave_banner() -> void:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_anchor(box, 0.5, 0.36, -700, -90, 1400, 180))
	var band := ColorRect.new()
	band.color = Color("1E4D32", 0.9)
	band.position = Vector2(-1500, 20)
	band.size = Vector2(4400, 140)
	box.add_child(band)
	var t := Style.label("僵尸鼠来袭！", 110, Color("7CFFB2"), Style.title_font(), 22, Pal.INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(1400, 130)
	t.position = Vector2(0, 10)
	box.add_child(t)
	var s := Style.label("实验罐头泄漏 · 保护小米", 30, Pal.CREAM, Style.title_font(), 8)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.size = Vector2(1400, 40)
	s.position = Vector2(0, 132)
	box.add_child(s)
	box.pivot_offset = Vector2(700, 90)
	box.scale = Vector2(1.5, 1.5)
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.0)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(box.queue_free)


## FIRE! 大字
func fire_shout() -> void:
	var l := Style.label("FIRE!", 220, Pal.YELLOW, Style.num_font(), 40, Pal.INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_anchor(l, 0.5, 0.42, -700, -140, 1400, 280))
	l.pivot_offset = Vector2(700, 140)
	l.rotation = deg_to_rad(-6)
	l.scale = Vector2.ONE * 2.5
	var tw := l.create_tween().set_ignore_time_scale(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(l, "scale", Vector2.ONE * 1.3, 0.35)
	tw.tween_callback(l.queue_free)
	flash(0.6)


func flash(a: float) -> void:
	_flash_rect.color.a = a


## 镜头指引时显示电影黑边
func cinema(t: float) -> void:
	_cinema_t = t


func tip(id: String) -> void:
	_tips.show_tip(id)
