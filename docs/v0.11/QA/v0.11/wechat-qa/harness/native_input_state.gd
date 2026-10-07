extends Node
## Linux headless synthetic native InputEvents and manual notification dispatch. Not Android hardware input.
var level: Level
var p: Player
var tc: TouchControls
var checks: Array[Dictionary] = []
var observations: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Online.server_url = ""
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.ignore_time_scale = true
	watchdog.wait_time = 30.0
	watchdog.timeout.connect(func(): print("[native-input-qa] TIMEOUT"); get_tree().quit(2))
	add_child(watchdog)
	watchdog.start()
	call_deferred("_run")

func check(name: String, passed: bool, detail: Dictionary = {}) -> void:
	checks.append({"name": name, "passed": passed, "details": detail})
	print("[native-input-qa] ", "PASS " if passed else "FAIL ", name, " ", JSON.stringify(detail))

func frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func touch(index: int, pos: Vector2, pressed: bool, canceled: bool = false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = get_viewport().get_final_transform() * pos
	e.pressed = pressed
	e.canceled = canceled
	Input.parse_input_event(e)

func drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = get_viewport().get_final_transform() * pos
	Input.parse_input_event(e)

func clean() -> void:
	tc.release_all()
	p.bot.clear()
	await frames()

func wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _run() -> void:
	get_tree().root.size = Vector2i(2400, 1080)
	await frames()
	var holder := Node.new()
	holder.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(holder)
	Game.autotest = false
	Game.touch = true
	Game.settings.aim_mode = "lock"
	Game.set_difficulty("normal", false)
	Game.container = holder
	level = Level.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	Game.current = level
	holder.add_child(level)
	p = level.player
	tc = level.hud.touch
	level.set_process(false)
	p.set_physics_process(false)
	level.hostage.set_physics_process(false)
	for e in level.enemies:
		e.set_physics_process(false)
	await frames()
	check("production_touch_controls_present", tc != null, {"size": str(tc.size), "viewport": str(get_viewport().get_visible_rect().size)})
	var c := tc.centers()
	var left := Vector2(300, 700)
	touch(-2147483647, left, true)
	drag(-2147483647, left + Vector2(80, -60))
	await frames()
	check("signed_browser_touch_id_can_move", p.bot.move.length() > 0.0, {"owner": tc._move_idx, "move": str(p.bot.move)})
	await clean()
	touch(-1, left, true)
	drag(-1, left + Vector2(80, -60))
	await frames()
	check("minus_one_browser_touch_id_can_move", p.bot.move.length() > 0.0, {"owner": tc._move_idx, "move": str(p.bot.move)})
	await clean()
	tc.hide()
	touch(8, left, true)
	drag(8, left + Vector2(80, -60))
	await frames()
	check("hidden_controls_cannot_drive_player", p.bot.move == Vector2.ZERO, {"owner": tc._move_idx, "move": str(p.bot.move)})
	tc.show()
	await clean()
	touch(10, left, true)
	drag(10, left + Vector2(80, -60))
	touch(20, c.fire, true)
	await frames()
	check("simultaneous_move_and_fire_native_events", tc._move_idx == 10 and tc._fire_idx == 20 and p.bot.move.length() > 0 and bool(p.bot.shoot))
	touch(11, left + Vector2(10, 0), true)
	drag(11, left + Vector2(90, -60))
	await frames()
	check("new_move_takes_over_after_lost_release", tc._move_idx == 11 and tc._fire_idx == 20)
	touch(10, left, false)
	await frames()
	check("late_old_move_release_preserves_new_owners", tc._move_idx == 11 and tc._fire_idx == 20)
	touch(21, c.fire, true)
	await frames()
	check("new_fire_takes_over_after_lost_release", tc._fire_idx == 21 and tc._move_idx == 11)
	touch(20, c.fire, false)
	await frames()
	check("late_old_fire_release_preserves_new_owners", tc._fire_idx == 21 and tc._move_idx == 11)
	touch(21, c.fire, false, true)
	await frames()
	check("lock_mode_fire_cancel_preserves_move", tc._fire_idx == -1 and tc._move_idx == 11 and not bool(p.bot.shoot))
	touch(11, left, false, true)
	await frames()
	check("move_cancel_releases_move", tc._move_idx == -1 and p.bot.move == Vector2.ZERO)
	await clean()
	p.grenades = 0
	check("hidden_grenade_button_not_hit", tc._hit_button(c.grenade) == "")
	touch(30, c.grenade, true)
	await frames()
	check("hidden_grenade_position_falls_through_to_fire", tc._fire_idx == 30 and not tc._btn_idx.has(30))
	await clean()
	p.grenades = 1
	check("available_grenade_button_is_hit", tc._hit_button(c.grenade) == "grenade")
	touch(31, c.grenade, true)
	await frames()
	check("grenade_touch_queues_production_action", tc._btn_idx.get(31, "") == "grenade" and bool(p.bot.get("just_grenade", false)))
	p.grenades = 0
	await frames()
	check("hidden_held_button_clears_owner", not tc._btn_idx.has(31))
	observations.append({"name": "button_becomes_hidden_while_held", "button_hit_after_hidden": tc._hit_button(c.grenade), "old_button_owner_retained": tc._btn_idx.has(31), "mode": "one-shot queued action observed; player physics disabled for state isolation"})
	touch(32, c.grenade, true)
	await frames()
	check("new_touch_after_grenade_hidden_uses_valid_fire_zone", tc._fire_idx == 32 and not tc._btn_idx.has(32))
	await clean()
	p.arsenal.clear()
	check("hidden_weapon_button_not_hit", tc._hit_button(c.weapon) == "")
	touch(40, c.weapon, true)
	await frames()
	check("hidden_weapon_position_falls_through_to_fire", tc._fire_idx == 40 and not tc._btn_idx.has(40))
	await clean()
	p.arsenal["shotgun"] = 10
	touch(41, c.weapon, true)
	await frames()
	check("available_weapon_touch_queues_switch", tc._btn_idx.get(41, "") == "weapon" and bool(p.bot.get("just_switch", false)))
	await clean()
	check("hidden_interact_button_not_hit", tc._interactable() == null and tc._hit_button(c.interact) == "")
	touch(50, c.interact, true)
	await frames()
	check("hidden_interact_position_falls_through_to_fire", tc._fire_idx == 50 and not tc._btn_idx.has(50))
	await clean()
	Game.settings.aim_mode = "release"
	touch(60, c.fire, true)
	await frames()
	check("release_mode_hold_does_not_shoot", not bool(p.bot.shoot))
	touch(60, c.fire, false, true)
	await frames()
	check("release_mode_cancel_does_not_fire_burst", tc._burst_t <= 0.0 and not bool(p.bot.shoot), {"burst_remaining": tc._burst_t, "shoot": p.bot.shoot})
	await clean()
	Game.settings.aim_mode = "lock"
	touch(70, left, true)
	drag(70, left + Vector2(80, -60))
	touch(71, c.fire, true)
	await frames()
	Game.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames()
	check("manual_native_back_notification_opens_pause", get_tree().paused and level.pause_menu.is_open())
	touch(70, left, false)
	touch(71, c.fire, false)
	await frames()
	Game.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await wait_real(0.35)
	await frames()
	check("manual_native_back_notification_resumes", not get_tree().paused and not level.pause_menu.is_open())
	check("released_while_paused_does_not_resume_stale_input", tc._move_idx == -1 and tc._fire_idx == -1 and p.bot.move == Vector2.ZERO and not bool(p.bot.shoot), {"move_owner": tc._move_idx, "fire_owner": tc._fire_idx, "move": str(p.bot.move), "shoot": p.bot.shoot})
	await clean()
	Game.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await frames()
	check("manual_application_paused_notification_opens_pause", get_tree().paused and level.pause_menu.is_open())
	level.pause_menu.close()
	await wait_real(0.35)
	await frames()
	check("pause_menu_close_resumes_after_background_notification", not get_tree().paused)
	await clean()
	touch(80, left, true)
	drag(80, left + Vector2(80, -60))
	touch(81, c.fire, true)
	await frames()
	Game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames()
	check("focus_out_clears_both_owners_and_cache", tc._move_idx == -1 and tc._fire_idx == -1 and p.bot.move == Vector2.ZERO and not bool(p.bot.shoot), {"move_owner": tc._move_idx, "fire_owner": tc._fire_idx, "move": str(p.bot.move), "shoot": p.bot.shoot})
	level.pause_menu.close()
	await wait_real(0.35)
	await frames()
	await clean()
	touch(91, left, true)
	drag(91, left + Vector2(80, -60))
	touch(91, c.fire, true)
	drag(91, c.fire + Vector2(90, 0))
	await frames()
	check("reused_id_moves_to_fire_without_dual_ownership", tc._move_idx == -1 and tc._fire_idx == 91 and p.bot.move == Vector2.ZERO and tc._manual)
	await clean()
	touch(-1, c.fire, true)
	await frames()
	check("signed_minus_one_fire_contact_is_active", bool(p.bot.shoot))
	touch(-1, c.fire, false, true)
	await frames()
	check("signed_minus_one_fire_cancel_releases", not bool(p.bot.shoot))
	await clean()
	touch(92, left, true)
	drag(92, left + Vector2(600, -450))
	await frames()
	check("far_drag_keeps_floating_stick_active", p.bot.move.length() > 0.9 and p.bot.move.length() <= 1.001)
	touch(93, c.fire, true)
	await frames()
	tc.notification(Control.NOTIFICATION_RESIZED)
	check("rotation_coordinate_change_clears_cache_immediately", p.bot.move == Vector2.ZERO and not bool(p.bot.shoot))
	await clean()
	p.weapon = "shotgun"
	check("hidden_reload_button_is_not_hit", tc._hit_button(c.reload) == "")
	p.weapon = "rifle"
	touch(95, left, true)
	drag(95, left + Vector2(80, -60))
	await frames()
	var malformed := InputEventScreenDrag.new()
	malformed.index = 95
	malformed.position = Vector2(NAN, INF)
	tc._input(malformed)
	await frames()
	check("nonfinite_drag_does_not_corrupt_movement", p.bot.move.is_finite() and p.bot.move.length() > 0.0)
	await clean()
	var malformed_press := InputEventScreenTouch.new()
	malformed_press.index = 96
	malformed_press.position = Vector2(NAN, INF)
	malformed_press.pressed = true
	tc._input(malformed_press)
	await frames()
	check("nonfinite_press_does_not_claim_input", tc._move_idx == -1 and tc._fire_idx == -1 and p.bot.move == Vector2.ZERO)
	Game.settings.aim_mode = "release"
	touch(94, c.fire, true)
	await frames()
	touch(94, c.fire, false)
	await frames()
	check("ordinary_release_still_fires_burst", tc._burst_t > 0.0 and bool(p.bot.shoot))
	await clean()
	Game.settings.aim_mode = "lock"
	# Re-entering a level while already portrait must pause, even when the
	# orientation overlay was made visible earlier in a menu.
	get_tree().root.size = Vector2i(1080, 1920)
	Game._rotate.visible = true
	Game._check_rotate()
	await frames()
	check("already_visible_portrait_overlay_still_pauses_level", get_tree().paused and level.pause_menu.is_open())
	get_tree().root.size = Vector2i(2400, 1080)
	Game._check_rotate()
	level.pause_menu.close()
	await wait_real(0.35)
	await frames()
	check("landscape_resume_uses_fresh_contacts", not get_tree().paused and tc._move_idx == -1 and tc._fire_idx == -1 and p.bot.move == Vector2.ZERO)
	var failed := checks.filter(func(x: Dictionary): return not x.passed)
	var path := ProjectSettings.globalize_path("user://native-input-state-report.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info(), "checks": checks, "observations": observations, "passed": failed.is_empty(), "failed": failed.size(), "mode": "Linux headless synthetic Input.parse_input_event dispatch plus manual Object.notification; not Android device events, rendered UI, GPU or audible audio"}, "\t"))
	file.close()
	print("[native-input-qa] RESULT ", JSON.stringify({"checks": checks.size(), "failed": failed.size(), "passed": failed.is_empty(), "report": path}))
	Game.current = null
	Game.container = null
	Game.reset_time()
	get_tree().paused = false
	level.queue_free()
	level = null
	p = null
	tc = null
	await frames()
	Sfx.music("")
	Sfx._music.stream = null
	for a in Sfx._players:
		a.stop()
		a.stream = null
	Sfx._cache.clear()
	Fx._res.clear()
	Fx._tex.clear()
	await wait_real(0.5)
	await frames()
	get_tree().quit(0 if failed.is_empty() else 1)
