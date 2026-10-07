extends Node
## 全局：界面切换（警戒线转场）、时间控制（顿帧 / 子弹时间）、设置、本局统计。

signal shake_requested(amount: float)
signal bullet_time_changed(active: bool)
signal input_mode_changed(touch_enabled: bool)

const BT_SCALE := 0.25          # 子弹时间里世界的速度
const BT_PLAYER_SPEED := 0.6    # 子弹时间里玩家的相对速度

var container: Node
var current: Node
var settings := {"sfx": 0.85, "music": 0.55, "shake": 1.0, "vibrate": true, "aim_mode": "lock"}

## 难度：初级 / 中级 / 高级 / 鬼畜。差距拉得很大（血量、匪徒数量、僵尸数量都不同），各自单独上排行榜。
## bandits：0 = 少两只老鼠，1 = 标准 11 名，2 = +5 名，3 = +12 名（见 Level.EXTRA_*）
const DIFF_ORDER := ["easy", "normal", "hard", "insane"]
const DIFFS := {
	"easy": {
		"name": "初级", "tag": "萌新", "color": Color("4ED6C2"), "stars": 1,
		"desc": ["匪徒 9 名，血量 ×0.5", "你有 200 血，受伤 ×0.4", "僵尸最多 8 只", "人质能挨 5 下"],
		"bandits": 0, "player_hp": 200.0,
		"enemy_hp": 0.5, "enemy_speed": 0.8, "tele": 1.8, "atk_cd": 1.6, "burst": -1,
		"bullet_speed": 0.75, "spread": 1.6, "dmg": 0.4,
		"zombie_hp": 0.5, "zombie_speed": 0.8, "zombie_rate": 2.0, "zombie_cap": 8, "boss_hp": 0.4, "bosses": 1,
		"regen_delay": 2.5, "regen_rate": 25.0, "hostage_hits": 5, "heal_every": 8.0, "heal_drops": 1, "score": 0.6,
	},
	"normal": {
		"name": "中级", "tag": "特警", "color": Color("FFC93C"), "stars": 2,
		"desc": ["匪徒 11 名，标准血量", "你有 100 血，标准伤害", "僵尸最多 16 只 + 1 只鼠王", "人质挨 3 下失败"],
		"bandits": 1, "player_hp": 100.0,
		"enemy_hp": 1.0, "enemy_speed": 1.0, "tele": 1.0, "atk_cd": 1.0, "burst": 0,
		"bullet_speed": 1.0, "spread": 1.0, "dmg": 1.0,
		"zombie_hp": 1.0, "zombie_speed": 1.0, "zombie_rate": 1.0, "zombie_cap": 16, "boss_hp": 1.0, "bosses": 1,
		"regen_delay": 5.0, "regen_rate": 12.0, "hostage_hits": 3, "heal_every": 13.0, "heal_drops": 2, "score": 1.0,
	},
	"hard": {
		"name": "高级", "tag": "王牌", "color": Color("FF8A3D"), "stars": 4,
		"desc": ["匪徒 16 名，血量 ×1.7，4 连发", "你 130 血，受伤 ×1.25，回血慢", "僵尸最多 26 只 + 2 只鼠王", "人质挨 2 下失败"],
		"bandits": 2, "player_hp": 130.0,
		"enemy_hp": 1.7, "enemy_speed": 1.15, "tele": 0.85, "atk_cd": 0.9, "burst": 1,
		"bullet_speed": 1.15, "spread": 0.85, "dmg": 1.25,
		"zombie_hp": 1.8, "zombie_speed": 1.2, "zombie_rate": 0.6, "zombie_cap": 26, "boss_hp": 1.6, "bosses": 2,
		"regen_delay": 7.0, "regen_rate": 7.0, "hostage_hits": 2, "heal_every": 16.0, "heal_drops": 3, "score": 1.5,
	},
	"insane": {
		"name": "鬼畜", "tag": "地狱", "color": Color("E63946"), "stars": 5,
		"desc": ["匪徒 23 名，血量 ×3，5 连发", "你只有 90 血，受伤 ×1.8", "僵尸最多 34 只 + 3 只鼠王", "误伤人质 1 下就失败"],
		"bandits": 3, "player_hp": 90.0,
		"enemy_hp": 3.0, "enemy_speed": 1.4, "tele": 0.45, "atk_cd": 0.45, "burst": 2,
		"bullet_speed": 1.4, "spread": 0.5, "dmg": 1.8,
		"zombie_hp": 2.6, "zombie_speed": 1.45, "zombie_rate": 0.4, "zombie_cap": 34, "boss_hp": 2.2, "bosses": 3,
		"regen_delay": 9.0, "regen_rate": 5.0, "hostage_hits": 1, "heal_every": 22.0, "heal_drops": 4, "score": 2.2,
	},
}
const SETTINGS_FILE := "user://settings.cfg"
var difficulty := "normal"
## 触屏模式：手机/平板自动开启，电脑上可用 -- --touch 预览
var touch := false
var _forced_touch := false
var _web_input_mode: JavaScriptObject
var _web_mode_callback: JavaScriptObject
## 触摸调试叠层（网页 ?debug=touch / 命令行 --touchdebug）
var touch_debug := false
## 流畅画质：手机和网页默认开启。关掉实时阴影、SSAO、动态点光源（用自发光和环境光代替），
## 这几项在手机 GPU / 网页的 Compatibility 渲染器上最贵（每盏点光会让被照到的物体多画一遍）。
## 电脑上可用 -- --lite 预览，-- --hq 强制精美画质。
var lite := false
var run := {}
var autotest := false
var shots_dir := ""

var _bt_left := 0.0
var _hitstop_left := 0.0
var _last_ticks := 0
var _busy := false
var _layer: CanvasLayer
var _cover: ColorRect
var _tapes: Array[Control] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_build_transition()
	_build_rotate_hint()
	_setup_cursor()
	_last_ticks = Time.get_ticks_usec()
	Sfx.set_volume("SFX", settings.sfx)
	Sfx.set_volume("Music", settings.music)
	var args := OS.get_cmdline_user_args()
	autotest = args.has("--autotest")
	# Touch capability is not the active input mode: Windows hybrids can expose
	# touch APIs while using a mouse. The Web bridge observes real input changes.
	_forced_touch = args.has("--touch")
	if OS.has_feature("web"):
		_web_input_mode = JavaScriptBridge.get_interface("pawInput")
		touch = _forced_touch or _web_has_touch()
		if _web_input_mode:
			_web_mode_callback = JavaScriptBridge.create_callback(_on_web_input_mode)
			_web_input_mode.onModeChange(_web_mode_callback)
	else:
		touch = _forced_touch or OS.has_feature("mobile")
	_load_settings()
	touch_debug = args.has("--touchdebug")
	lite = OS.has_feature("web") or OS.has_feature("mobile") or args.has("--lite")
	if args.has("--hq"):
		lite = false
	if lite:
		# 物理 30 次/秒 + 物理插值：游戏逻辑（AI、移动、子弹）的 CPU 开销减半，画面照样按屏幕刷新率顺滑移动。
		# 追帧上限 3：10 FPS 的设备也能保持正常速度；再慢就只是略微变慢，不会出现「一帧里补算 12 次物理 → 更卡」的死循环。
		Engine.physics_ticks_per_second = 30
		Engine.max_physics_steps_per_frame = 3
		get_tree().physics_interpolation = true
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		touch_debug = touch_debug or (q is String and String(q).contains("debug=touch"))
	for a in args:
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
		if a.begins_with("--diff="):
			set_difficulty(a.substr(7), false)


# ------------------------------------------------------------------ 难度

## 当前难度的某个参数（倍率 / 数值）
func dv(key: String) -> float:
	return float(DIFFS[difficulty][key])


func diff_info(d := "") -> Dictionary:
	return DIFFS[d if DIFFS.has(d) else difficulty]


func set_difficulty(d: String, save := true) -> void:
	if not DIFFS.has(d):
		return
	difficulty = d
	if save:
		save_settings()


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_FILE) != OK:
		return
	for k in settings.keys():
		settings[k] = cf.get_value("settings", k, settings[k])
	var d := String(cf.get_value("game", "difficulty", "normal"))
	if DIFFS.has(d):
		difficulty = d
	Sfx.set_volume("SFX", settings.sfx)
	Sfx.set_volume("Music", settings.music)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.set_value("game", "difficulty", difficulty)
	cf.save(SETTINGS_FILE)


func boot(c: Node) -> void:
	container = c
	if autotest:
		var t: Node = load("res://scripts/test/autotest.gd").new()
		add_child(t)
	_show("menu", {})


# The bridge combines primary-pointer/mobile hints, then real input. Never use
# DisplayServer touch availability or maxTouchPoints alone as a mobile flag.
func _web_has_touch() -> bool:
	if _web_input_mode:
		return bool(_web_input_mode.usesTouch())
	return OS.has_feature("web_android") or OS.has_feature("web_ios")


func _on_web_input_mode(arguments: Array) -> void:
	if not arguments.is_empty():
		set_touch_mode(bool(arguments[0]))


func set_touch_mode(enabled: bool) -> void:
	if _forced_touch or touch == enabled:
		return
	touch = enabled
	input_mode_changed.emit(touch)
	_check_rotate()
	if current is Level and not get_tree().paused and not (current as Level).finished:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if touch else Input.MOUSE_MODE_HIDDEN


func _input(event: InputEvent) -> void:
	# Web mode changes happen in DOM capture before Godot receives the original
	# event. Do not mistake the browser's compatibility mouse event for a mouse.
	if _web_input_mode or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch and event.pressed:
		set_touch_mode(true)
	elif event is InputEventMouseButton and event.pressed:
		set_touch_mode(false)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_SHIFT, KEY_R, KEY_Q, KEY_E, KEY_F, KEY_G, KEY_TAB, KEY_X, KEY_ESCAPE, KEY_P, KEY_ENTER, KEY_KP_ENTER]:
			set_touch_mode(false)


# ------------------------------------------------------------------ 输入

func _setup_input() -> void:
	_key("move_up", [KEY_W, KEY_UP])
	_key("move_down", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("roll", [KEY_SPACE, KEY_SHIFT])
	_key("reload", [KEY_R])
	_key("skill", [KEY_Q])
	_key("interact", [KEY_E, KEY_F])
	_key("grenade", [KEY_G])
	_key("switch", [KEY_TAB, KEY_X])
	_mouse("switch", MOUSE_BUTTON_WHEEL_DOWN)
	_key("pause", [KEY_ESCAPE, KEY_P])
	_key("confirm", [KEY_ENTER, KEY_KP_ENTER])
	_mouse("shoot", MOUSE_BUTTON_LEFT)
	_mouse("aim", MOUSE_BUTTON_RIGHT)


func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


## 菜单里的鼠标指针：小肉垫
func _setup_cursor() -> void:
	var n := 40
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var pads := [[Vector2(20, 26), 9.5], [Vector2(9, 15), 4.6], [Vector2(16, 8), 4.8], [Vector2(25, 8), 4.8], [Vector2(32, 15), 4.6]]
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var col := Color(0, 0, 0, 0)
			for pd in pads:
				var d: float = p.distance_to(pd[0])
				var r: float = pd[1]
				if d < r + 2.2:
					col = Pal.INK
			for pd in pads:
				var d2: float = p.distance_to(pd[0])
				if d2 < pd[1]:
					col = Pal.ORANGE
			img.set_pixel(x, y, col)
	Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img), Input.CURSOR_ARROW, Vector2(16, 4))
	Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img), Input.CURSOR_POINTING_HAND, Vector2(16, 4))


## 手机震动反馈
func vibrate(ms: int) -> void:
	if touch and bool(settings.vibrate) and (OS.has_feature("mobile") or OS.has_feature("web_android")):
		Input.vibrate_handheld(ms)


## 安卓返回键 / 切到后台
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if current is Level:
			var lv := current as Level
			if lv.pause_menu.is_open():
				lv.pause_menu.close()
			elif not lv.finished:
				lv.pause_menu.open()
		elif current is MainMenu:
			get_tree().quit()
		elif current != null:
			goto("menu")
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if current is Level and not (current as Level).finished and not autotest:
			(current as Level).pause_menu.open()


# ------------------------------------------------------------------ 时间控制

func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	var real := minf((now - _last_ticks) / 1000000.0, 0.1)
	_last_ticks = now
	_check_rotate()
	if get_tree().paused:
		return
	if _hitstop_left > 0.0:
		_hitstop_left -= real
	if _bt_left > 0.0:
		_bt_left -= real
		if _bt_left <= 0.0:
			_bt_left = 0.0
			Sfx.muffle(false)
			bullet_time_changed.emit(false)
	_apply_scale()


func _apply_scale() -> void:
	var s := 1.0
	if _bt_left > 0.0:
		s *= BT_SCALE
	if _hitstop_left > 0.0:
		s *= 0.04
	Engine.time_scale = s


## 顿帧：命中/击倒的瞬间冻结几十毫秒
var _last_hitstop := 0


func hitstop(dur: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hitstop < 350:
		return
	_last_hitstop = now
	_hitstop_left = maxf(_hitstop_left, minf(dur, 0.06))
	_apply_scale()


func bullet_time(dur: float) -> void:
	var was := _bt_left > 0.0
	_bt_left = maxf(_bt_left, dur)
	Sfx.muffle(true)
	if not was:
		bullet_time_changed.emit(true)
	_apply_scale()


func in_bullet_time() -> bool:
	return _bt_left > 0.0


## 玩家在子弹时间里比世界快
func player_time_mult() -> float:
	if _bt_left > 0.0 and _hitstop_left <= 0.0:
		return BT_PLAYER_SPEED / BT_SCALE
	return 1.0


func shake(amount: float) -> void:
	shake_requested.emit(amount * float(settings.shake))
	if amount >= 0.3:
		vibrate(int(clampf(amount * 60.0, 15.0, 60.0)))


func reset_time() -> void:
	_bt_left = 0.0
	_hitstop_left = 0.0
	Engine.time_scale = 1.0
	Sfx.muffle(false)


# ------------------------------------------------------------------ 本局统计

func new_run() -> void:
	run = {
		"time": 0.0, "shots": 0, "hits": 0, "downs": 0, "cuffs": 0, "perfect": 0,
		"damage": 0.0, "hostage_hits": 0, "rescued": false, "score": 0, "dodges": 0,
		"zombies": 0, "boss": false, "run_ms": 0, "difficulty": difficulty, "heal_drops": 0,
	}


func add_score(pts: int) -> void:
	run.score = int(run.get("score", 0)) + pts


func final_score() -> Dictionary:
	var acc := 0.0
	if int(run.shots) > 0:
		acc = float(run.hits) / float(run.shots)
	var s := int(run.downs) * 100 + int(run.cuffs) * 150 + int(run.perfect) * 50
	if run.rescued:
		s += 500 if int(run.hostage_hits) == 0 else 200
	s += int(run.get("zombies", 0)) * 20 + (500 if bool(run.get("boss", false)) else 0)
	var time_bonus := maxi(0, int(600 - float(run.time) * 2.0))
	s += time_bonus
	s += int(acc * 500.0)
	s -= int(float(run.damage) * 2.0)
	s = maxi(s, 0)
	s = int(s * float(diff_info(String(run.get("difficulty", difficulty))).score))
	var rating := "C"
	if s >= 4500:
		rating = "S"
	elif s >= 3400:
		rating = "A"
	elif s >= 2300:
		rating = "B"
	return {"score": s, "accuracy": acc, "rating": rating, "time_bonus": time_bonus}


# ------------------------------------------------------------------ 界面切换

func goto(screen: String, data := {}) -> void:
	if _busy:
		return
	_busy = true
	Sfx.play("paper", -6.0)
	await _tape(true)
	get_tree().paused = false
	reset_time()
	_show(screen, data)
	await get_tree().process_frame
	await _tape(false)
	_busy = false


func _show(screen: String, data: Dictionary) -> void:
	if current and is_instance_valid(current):
		current.queue_free()
	current = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	match screen:
		"menu":
			current = MainMenu.new()
		"briefing":
			current = Briefing.new()
		"leaderboard":
			current = LeaderboardScreen.new()
		"level":
			current = Level.new()
		"results":
			var r := Results.new()
			r.data = data
			current = r
	current.name = screen.capitalize()
	container.add_child(current)


## 警戒线转场：三条黄黑胶带交错扫过
## 手机竖着拿时（网页版无法锁定横屏）提示横屏
var _rotate: Control


func _build_rotate_hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_rotate = ColorRect.new()
	(_rotate as ColorRect).color = Pal.NAVY_DARK
	Style.full_rect(_rotate)
	_rotate.mouse_filter = Control.MOUSE_FILTER_STOP
	_rotate.visible = false
	layer.add_child(_rotate)
	var l := Style.label("请把手机横过来玩", 72, Pal.CREAM, Style.title_font(), 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Style.full_rect(l)
	_rotate.add_child(l)


func _check_rotate() -> void:
	if _rotate == null:
		return
	if not touch:
		_rotate.visible = false
		return
	var s := get_viewport().get_visible_rect().size
	var portrait := s.y > s.x * 1.05
	if portrait != _rotate.visible:
		_rotate.visible = portrait
	# A level can start after the portrait overlay was already shown in a menu.
	# Check the current level as well as the orientation change itself.
	if current is Level and portrait and not (current as Level).finished:
		if not (current as Level).pause_menu.is_open():
			(current as Level).pause_menu.open()


func _build_transition() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_cover = ColorRect.new()
	_cover.color = Pal.NAVY_DARK
	Style.full_rect(_cover)
	_cover.modulate.a = 0.0
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_cover)
	for i in 3:
		var tape := Control.new()
		tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tape.size = Vector2(3400, 150)
		tape.pivot_offset = tape.size * 0.5
		tape.rotation = deg_to_rad(-9.0 if i != 1 else 7.0)
		var band := Style.shader_rect("res://shaders/tape.gdshader", {"size": tape.size})
		tape.add_child(band)
		var txt := "  POLICE LINE  ·  警戒线  ·  请勿越过  ·  DO NOT CROSS  ·  P.A.W. S.W.A.T.  ·  警戒线  ·  请勿越过  ·  POLICE LINE  ·  DO NOT CROSS  "
		var l := Style.label(txt, 54, Pal.INK, Style.title_font())
		l.position = Vector2(0, 34)
		tape.add_child(l)
		tape.visible = false
		_layer.add_child(tape)
		_tapes.append(tape)


func _tape(cover_in: bool) -> void:
	var vp := Vector2(1920, 1080)
	if container and container.get_viewport():
		vp = container.get_viewport().get_visible_rect().size
	var ys := [vp.y * 0.2, vp.y * 0.5, vp.y * 0.8]
	var tw := create_tween().set_parallel().set_ignore_time_scale(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for i in 3:
		var tape := _tapes[i]
		tape.visible = true
		var from_left := i % 2 == 0
		var center := Vector2(vp.x * 0.5 - tape.size.x * 0.5, ys[i] - tape.size.y * 0.5)
		var off := Vector2(-tape.size.x - 200 if from_left else vp.x + 200, center.y)
		var exit := Vector2(vp.x + 200 if from_left else -tape.size.x - 200, center.y)
		if cover_in:
			tape.position = off
			tw.tween_property(tape, "position", center, 0.32).set_delay(i * 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			tape.position = center
			tw.tween_property(tape, "position", exit, 0.34).set_delay(0.08 + i * 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if cover_in:
		_cover.mouse_filter = Control.MOUSE_FILTER_STOP
		tw.tween_property(_cover, "modulate:a", 1.0, 0.3).set_delay(0.1)
	else:
		tw.tween_property(_cover, "modulate:a", 0.0, 0.3)
	await tw.finished
	if not cover_in:
		_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for t in _tapes:
			t.visible = false
