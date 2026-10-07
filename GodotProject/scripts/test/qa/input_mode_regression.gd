extends Node
## Isolated headless input/HUD regression. Synthetic native events, not browser
## or physical device QA. Never finishes a run or writes a score.
var checks := 0
var failures := 0
var level: Level
var player: Player
var controls: TouchControls

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Online.server_url = ""
	var watchdog := Timer.new()
	watchdog.wait_time = 30.0
	watchdog.one_shot = true
	watchdog.ignore_time_scale = true
	watchdog.timeout.connect(func(): print("[input-mode-native] TIMEOUT"); get_tree().quit(2))
	add_child(watchdog)
	watchdog.start()
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("[input-mode-native] ", "PASS " if ok else "FAIL ", label)

func frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func contact(index: int, position: Vector2, pressed: bool, emulated := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * position
	event.pressed = pressed
	event.device = InputEvent.DEVICE_ID_EMULATION if emulated else 0
	Input.parse_input_event(event)

func drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * position
	Input.parse_input_event(event)

func mouse(pressed: bool, emulated := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = get_viewport().get_final_transform() * Vector2(1000, 600)
	event.device = InputEvent.DEVICE_ID_EMULATION if emulated else 0
	Input.parse_input_event(event)

func key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.pressed = pressed
	Input.parse_input_event(event)

func _run() -> void:
	get_tree().root.size = Vector2i(2400, 1080)
	await frames()
	Game.autotest = false
	Game._forced_touch = false
	Game.touch = false
	Game.new_run()
	level = Level.new()
	Game.current = level
	Game.container = self
	add_child(level)
	level.set_process(false)
	player = level.player
	player.set_physics_process(false)
	level.hostage.set_physics_process(false)
	for enemy in level.enemies:
		enemy.set_physics_process(false)
	controls = level.hud.touch
	await frames()
	var options := level.pause_menu.find_child("TouchOptions", true, false) as Control
	check(not Game.touch and not controls.visible, "desktop starts without virtual controls")
	check(not player.bot_enabled, "desktop input remains keyboard mouse owned")
	check(level.hud._ammo.visible and level.hud._skills.visible and level.hud._cross.visible, "desktop ammo skills and crosshair visible")
	check(options != null and not options.visible, "desktop hides touch-only pause options")
	key(true)
	await frames()
	check(player._vec().y < 0, "desktop keyboard reaches production Player movement")
	key(false)
	mouse(true)
	await frames()
	check(player._held("shoot"), "desktop mouse reaches production Player shooting")
	mouse(false)
	contact(8, Vector2(300, 700), true, true)
	await frames()
	check(not Game.touch and not controls.visible, "mouse-emulated touch cannot force mobile")
	contact(8, Vector2(300, 700), false, true)
	var left := Vector2(300, 700)
	contact(-1, left, true)
	drag(-1, left + Vector2(80, -60))
	await frames()
	check(Game.touch and controls.visible and player.bot_enabled, "genuine touch activates virtual controls and player input")
	check(controls._move_active and controls._move_idx == -1 and player._vec().length() > 0.2, "first actual touch and signed ID retained without replay")
	check(not level.hud._ammo.visible and not level.hud._skills.visible and not level.hud._cross.visible, "touch layout hides desktop widgets")
	check(options.visible, "hybrid activation exposes touch aim and vibration settings")
	contact(2, controls.centers().fire, true)
	await frames()
	check(controls._fire_active and player._held("shoot"), "multitouch virtual fire still works")
	mouse(true, true)
	mouse(false, true)
	await frames()
	check(Game.touch and controls._move_active and controls._fire_active, "engine emulated mouse preserves both touch sticks")
	mouse(true)
	await frames()
	check(not Game.touch and not controls.visible and not player.bot_enabled, "real mouse restores desktop ownership mid-level")
	check(not controls._move_active and not controls._fire_active and controls._burst_t <= 0.0, "mode change cancels touch owners and pending burst")
	check(player.bot.get("move", Vector2.ZERO) == Vector2.ZERO and not player.bot.get("shoot", false), "mode change clears stale virtual movement and firing")
	check(player._held("shoot"), "first real mouse press still reaches shooting after mode change")
	check(level.hud._ammo.visible and options != null and not options.visible, "desktop HUD and pause options restored")
	mouse(false)
	get_tree().root.size = Vector2i(800, 1400)
	await frames()
	Game._check_rotate()
	check(not Game.touch and not controls.visible, "narrow portrait resize does not select mobile")
	check(not Game._rotate.visible and not get_tree().paused, "portrait desktop has no mobile rotate gate")
	get_tree().root.size = Vector2i(2400, 1080)
	await frames()
	contact(3, left, true)
	drag(3, left + Vector2(80, 0))
	await frames()
	check(Game.touch and player._vec().x > 0, "touch can reactivate after desktop resize")
	controls.notification(Control.NOTIFICATION_RESIZED)
	check(Game.touch and controls.visible and player.bot.move == Vector2.ZERO and not controls._move_active, "touch resize keeps mode but clears obsolete coordinates")
	key(true)
	await frames()
	check(not Game.touch and not player.bot_enabled and player._vec().y < 0, "real keyboard switches back and moves on the first key")
	key(false)
	var shoot_events := InputMap.action_get_events("shoot").size()
	for i in 5:
		Game.set_touch_mode(true)
		Game.set_touch_mode(false)
	var count := 0
	for child in level.hud.root.get_children():
		if child is TouchControls:
			count += 1
	check(count == 1 and level.hud.touch == controls, "repeated switching reuses one virtual control overlay")
	check(InputMap.action_get_events("shoot").size() == shoot_events, "switching does not rewrite action or controller mappings")
	Game.set_touch_mode(true)
	var despawned := Enemy.new()
	controls.lock = despawned
	controls._cand = despawned
	despawned.free()
	check(not controls._valid(controls.lock) and not controls._can_hit(controls.lock), "freed target references rejected before typed helper calls")
	controls._feed()
	check(controls.lock == null, "direct feed safely drops an actually freed Enemy")
	controls._process(0.016)
	check(controls.lock == null and controls._cand == null and player.lock_target == null, "despawn clears touch lock candidate and player homing target")
	var queued := Enemy.new()
	controls.lock = queued
	queued.queue_free()
	check(not controls._valid(controls.lock), "queued target deletion immediately excludes touch targeting")
	controls._process(0.016)
	await frames()
	check(controls.lock == null, "target deletion cannot leave a stale lock on the next frame")
	Game.set_touch_mode(true)
	Game._rotate.visible = true
	Game.set_touch_mode(false)
	check(not Game._rotate.visible, "desktop switch clears stale orientation overlay immediately")
	controls.drive = false
	player.bot_enabled = true
	player.bot["move"] = Vector2(0.3, 0.4)
	Game.set_touch_mode(true)
	Game.set_touch_mode(false)
	await frames()
	check(player.bot_enabled and player.bot.move == Vector2(0.3, 0.4), "test bot ownership preserved when virtual controls do not drive")
	controls.drive = true
	Game._forced_touch = true
	Game.touch = true
	Game.input_mode_changed.emit(true)
	Game.set_touch_mode(false)
	check(Game.touch and controls.visible, "explicit --touch preview remains forced")
	Game._forced_touch = false
	Game.set_touch_mode(false)
	print("[input-mode-native] RESULT ", JSON.stringify({"checks": checks, "failed": failures, "mode": "Godot headless synthetic InputEvents; no hardware browser or score writes"}))
	Game.current = null
	Game.container = null
	level.queue_free()
	await frames()
	Sfx.music("")
	Sfx._music.stream = null
	for audio_player in Sfx._players:
		audio_player.stop()
		audio_player.stream = null
	Sfx._cache.clear()
	Fx._res.clear()
	Fx._tex.clear()
	await get_tree().create_timer(0.5, true, false, true).timeout
	await frames()
	get_tree().quit(0 if failures == 0 else 1)
