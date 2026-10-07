extends Node
## 自动测试：用 --autotest 启动（可加 --shots=目录 截图）。
## 机器人走完整个流程：菜单 → 简报 → 关卡（清场/破门/救人质）→ 结算，然后退出。

var _step := "boot"
var _t := 0.0
var _total := 0.0
var _shot_n := 0
var _level: Level
var _shots_taken := {}
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _reload_pressed := false
var _paused_once := false
var _path: PackedVector3Array = PackedVector3Array()
var _path_i := 0
var _path_goal := Vector3.INF


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[autotest] start")


func _shot(name: String) -> void:
	if Game.shots_dir == "" or _shots_taken.has(name):
		return
	_shots_taken[name] = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shot_n += 1
	var path := "%s/%02d_%s.png" % [Game.shots_dir, _shot_n, name]
	img.save_png(path)
	print("[autotest] screenshot ", path)


var _perf_last := 0
var _perf_hitches := 0
var _perf_max := 0.0
var _perf_frames := 0


## 帧耗时统计：超过 50ms 的帧记为一次卡顿
func _perf_tick() -> void:
	var now := Time.get_ticks_usec()
	if _perf_last > 0:
		var ms := (now - _perf_last) / 1000.0
		_perf_frames += 1
		_perf_max = maxf(_perf_max, ms)
		if ms > 50.0:
			_perf_hitches += 1
			var where := _step
			if is_instance_valid(_level) and Game.current == _level:
				where += " phase=%d t=%.1f wave_t=%.1f zombies=%d" % [_level.phase, _level.t, _level.wave_t, _level.zombies.size()]
			print("[hitch] ", snappedf(ms, 0.1), "ms @ ", where)
	_perf_last = now


var _gren_t := 0.0
var _switch_t := 5.0
var _tip_seen := {}
var _tip_on_since := -1.0


## 新手提示卡：记录出现 / 消失；同一张卡挂在屏幕上超过 15 秒算 BUG
func _tip_watch() -> void:
	if not is_instance_valid(_level) or not is_instance_valid(_level.hud):
		return
	var tc: TipCards = _level.hud.get("_tips")
	if tc == null:
		return
	var vis := tc.modulate.a > 0.01
	if vis and _tip_on_since < 0.0:
		_tip_on_since = _total
		print("[tip] show %s at %.1f" % [tc.get("_cur"), _total])
	elif not vis and _tip_on_since >= 0.0:
		print("[tip] hide after %.1fs" % (_total - _tip_on_since))
		_tip_on_since = -1.0
	elif vis and _total - _tip_on_since > 15.0 and not _tip_seen.has("stuck"):
		_tip_seen["stuck"] = true
		print("[tip] STUCK %s" % tc.get("_cur"))


func _process(delta: float) -> void:
	_perf_tick()
	_tip_watch()
	_t += delta
	_total += delta
	if _total > 400.0:
		print("[autotest] TIMEOUT step=", _step)
		get_tree().quit(2)
		return
	match _step:
		"boot":
			if _t > 1.6:
				_shot("menu")
				if OS.get_cmdline_user_args().has("--lbshot"):
					Game.goto("leaderboard")
					_next("lbshot")
				else:
					_next("to_brief")
		"lbshot":
			if _t > 4.0:
				_shot("leaderboard")
				_next("lbshot_local")
		"lbshot_local":
			if _t == delta:
				Game.current._switch("local")
			if _t > 1.5:
				_shot("leaderboard_local")
				_next("done")
		"to_brief":
			if _t > 0.3:
				Game.goto("briefing")
				_next("brief")
		"brief":
			if _t > 2.6:
				_shot("briefing")
				_next("to_level")
		"to_level":
			if _t > 0.3:
				Game.goto("level")
				_next("level_wait")
		"level_wait":
			if Game.current is Level and _t > 1.4:
				_level = Game.current
				_shot("street")
				if OS.get_cmdline_user_args().has("--perfprobe"):
					var pp: Node = load("res://scripts/test/perf_probe.gd").new()
					pp.set("level", _level)
					add_child(pp)
				if OS.get_cmdline_user_args().has("--wave"):
					# 直接跳到僵尸潮（截图 / 调试用）
					_level.player.global_position = Vector3(1.0, 0, 5.5)
					_level.player.reset_physics_interpolation()
					_level.cam.snap()
					for e in _level.enemies.duplicate():
						e.drop = ""
						e.take_hit(99.0, Vector3.FORWARD, Vector3.ZERO, null)
					_level.door.breachable = true
					_level.door.breach(_level.player.global_position)
					_level.hostage.state = "free"
					_level.hostage.rescue()
				if OS.get_cmdline_user_args().has("--touchtest"):
					_next("touch")
					_touch_test()
				else:
					_level.player.bot_enabled = true
					if _level.hud.touch:
						_level.hud.touch.drive = false
					_check_mouse()
					_next("play")
		"play":
			if is_instance_valid(_level) and int(_total) % 10 == 0 and int(_total) != int(_total - delta):
				var pl := _level.player
				for e in _level.enemies:
					if e.is_active() and e.zone != "staff":
						print("    enemy ", e.kind, " ", e.state, " at ", e.global_position.snappedf(0.1))
				print("[autotest] t=", int(_total), " phase=", _level.phase, " pos=", pl.global_position.snappedf(0.1), " hp=", int(pl.hp), " paused=", get_tree().paused, " ts=", Engine.time_scale)
			if not is_instance_valid(_level):
				_next("results_wait")
				return
			var cs = _level.get_node_or_null("Cutscene")
			if cs:
				if cs._f >= 46:
					_shot("cutscene_assemble")
				if cs._f >= 70:
					_shot("cutscene_equip")
				if cs._f >= 86:
					_shot("cutscene_fire")
			for e in _level.enemies:
				if e.state == "downed" and e.down_t < 12.0 and _level.phase <= 1:
					_shot("cuff_hint")
			if _level.wave_fired and _level.wave_t > 8.0:
				_shot("wave")
			if _level._boss_spawned > 0 and _level.wave_t > 31.0:
				_shot("boss")
			if OS.get_cmdline_user_args().has("--god") and is_instance_valid(_level.player):
				_level.player.hp = _level.player.max_hp
			if _level.finished:
				if not _shots_taken.has("finish"):
					_shot("finish")
				if Game.current is Results:
					_next("results_wait")
		"results_wait":
			if Game.current is Results and _t > 4.5:
				_shot("results")
				if Game.current.get("_lb_line2") != null:
					await get_tree().create_timer(1.5).timeout
					_shot("results_lb")
				print("[autotest] OUTCOME ", JSON.stringify((Game.current as Results).data))
				var r := Game.run
				print("[autotest] RESULT ", JSON.stringify(r))
				print("[autotest] FINAL ", JSON.stringify(Game.final_score()))
				var rs = Game.current
				if rs.get("_lb_line2") != null:
					print("[leaderboard] time=", rs._lb_time.text, " | ", rs._lb_line1.text, " | ", rs._lb_line2.text.replace("\n", " / "), " | badge=", rs._lb_badge.text)
				print("[perf] frames=", _perf_frames, " hitches(>50ms)=", _perf_hitches, " worst=", snappedf(_perf_max, 0.1), "ms")
				_next("done")
		"done":
			if _t > 0.5:
				get_tree().quit(0 if Game.current is Results and bool((Game.current as Results).data.get("success", false)) else 1)


func _next(s: String) -> void:
	print("[autotest] step ", s, " at ", snappedf(_total, 0.1))
	_step = s
	_t = 0.0


# ------------------------------------------------------------------ 机器人玩家

func _physics_process(delta: float) -> void:
	if _step != "play" or not is_instance_valid(_level) or _level.finished:
		return
	if get_tree().paused:
		return
	var p := _level.player
	if p.dead:
		return
	var bot := p.bot
	bot["move"] = Vector2.ZERO
	bot["shoot"] = false
	bot["aim"] = false

	if not _paused_once and _level.t > 6.0:
		_paused_once = true
		_level.pause_menu.open()
		await get_tree().create_timer(0.6, true, false, true).timeout
		await _shot("pause")
		_level.pause_menu._open_help()
		await get_tree().create_timer(0.4, true, false, true).timeout
		await _shot("help")
		_level.pause_menu.close()
		return

	# 完美换弹
	if p.reloading:
		var pr := p.reload_t / Player.RELOAD_TIME
		if not _reload_pressed and pr > 0.5:
			_reload_pressed = true
			bot["just_reload"] = true
	else:
		_reload_pressed = false

	var goal := Vector3.INF
	var shoot_at: Enemy = null

	match _level.phase:
		0, 1:
			var tgt := _nearest(func(e: Enemy): return e.zone != "staff" and e.is_active())
			var downed := _nearest(func(e: Enemy): return e.state == "downed")
			var threat := _nearest(func(e: Enemy): return e.is_active() and e.alerted and _level.zone_active(e.zone))
			if threat and threat.global_position.distance_to(p.global_position) < 8.0 and _can_shoot(p, threat):
				shoot_at = threat
			if downed and (threat == null or threat.global_position.distance_to(p.global_position) > 7.0):
				goal = downed.global_position
				if p.global_position.distance_to(downed.global_position) < 1.4:
					bot["just_interact"] = true
			elif tgt:
				if shoot_at == null and _can_shoot(p, tgt) and tgt.global_position.distance_to(p.global_position) < 9.0:
					shoot_at = tgt
				if shoot_at == null or p.global_position.distance_to(tgt.global_position) > 6.0:
					goal = tgt.global_position
		2:
			var dpos := Level.DOOR_POS + Vector3(0, 0, 1.4)
			goal = dpos
			if p.global_position.distance_to(dpos) < 0.9:
				goal = Vector3.INF
				bot["just_interact"] = true
		5:
			var gt := _level.guide_target()
			var zt: Node3D = null
			var zd := 1e9
			for z in _level.targets():
				var dd: float = z.global_position.distance_to(p.global_position)
				if dd < zd:
					zd = dd
					zt = z
			if gt != Vector3.INF:
				goal = gt
			elif zt and zd > 6.0:
				goal = zt.global_position
			if zt and zd < 11.0:
				bot["aim_point"] = zt.global_position
				bot["shoot"] = true
			if zt and zd < 2.0 and randf() < 0.05:
				bot["just_roll"] = true
		3, 4:
			if Game.in_bullet_time():
				_shot("breach")
			var tk := _level.taker
			var other := _nearest(func(e: Enemy): return e.zone == "staff" and e.is_active() and e != tk)
			if other and _can_shoot(p, other):
				shoot_at = other
			elif is_instance_valid(tk) and tk.is_active():
				if _can_shoot(p, tk):
					shoot_at = tk
					bot["aim"] = true
				else:
					goal = tk.global_position + Vector3(-2.0, 0, 2.0)
			elif _level.hostage and _level.hostage.state == "free":
				goal = _level.hostage.global_position
				if p.global_position.distance_to(goal) < 1.4:
					bot["just_interact"] = true
					goal = Vector3.INF
			else:
				var dn := _nearest(func(e: Enemy): return e.state == "downed")
				if dn:
					goal = dn.global_position

	# 顺路捡手雷（6 米内）
	if p.grenades < Player.MAX_GRENADES and goal != Vector3.INF:
		for pk in _level.pickups:
			if is_instance_valid(pk) and pk.kind == "grenade" and not pk.taken and pk.global_position.distance_to(p.global_position) < 6.0:
				goal = pk.global_position
				break
	if shoot_at:
		bot["aim"] = bot.get("aim", false) or shoot_at.kind == "taker"
		bot["aim_point"] = shoot_at.global_position
		bot["shoot"] = true
		if not _shots_taken.has("combat") and _level.t > 3.0:
			_shot("combat")
	if goal != Vector3.INF:
		var dir := _follow(p, goal)
		var cam := _level.cam
		bot["move"] = cam.ground_to_screen(dir)
		if shoot_at == null and not bool(bot.get("shoot", false)):
			bot["aim_point"] = p.global_position + dir * 4.0
		# 卡住了就翻滚
		if p.global_position.distance_to(_last_pos) < 0.02:
			_stuck_t += delta
			if _stuck_t > 0.6:
				_stuck_t = 0.0
				bot["just_roll"] = true
				_path_goal = Vector3.INF
		else:
			_stuck_t = 0.0
	# 手雷：有手雷且目标在 7.5 米内就扔；神装：每 5 秒切换一次（测试武器库）
	_gren_t -= delta
	if p.grenades > 0 and _gren_t <= 0.0 and shoot_at and shoot_at.global_position.distance_to(p.global_position) < 7.5:
		_gren_t = 2.5
		bot["just_grenade"] = true
		print("[autotest] grenade x%d at %.1f" % [p.grenades, _total])
		if not _shots_taken.has("grenade"):
			get_tree().create_timer(0.45, false).timeout.connect(func(): _shot("grenade"))
	_switch_t -= delta
	if p.arsenal.size() >= 1 and _switch_t <= 0.0:
		_switch_t = 5.0
		bot["just_switch"] = true
		print("[autotest] switch from %s owned=%s" % [p.weapon, str(p.owned_weapons())])
		if p.owned_weapons().size() >= 3 and not _shots_taken.has("weapons"):
			get_tree().create_timer(0.3, false).timeout.connect(func(): _shot("weapons"))
	_last_pos = p.global_position
	if p.hp < 45.0 and randf() < 0.02:
		bot["just_roll"] = true
	bot["aim"] = bool(bot.get("aim", false))
	p.bot = bot


func _can_shoot(p: Player, e: Enemy) -> bool:
	if not _level.clear_shot(p.global_position + Vector3(0, Bullet.HEIGHT, 0), e.global_position + Vector3(0, Bullet.HEIGHT, 0)):
		return false
	var h := _level.hostage
	if h == null or h.state in ["rescued", "evac", "gone"]:
		return true
	var a := Vector2(p.global_position.x, p.global_position.z)
	var b := Vector2(e.global_position.x, e.global_position.z)
	var hp := Vector2(h.global_position.x, h.global_position.z)
	var over := 1.0 + 8.0 / maxf((b - a).length(), 0.5)
	var t := clampf((hp - a).dot(b - a) / maxf((b - a).length_squared(), 0.001), 0.0, over)
	return (hp - (a + (b - a) * t)).length() > 1.0


func _nearest(pred: Callable) -> Enemy:
	var best: Enemy = null
	var bd := 1e9
	for e in _level.enemies:
		if pred.call(e):
			var d := e.global_position.distance_to(_level.player.global_position)
			if d < bd:
				bd = d
				best = e
	return best


func _follow(p: Player, goal: Vector3) -> Vector3:
	if _path_goal == Vector3.INF or _path_goal.distance_to(goal) > 1.0 or _path_i >= _path.size():
		_path_goal = goal
		var map := _level.get_world_3d().navigation_map
		_path = NavigationServer3D.map_get_path(map, p.global_position, goal, true)
		_path_i = 0
	while _path_i < _path.size():
		var wp := _path[_path_i]
		var d := Vector3(wp.x - p.global_position.x, 0, wp.z - p.global_position.z)
		if d.length() < 0.45:
			_path_i += 1
			continue
		return d.normalized()
	var dd := goal - p.global_position
	dd.y = 0
	return dd.normalized() if dd.length() > 0.3 else Vector3.ZERO


## 校验：鼠标屏幕坐标 → 世界坐标 的换算在窗口缩放下仍然正确
func _check_mouse() -> void:
	var target := _level.player.global_position + Vector3(3.0, Bullet.HEIGHT, -2.0)
	var sp := _level.cam.cam.unproject_position(target)
	get_viewport().warp_mouse(sp)
	await get_tree().process_frame
	var w := _level.mouse_world()
	print("[autotest] mouse check screen=", sp, " world=", w, " target=", target, " err=", snappedf(w.distance_to(target), 0.01))


# ------------------------------------------------------------------ 触屏测试（窗口需与基准分辨率同比例，如 2400x1080）

func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = get_viewport().get_final_transform() * pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = get_viewport().get_final_transform() * pos
	Input.parse_input_event(e)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _touch_test() -> void:
	var lv := _level
	var tc := lv.hud.touch
	var p := lv.player
	var ok := true
	print("[touch] touch controls present: ", tc != null, " size=", tc.size)
	var c := tc.centers()
	# 1) 左摇杆向上拖 → 角色朝屏幕上方（镜头前方）移动，并转身朝移动方向
	var start := p.global_position
	_touch(0, Vector2(300, 800), true)
	for i in 6:
		await get_tree().process_frame
		_drag(0, Vector2(300, 800 - i * 25))
	await _wait(1.0)
	await _shot("touch_move")
	var moved := p.global_position - start
	var fwd := lv.cam.ground_forward()
	var along := moved.dot(fwd)
	var face_dot := p.model_forward().dot(fwd)
	print("[touch] move along forward=", snappedf(along, 0.01), " facing·fwd=", snappedf(face_dot, 0.01))
	ok = ok and along > 2.0 and face_dot > 0.8
	_touch(0, Vector2(300, 650), false)
	# 2) 按住开火键 → 自动开火
	var shots0 := int(Game.run.shots)
	_touch(1, c.fire, true)
	await _wait(0.8)
	await _shot("touch_fire")
	_touch(1, c.fire, false)
	var fired := int(Game.run.shots) - shots0
	print("[touch] shots fired by holding fire=", fired)
	ok = ok and fired >= 4
	# 3) 拖动开火键 → 手动瞄准（向右拖 → 朝镜头右方开火）
	_touch(1, c.fire, true)
	await get_tree().process_frame
	_drag(1, c.fire + Vector2(90, 0))
	await _wait(0.3)
	var aim_dot := p.aim_dir.dot(lv.cam.ground_right())
	print("[touch] drag-aim right · aim_dir=", snappedf(aim_dot, 0.01))
	ok = ok and aim_dot > 0.7
	_touch(1, c.fire + Vector2(90, 0), false)
	# 4) 翻滚键
	await _wait(0.6)
	_touch(2, c.roll, true)
	await _wait(0.12)
	print("[touch] roll triggered=", p.roll_t > 0.0 or p.roll_cd > 0.0)
	ok = ok and (p.roll_t > 0.0 or p.roll_cd > 0.0)
	_touch(2, c.roll, false)
	# 5) 暂停键
	await _wait(0.5)
	_touch(3, c.pause, true)
	_touch(3, c.pause, false)
	await _wait(0.6)
	print("[touch] pause opened=", get_tree().paused)
	ok = ok and get_tree().paused
	await _shot("touch_pause")
	lv.pause_menu.close()
	await _wait(0.5)
	print("[touch] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 3)
