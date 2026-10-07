extends Node
## Deterministic native renderer QA. The scenario uses production classes; it never uses --god.
var level: Level
var p: Player
var shots_dir := ProjectSettings.globalize_path("user://qa-evidence")
var n := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Online.server_url = ""
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.wait_time = 60.0
	watchdog.ignore_time_scale = true
	watchdog.timeout.connect(func(): print("[qa] TIMEOUT"); get_tree().quit(2))
	add_child(watchdog)
	watchdog.start()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-shots="):
			shots_dir = arg.substr(11)
	DirAccess.make_dir_recursive_absolute(shots_dir)
	call_deferred("_run")

func wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	var path := shots_dir.path_join("%02d_%s.png" % [n, label])
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("[visual-qa] screenshot ", path, " error=", err)

func _run() -> void:
	Game.autotest = false
	Game.set_difficulty("normal", false)
	Game.boot(self)
	await wait_real(1.8)
	await shot("menu")
	Game.goto("level")
	await wait_real(2.5)
	level = Game.current
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	p = level.player
	level.set_process(false)
	level.phase = 5
	level.wave_on = true
	level.wave_fired = true
	level.wave_t = 22.0
	level.hud.radio.clear()
	level.hud.set_objective("坚守阵地 · 护盾测试", "38秒")
	for e in level.enemies:
		e.set_physics_process(false)
		e.visible = false
	level.hostage.set_physics_process(false)
	level.hostage.visible = false
	p.bot_enabled = true
	p.bot = {"move": Vector2.ZERO, "shoot": false, "aim": false}
	p.global_position = Vector3(0, 0, 9.0)
	level.cam.snap()
	Game.reset_time()
	for pos in [Vector3(-3, 0, 11), Vector3(3, 0, 11), Vector3(-4, 0, 8), Vector3(4, 0, 8), Vector3(-2, 0, 6), Vector3(2, 0, 6)]:
		var z := Zombie.new()
		z.level = level
		level.add_child(z)
		level.zombies.append(z)
		z.global_position = pos
		z.set_physics_process(false)
		z._rise = 0.0
		z.model.position.y = 0.0
	await wait_real(0.8)
	p.since_damage = 99.0
	p.take_hit(5.0, Vector3.RIGHT, p.global_position + Vector3.LEFT, null)
	print("[visual-qa] normal damage hp=", p.hp, " damage_stat=", Game.run.damage)
	await wait_real(0.15)
	await shot("horde_damage_no_shield")
	var pk := level.spawn_pickup(Vector3(3.2, 0, 9), "shield", "", 0.0, p.global_position)
	pk.set_process(false)
	level.hud.set_target(pk)
	await wait_real(0.4)
	await shot("rare_shield_loot")
	pk._collect()
	level.hud.set_target(null)
	var hp_before: float = p.hp
	p.since_damage = 0.0
	p.take_hit(22.0, Vector3.RIGHT, p.global_position + Vector3.LEFT, null)
	print("[visual-qa] active shield hp=", p.hp, " unchanged=", p.hp == hp_before, " seconds=", p.shield_t)
	await wait_real(0.25)
	await shot("shield_active_countdown")
	level.pause_menu.open()
	var frozen: float = p.shield_t
	await wait_real(0.6)
	await shot("paused_shield")
	print("[visual-qa] paused shield frozen=", is_equal_approx(frozen, p.shield_t), " seconds=", p.shield_t)
	level.pause_menu.close()
	await wait_real(0.4)
	while p.shield_t > 0.85:
		await wait_real(0.05)
	await shot("shield_expiry_warning")
	while p.shield_t > 0.0:
		await wait_real(0.03)
	p.since_damage = 99.0
	p.take_hit(5.0, Vector3.RIGHT, p.global_position + Vector3.LEFT, null)
	print("[visual-qa] expired shield hp=", p.hp, " seconds=", p.shield_t, " damage_stat=", Game.run.damage)
	await wait_real(0.15)
	await shot("shield_expired_damage_resumes")
	print("[visual-qa] DONE screenshots=", n, " permanent_god=false")
	Game.current = null
	Game.container = null
	Game.reset_time()
	get_tree().paused = false
	level.queue_free()
	level = null
	p = null
	await get_tree().process_frame
	await get_tree().process_frame
	Sfx.music("")
	Sfx._music.stream = null
	for audio_player in Sfx._players:
		audio_player.stop()
		audio_player.stream = null
	Sfx._cache.clear()
	Fx._res.clear()
	Fx._tex.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()
