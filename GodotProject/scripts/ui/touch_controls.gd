class_name TouchControls
extends Control
## 手机 / 平板触屏操作（参考元气骑士 + 荒野乱斗）
##
##   左侧按住拖动        = 浮动移动摇杆
##   右下按住（任意位置）= 浮动开火摇杆
##       · 不拖动：自动锁定目标开火（锁定后不乱跳，敌人脚下有锁定框）
##       · 拖动：手动精准瞄准（透视已修正，指哪打哪；带轻微吸附）
##   点屏幕上的敌人      = 切换锁定目标
##   翻滚 / 冲撞 / 换弹 / 互动（破门、解救有目标时出现）/ 暂停
##
## 两种操作方案（暂停菜单切换）：
##   lock    智能锁定（默认）：按住即射，拖动手动瞄准时持续射击
##   release 松手射击：拖动只显示瞄准线，松手打出一轮
## 输出写入 Player.bot（虚拟输入），与键鼠共用一套角色逻辑。

const STICK_R := 120.0
const DEADZONE := 0.12
const MANUAL_DRAG := 42.0
const LOCK_RANGE := 13.5
const RADII := {"roll": 78.0, "skill": 78.0, "reload": 62.0, "interact": 88.0, "pause": 52.0, "weapon": 60.0, "grenade": 62.0}

var level: Level
## 自动测试机器人接管时设为 false
var drive := true
var lock: Node3D

# Web Touch.identifier is a signed long; -1 is a valid contact, not an idle flag.
var _move_active := false
var _fire_active := false
var _move_idx := -1
var _move_origin := Vector2.ZERO
var _move_pos := Vector2.ZERO
var _fire_idx := -1
var _fire_origin := Vector2.ZERO
var _fire_pos := Vector2.ZERO
var _manual := false
var _btn_idx := {}
var _flash := {}
var _just := {}
var _t := 0.0
var _aim_dir := Vector3.ZERO
var _burst_t := 0.0
var _burst_dir := Vector3.ZERO
var _burst_lock := false
var _hostage_hint := false
var _cand: Node3D
var _cand_t := 0.0
## 触摸调试（网页地址加 ?debug=touch，或命令行 --touchdebug）：画出每根手指 + 最近的事件
var _dbg := false
var _dbg_touches := {}
var _dbg_log: Array[String] = []
var _web_input: JavaScriptObject
var _web_revision := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dbg = Game.touch_debug
	if OS.has_feature("web"):
		_web_input = JavaScriptBridge.get_interface("pawInput")


func set_enabled(enabled: bool) -> void:
	release_all()
	visible = enabled
	set_process(enabled)
	if drive and level and level.player:
		level.player.bot_enabled = enabled
		level.player.lock_target = null
	lock = null
	_cand = null
	_cand_t = 0.0


func _dbg_event(t: String) -> void:
	_dbg_log.append(t)
	if _dbg_log.size() > 8:
		_dbg_log.pop_front()


func centers() -> Dictionary:
	var w := size.x
	var h := size.y
	return {
		"fire": Vector2(w - 270, h - 265),
		"roll": Vector2(w - 555, h - 118),
		"skill": Vector2(w - 575, h - 340),
		"reload": Vector2(w - 430, h - 505),
		"interact": Vector2(w - 220, h - 560),
		"pause": Vector2(w - 72, 72),
		"weapon": Vector2(w - 80, h - 450),
		"grenade": Vector2(w - 760, h - 230),
	}


func _interactable() -> Node:
	return level.best_interactable() if level else null


func _button_visible(b: String) -> bool:
	if level == null or level.player == null:
		return false
	match b:
		"interact":
			return _interactable() != null
		"weapon":
			return not level.player.arsenal.is_empty()
		"grenade":
			return level.player.grenades > 0
		"reload":
			return level.player.weapon == "rifle"
	return true


func _hit_button(p: Vector2) -> String:
	var c := centers()
	for k in RADII:
		if _button_visible(k) and p.distance_to(c[k]) < float(RADII[k]) * 1.25:
			return k
	return ""


func _prune_buttons() -> void:
	for id in _btn_idx.keys():
		var b: String = _btn_idx[id]
		if not _button_visible(b):
			_btn_idx.erase(id)
			var action := "switch" if b == "weapon" else b
			_just.erase(action)
			if drive:
				level.player.bot["just_" + action] = false


## 屏幕上点到的敌人
func _enemy_at(p: Vector2) -> Node3D:
	var cam := level.cam.cam
	var best: Node3D = null
	var bd := 95.0
	for e in level.targets():
		var sp := cam.unproject_position(e.center())
		var d := sp.distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best


func _in_fire_zone(p: Vector2) -> bool:
	return p.x > size.x * 0.5 and p.y > size.y * 0.3


func _input(event: InputEvent) -> void:
	# Native hybrid fallback. Activate before processing the first genuine
	# contact, without replaying it or turning emulated mouse touches into mobile.
	if not Game.touch and event is InputEventScreenTouch and event.pressed \
		and event.device != InputEvent.DEVICE_ID_EMULATION:
		Game.set_touch_mode(true)
	if level == null or level.player == null or get_tree().paused or not drive \
		or not is_visible_in_tree() or level.finished or level.player.dead \
		or size.y > size.x * 1.05:
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed and not p.is_finite():
			_end_contact(event.index, true)
			return
		if event.pressed:
			# A reused ID must release its old zone before the new press is recorded.
			_end_contact(event.index, true)
		if _dbg:
			if event.pressed:
				_dbg_touches[event.index] = p
			else:
				_dbg_touches.erase(event.index)
			_dbg_event("%s #%d (%d,%d) move=%d fire=%d" % ["按下" if event.pressed else ("取消" if event.canceled else "抬起"), event.index, p.x, p.y, _move_idx, _fire_idx])
		if event.pressed:
			var b := _hit_button(p)
			if b != "":
				_btn_idx[event.index] = b
				_press(b)
			elif not _in_fire_zone(p) and p.x > size.x * 0.4 and _enemy_at(p) != null:
				lock = _enemy_at(p)
				Game.vibrate(15)
				Sfx.play("telegraph", -8.0, 1.6)
			elif p.x > size.x * 0.5:
				# 新手指直接接管开火键：iOS 偶尔会丢“抬起”事件，不接管的话开火键会一直卡住
				_fire_active = true
				_fire_idx = event.index
				_fire_origin = p
				_fire_pos = p
				_manual = false
				Game.vibrate(8)
			else:
				# 同理：左半屏的新手指总是接管摇杆
				_move_active = true
				_move_idx = event.index
				_move_origin = p
				_move_pos = p
			get_viewport().set_input_as_handled()
		else:
			var canceled: bool = event.canceled
			# The 4.6 Web runtime sends touchcancel as an ordinary release.
			if _web_input:
				canceled = bool(_web_input.consumeCancel(event.index)) or canceled
			_end_contact(event.index, canceled)
	elif event is InputEventScreenDrag:
		if not event.position.is_finite():
			return
		if _dbg:
			_dbg_touches[event.index] = event.position
		if _move_active and event.index == _move_idx:
			_move_pos = event.position
		elif _fire_active and event.index == _fire_idx:
			_fire_pos = event.position
			if not _manual and _fire_pos.distance_to(_fire_origin) > MANUAL_DRAG:
				_manual = true


func _end_contact(id: int, canceled: bool) -> void:
	if _move_active and id == _move_idx:
		_move_active = false
		_move_idx = -1
		if drive:
			level.player.bot["move"] = Vector2.ZERO
	if _fire_active and id == _fire_idx:
		if canceled:
			_burst_t = 0.0
			if drive:
				level.player.bot["shoot"] = false
		else:
			_release_fire()
		_fire_active = false
		_fire_idx = -1
	_btn_idx.erase(id)
	_dbg_touches.erase(id)



func _press(b: String) -> void:
	_flash[b] = 1.0
	Game.vibrate(12)
	if b == "pause":
		level.pause_menu.open()
	elif b == "weapon":
		_just["switch"] = true
	else:
		_just[b] = true


## 松手射击模式：放开开火摇杆时打出一轮
func _release_fire() -> void:
	if Game.settings.get("aim_mode", "lock") != "release":
		return
	_burst_t = _burst_len()
	if _manual and _aim_dir != Vector3.ZERO:
		_burst_dir = _aim_dir
		_burst_lock = false
	else:
		_burst_lock = true


func _burst_len() -> float:
	match level.player.weapon:
		"shotgun", "rocket":
			return 0.05
		"laser":
			return 0.7
		"gatling":
			return 0.5
	return 0.36


func release_all() -> void:
	lock = null
	_cand = null
	_cand_t = 0.0
	_move_active = false
	_fire_active = false
	_move_idx = -1
	_fire_idx = -1
	_burst_t = 0.0
	_btn_idx.clear()
	_just.clear()
	_manual = false
	_dbg_touches.clear()
	if _web_input:
		_web_input.reset()
	# Pausable nodes do not process while paused: clear action cache now.
	if drive and level and level.player:
		level.player.lock_target = null
		var b := level.player.bot
		b["move"] = Vector2.ZERO
		b["shoot"] = false
		b["aim"] = false
		for k in b.keys():
			if String(k).begins_with("just_"):
				b[k] = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		release_all()
	elif what == NOTIFICATION_RESIZED and is_node_ready():
		# Rotation/resize changes the joystick coordinate space.
		release_all()


func _process(delta: float) -> void:
	var rd := HudWidgets.real_delta(delta)
	_t += rd
	for k in _flash.keys():
		_flash[k] = maxf(0.0, float(_flash[k]) - rd * 4.0)
	if level == null or level.player == null:
		return
	if level.finished or level.player.dead or not is_visible_in_tree() or size.y > size.x * 1.05:
		release_all()
		return
	if not is_instance_valid(_cand) or _cand.is_queued_for_deletion():
		_cand = null
	_prune_buttons()
	if _web_input:
		# One integer read per rendered frame; owner reconciliation only after
		# a DOM touch/lifecycle change. No per-frame JSON dump or event replay.
		var revision := int(_web_input.revision())
		if revision != _web_revision:
			_web_revision = revision
			if bool(_web_input.observed()):
				if _move_active and not bool(_web_input.isActive(_move_idx)):
					_end_contact(_move_idx, true)
				if _fire_active and not bool(_web_input.isActive(_fire_idx)):
					_end_contact(_fire_idx, true)
				for id in _btn_idx.keys():
					if not bool(_web_input.isActive(id)):
						_end_contact(id, true)
	if _move_active:
		var v := _move_pos - _move_origin
		if v.length() > STICK_R:
			_move_origin = _move_pos - v.normalized() * STICK_R
	_burst_t -= rd
	if drive:
		_feed()
	queue_redraw()


# ------------------------------------------------------------------ 瞄准逻辑

func _feed() -> void:
	var p := level.player
	p.bot_enabled = true
	var b := p.bot
	var mv := Vector2.ZERO
	if _move_active:
		mv = ((_move_pos - _move_origin) / STICK_R).limit_length(1.0)
		if mv.length() < DEADZONE:
			mv = Vector2.ZERO
	b["move"] = mv

	var release_mode: bool = Game.settings.get("aim_mode", "lock") == "release"
	var holding := _fire_active
	var shoot := false
	_aim_dir = Vector3.ZERO
	if not _valid(lock):
		lock = null
	if holding and _manual:
		var dv := _fire_pos - _fire_origin
		_aim_dir = _soft_assist(level.cam.screen_to_ground(dv.normalized()))
		shoot = not release_mode
	elif holding and not release_mode:
		_aim_dir = _lock_dir()
		shoot = true
	elif _burst_t > 0.0:
		_aim_dir = _lock_dir() if _burst_lock else _burst_dir
		shoot = true
	b["shoot"] = shoot
	b["aim"] = false
	p.lock_target = lock if (shoot and not _manual) else null
	if _aim_dir == Vector3.ZERO:
		b["aim_point"] = p.global_position + p.facing * 3.0
	else:
		b["aim_point"] = p.global_position + _aim_dir * 6.0
	for k in _just:
		b["just_" + String(k)] = true
	_just.clear()


func _valid(e: Variant) -> bool:
	# A despawned target is a freed Object, which cannot be passed to a typed
	# Node3D argument. Validate the Variant before any cast or method call.
	if not is_instance_valid(e) or not e is Node3D or e.is_queued_for_deletion() or not e.is_active():
		return false
	if e is Enemy and not level.zone_active((e as Enemy).zone):
		return false
	return e.global_position.distance_to(level.player.global_position) < LOCK_RANGE + 2.0


## 锁定方向：已有锁定且仍可打 → 继续打它；否则挑一个新的
func _lock_dir() -> Vector3:
	var p := level.player
	if not _valid(lock) or not _can_hit(lock):
		lock = _pick_target()
	if _valid(lock) and _can_hit(lock):
		var d := lock.global_position - p.global_position
		d.y = 0
		return d.normalized()
	return p.facing


func _can_hit(e: Variant) -> bool:
	if not _valid(e):
		return false
	var p := level.player
	return level.clear_shot(p.global_position + Vector3(0, Bullet.HEIGHT, 0), e.global_position + Vector3(0, Bullet.HEIGHT, 0)) \
		and _hostage_safe(e)


## 射线是否会擦到人质（人质附近的敌人不自动锁定，需要手动瞄准）
func _hostage_safe(e: Node3D) -> bool:
	var h := level.hostage
	if h == null or h.state in ["rescued", "evac", "gone"]:
		return true
	var a := level.player.global_position
	var b := e.global_position
	var hp := h.global_position
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(hp.x - a.x, hp.z - a.z)
	# 打偏的子弹会继续飞，所以检查到目标后方 8m
	var over := 1.0 + 8.0 / maxf(ab.length(), 0.5)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, over)
	var dist := (ap - ab * t).length()
	var ok := dist > 1.0 and Vector2(hp.x - b.x, hp.z - b.z).length() > 1.4
	if not ok and not _hostage_hint:
		_hostage_hint = true
		level.hud.toast("人质在旁边 —— 拖动开火键手动瞄准！")
	return ok


## 选目标：距离为主，优先面前的，避免突然转身打背后
func _pick_target() -> Node3D:
	var p := level.player
	var best: Node3D = null
	var bs := 1e9
	for e in level.targets():
		var to: Vector3 = e.global_position - p.global_position
		to.y = 0
		var d := to.length()
		if d > LOCK_RANGE or not _can_hit(e):
			continue
		var front := p.facing.dot(to / maxf(d, 0.01))
		var score := d * (1.0 + 0.35 * (1.0 - front))
		if score < bs:
			bs = score
			best = e
	return best


## 手动瞄准的轻微吸附：只在 7° 以内，平滑拉近而不是瞬间吸过去
func _soft_assist(dir: Vector3) -> Vector3:
	var p := level.player
	var best := dir
	var ba := deg_to_rad(7.0)
	for e in level.targets():
		var to: Vector3 = e.global_position - p.global_position
		to.y = 0
		if to.length() > LOCK_RANGE:
			continue
		var a := dir.angle_to(to.normalized())
		if a < ba:
			ba = a
			best = dir.slerp(to.normalized(), 0.6)
	return best.normalized()


# ------------------------------------------------------------------ 绘制

func _reticle(e: Node3D, col: Color, strong: bool) -> void:
	var cam := level.cam.cam
	var c := cam.unproject_position(e.global_position + Vector3(0, 0.05, 0))
	var r := (46.0 if strong else 40.0) * (2.0 if (e is Zombie and (e as Zombie).boss) else 1.0)
	var rot := _t * (3.0 if strong else 1.0)
	for i in 4:
		var a := rot + i * PI / 2.0
		var p0 := c + Vector2(cos(a - 0.35), sin(a - 0.35) * 0.55) * r
		var p1 := c + Vector2(cos(a), sin(a) * 0.55) * r
		var p2 := c + Vector2(cos(a + 0.35), sin(a + 0.35) * 0.55) * r
		draw_polyline(PackedVector2Array([p0, p1, p2]), Pal.INK, 9.0 if strong else 6.0)
		draw_polyline(PackedVector2Array([p0, p1, p2]), col, 5.0 if strong else 3.0)
	if strong:
		HudWidgets.text(self, Style.title_font(), c + Vector2(-50, -r * 0.55 - 10), "锁定", 24, col, HORIZONTAL_ALIGNMENT_CENTER, 100, 6)


func _draw() -> void:
	if _dbg:
		_draw_debug()
	if level == null or level.player == null or level.finished:
		return
	var p := level.player
	var c := centers()
	var f := Style.title_font()
	var cam := level.cam.cam
	var firing := _fire_active or _burst_t > 0.0
	# 锁定框：开火时红色实框，平时淡淡提示“下一个会打谁”
	if _valid(lock) and firing and not _manual:
		_reticle(lock, Pal.RED, true)
	elif not firing:
		# 候选目标每 0.15 秒算一次（射线检测较多）
		_cand_t -= get_process_delta_time()
		if _cand_t <= 0.0:
			_cand_t = 0.15
			_cand = lock if _valid(lock) and _can_hit(lock) else _pick_target()
		if _valid(_cand):
			_reticle(_cand, Color(1, 1, 1, 0.55), false)
		else:
			_cand = null
	# 瞄准线
	if (_fire_active and _manual) or (_burst_t > 0.0 and not _burst_lock):
		var dir := _aim_dir
		if dir != Vector3.ZERO:
			var o := p.global_position + Vector3(0, Bullet.HEIGHT, 0)
			var a := cam.unproject_position(o)
			var e := cam.unproject_position(o + dir * 9.0)
			var l := a.distance_to(e)
			var sd := (e - a) / maxf(l, 1.0)
			var d := 36.0
			var col := Pal.YELLOW if Game.settings.get("aim_mode", "lock") == "release" else Pal.ORANGE
			while d < l:
				draw_line(a + sd * d, a + sd * minf(d + 20.0, l), Pal.INK, 9.0)
				draw_line(a + sd * d, a + sd * minf(d + 20.0, l), col, 5.0)
				d += 32.0
			draw_circle(e, 12, Pal.INK)
			draw_circle(e, 8, col)
	# 移动摇杆
	if _move_active:
		var knob := _move_origin + (_move_pos - _move_origin).limit_length(STICK_R)
		draw_circle(_move_origin, STICK_R, Color(1, 1, 1, 0.1))
		draw_arc(_move_origin, STICK_R, 0, TAU, 48, Color(1, 1, 1, 0.45), 4.0)
		draw_circle(knob, 56, Pal.INK)
		draw_circle(knob, 50, Color(Pal.CREAM, 0.92))
	else:
		var hint := Vector2(280, size.y - 270)
		draw_arc(hint, STICK_R, 0, TAU, 48, Color(1, 1, 1, 0.22), 4.0)
		draw_circle(hint, 46, Color(1, 1, 1, 0.14))
		HudWidgets.text(self, f, hint + Vector2(-90, STICK_R + 44), "左手拖动 移动", 26, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 180)
	# 开火摇杆（浮动：按在哪就出现在哪）
	var w := Weapons.info(p.weapon)
	var wcol: Color = w.color if p.weapon != "rifle" else Pal.RED
	var fc: Vector2 = _fire_origin if _fire_active else c.fire
	var fr := 125.0
	draw_circle(fc, fr, Color(wcol, 0.42 if _fire_active else 0.28))
	draw_arc(fc, fr, 0, TAU, 64, Color(Pal.CREAM, 0.6), 5.0)
	if p.reloading:
		var pw := p.perfect_window()
		draw_arc(fc, fr + 14, 0, TAU, 64, Color(Pal.INK, 0.6), 12.0)
		draw_arc(fc, fr + 14, -PI / 2 + pw.x * TAU, -PI / 2 + pw.y * TAU, 20, Pal.YELLOW, 12.0)
		draw_arc(fc, fr + 14, -PI / 2, -PI / 2 + p.reload_progress() * TAU, 48, Pal.CREAM, 5.0)
	var knob2 := fc + (_fire_pos - fc).limit_length(fr - 30.0) if _fire_active else fc
	draw_circle(knob2, 58, Pal.INK)
	draw_circle(knob2, 52, wcol if p.weapon != "rifle" else (Pal.ORANGE if p.buff_t > 0.0 else Pal.CREAM))
	for v in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(knob2 + v * 14, knob2 + v * 34, Pal.INK, 6.0)
	draw_circle(knob2, 6, Pal.RED)
	var ammo_txt := ("%d" % p.special_ammo) if p.weapon != "rifle" else ("%d" % p.ammo)
	var label := (String(w.short) + " " + ammo_txt) if p.weapon != "rifle" else ammo_txt
	HudWidgets.text(self, Style.title_font() if p.weapon != "rifle" else Style.num_font(), fc + Vector2(-fr, fr + 46), label, 34,
		wcol if p.weapon != "rifle" else (Pal.RED if p.ammo <= 5 else Pal.CREAM), HORIZONTAL_ALIGNMENT_CENTER, fr * 2, 8)
	# 翻滚
	var rc: Vector2 = c.roll
	_round(rc, RADII.roll, Pal.TEAL, "roll", clampf(p.roll_cd / (Player.ROLL_TIME + Player.ROLL_CD), 0.0, 1.0))
	draw_arc(rc, 26, -PI * 0.9, PI * 0.6, 20, Pal.INK, 7)
	var tip := rc + Vector2(cos(PI * 0.6), sin(PI * 0.6)) * 26
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-14, -2), tip + Vector2(8, -12), tip + Vector2(5, 12)]), Pal.INK)
	HudWidgets.text(self, f, rc + Vector2(-60, 114), "翻滚", 28, Pal.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 120, 8)
	# 冲撞
	var sc: Vector2 = c.skill
	var cd01 := p.dash_cd / Player.DASH_CD
	_round(sc, RADII.skill, Pal.ORANGE, "skill", cd01)
	draw_rect(Rect2(sc + Vector2(12, -24), Vector2(11, 48)), Pal.INK)
	draw_colored_polygon(PackedVector2Array([sc + Vector2(-28, -7), sc + Vector2(-4, -7), sc + Vector2(-4, -18), sc + Vector2(9, 0), sc + Vector2(-4, 18), sc + Vector2(-4, 7), sc + Vector2(-28, 7)]), Pal.INK)
	if cd01 > 0.0:
		HudWidgets.text(self, Style.num_font(), sc + Vector2(-50, 16), "%d" % ceili(p.dash_cd), 44, Pal.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 100, 8)
	HudWidgets.text(self, f, sc + Vector2(-60, 114), "冲撞", 28, Pal.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 120, 8)
	# 换弹（只有步枪需要）
	if p.weapon == "rifle":
		var lc: Vector2 = c.reload
		var in_zone := false
		if p.reloading and not p.reload_tried:
			var pr := p.reload_t / Player.RELOAD_TIME
			in_zone = pr >= Player.PERFECT_A and pr <= Player.PERFECT_B
		var rcol := Pal.YELLOW if in_zone else (Pal.NAVY_LIGHT if not p.reloading else Pal.STEEL)
		if in_zone:
			draw_circle(lc, RADII.reload + 14 + sin(_t * 30.0) * 4.0, Color(Pal.YELLOW, 0.5))
		_round(lc, RADII.reload, rcol, "reload", 0.0)
		for i in 3:
			var cp := lc + Vector2(-20 + i * 20, 0)
			draw_rect(Rect2(cp + Vector2(-7, -13), Vector2(14, 26)), Pal.ORANGE if not p.reloading else Pal.CREAM)
			draw_rect(Rect2(cp + Vector2(-7, -13), Vector2(14, 26)), Pal.INK, false, 3.0)
		HudWidgets.text(self, f, lc + Vector2(-60, 98), "再点!" if in_zone else "换弹", 26, Pal.YELLOW if in_zone else Pal.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 120, 8)
	# 互动（有目标才出现）
	var it := _interactable()
	if it:
		var icc: Vector2 = c.interact
		var en: bool = it.interact_enabled()
		var lbl := "互动"
		if it is Door:
			lbl = "破门!" if en else "锁住"
		elif it is Hostage:
			lbl = "解救"
		var r: float = float(RADII.interact) * (1.0 + sin(_t * 8.0) * 0.06 if en else 1.0)
		if en:
			draw_circle(icc, r + 12, Color(Pal.ORANGE, 0.35))
		draw_circle(icc, r, Pal.INK)
		draw_circle(icc, r - 6, Pal.CREAM if en else Color("8A90A0"))
		if float(_flash.get("interact", 0.0)) > 0.0:
			draw_circle(icc, r - 6, Color(1, 1, 1, float(_flash.interact) * 0.6))
		HudWidgets.text(self, f, icc + Vector2(-r, 14), lbl, 40, Pal.INK, HORIZONTAL_ALIGNMENT_CENTER, r * 2)
	# 切换神装（有神装才出现）：圆心是当前武器的颜色，下面写武器名
	if not p.arsenal.is_empty():
		var wc: Vector2 = c.weapon
		var cur := Weapons.info(p.weapon)
		_round(wc, RADII.weapon, cur.color if p.weapon != "rifle" else Pal.CREAM, "weapon", 0.0)
		draw_arc(wc, 30, -PI * 0.95, -PI * 0.15, 12, Pal.INK, 6)
		draw_arc(wc, 30, PI * 0.05, PI * 0.85, 12, Pal.INK, 6)
		var a1 := wc + Vector2(cos(-PI * 0.15), sin(-PI * 0.15)) * 30
		draw_colored_polygon(PackedVector2Array([a1 + Vector2(-12, -4), a1 + Vector2(8, -4), a1 + Vector2(-2, 12)]), Pal.INK)
		var a2 := wc + Vector2(cos(PI * 0.85), sin(PI * 0.85)) * 30
		draw_colored_polygon(PackedVector2Array([a2 + Vector2(12, 4), a2 + Vector2(-8, 4), a2 + Vector2(2, -12)]), Pal.INK)
		HudWidgets.text(self, f, wc + Vector2(-70, 96), "切换 · " + String(cur.short), 24, cur.color if p.weapon != "rifle" else Pal.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 140, 8)
		# 拥有几把神装：小圆点
		var owned := p.owned_weapons()
		for i in owned.size():
			var dc := wc + Vector2((i - (owned.size() - 1) * 0.5) * 18.0, -RADII.weapon - 16)
			draw_circle(dc, 7 if owned[i] == p.weapon else 5, Weapons.info(owned[i]).color if owned[i] != "rifle" else Pal.CREAM)
	# 手雷（有手雷才出现）
	if p.grenades > 0:
		var gc: Vector2 = c.grenade
		_round(gc, RADII.grenade, Color("7EE081"), "grenade", 0.0)
		draw_rect(Rect2(gc + Vector2(-16, -18), Vector2(32, 40)), Color("3E8F45"))
		draw_rect(Rect2(gc + Vector2(-16, -4), Vector2(32, 10)), Pal.CREAM)
		draw_rect(Rect2(gc + Vector2(-16, -18), Vector2(32, 40)), Pal.INK, false, 4.0)
		draw_arc(gc + Vector2(8, -26), 8, 0, TAU, 12, Pal.ORANGE, 4)
		HudWidgets.text(self, Style.num_font(), gc + Vector2(14, 48), "×%d" % p.grenades, 30, Pal.CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		HudWidgets.text(self, f, gc + Vector2(-60, 98), "手雷", 26, Pal.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 120, 8)
	# 暂停
	var pc: Vector2 = c.pause
	draw_circle(pc, RADII.pause, Pal.INK)
	draw_circle(pc, RADII.pause - 5, Color(Pal.NAVY, 0.95))
	draw_rect(Rect2(pc + Vector2(-14, -16), Vector2(9, 32)), Pal.CREAM)
	draw_rect(Rect2(pc + Vector2(5, -16), Vector2(9, 32)), Pal.CREAM)


func _round(center: Vector2, r: float, col: Color, key: String, cd01: float) -> void:
	var ready := cd01 <= 0.0
	draw_circle(center, r, Pal.INK)
	draw_circle(center, r - 6, col if ready else Pal.NAVY)
	if cd01 > 0.0:
		var pts := PackedVector2Array([center])
		for i in 33:
			var a := -PI / 2 + TAU * cd01 * float(i) / 32.0
			pts.append(center + Vector2(cos(a), sin(a)) * (r - 6))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.45))
	var fl: float = _flash.get(key, 0.0)
	if fl > 0.0:
		draw_circle(center, r - 6, Color(1, 1, 1, fl * 0.6))


func _draw_debug() -> void:
	var f := Style.body_font()
	for i in _dbg_touches:
		var p: Vector2 = _dbg_touches[i]
		var col := Pal.TEAL if i == _move_idx else (Pal.RED if i == _fire_idx else Pal.YELLOW)
		draw_arc(p, 70, 0, TAU, 32, col, 6)
		HudWidgets.text(self, f, p + Vector2(-60, -84), "#%d" % i, 30, col, HORIZONTAL_ALIGNMENT_CENTER, 120, 6)
	var y := 150.0
	draw_rect(Rect2(Vector2(size.x * 0.5 - 380, y - 34), Vector2(760, 30 * _dbg_log.size() + 16)), Color(0, 0, 0, 0.55))
	for l in _dbg_log:
		HudWidgets.text(self, f, Vector2(size.x * 0.5 - 366, y), l, 22, Pal.CREAM)
		y += 30.0
