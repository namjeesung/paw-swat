extends Node
## Uses real Player, Level, Zombie and Pickup classes. No permanent god-mode flag.
var checks: Array[Dictionary] = []
var level: Level
var p: Player
var holder: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Online.server_url = ""
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.wait_time = 30.0
	watchdog.ignore_time_scale = true
	watchdog.timeout.connect(func(): print("[qa] TIMEOUT"); get_tree().quit(2))
	add_child(watchdog)
	watchdog.start()
	holder = Node.new()
	holder.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(holder)
	call_deferred("_run")

func check(name: String, ok: bool, details: Dictionary = {}) -> void:
	checks.append({"name": name, "passed": ok, "details": details})
	print("[regression] ", "PASS " if ok else "FAIL ", name, " ", JSON.stringify(details))

func wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func start_level() -> void:
	Game.reset_time()
	get_tree().paused = false
	Game.set_difficulty("normal", false)
	Game.autotest = false
	Game.container = holder
	level = Level.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	Game.current = level
	holder.add_child(level)
	p = level.player
	p.bot_enabled = true
	p.bot = {"move": Vector2.ZERO, "shoot": false, "aim": false}
	level.set_process(false)
	for e in level.enemies:
		e.set_physics_process(false)
	level.hostage.set_physics_process(false)
	p.set_physics_process(false)

func clean_damage() -> void:
	p.hp = p.max_hp
	p.since_damage = 99.0
	p.roll_t = 0.0
	p.dash_t = 0.0
	Game.run.damage = 0.0

func hit(damage: float) -> void:
	p.take_hit(damage, Vector3.RIGHT, p.global_position + Vector3.LEFT, null)

func _run() -> void:
	start_level()
	check("no_god_arguments", not OS.get_cmdline_user_args().has("--god"), {"arguments": Array(OS.get_cmdline_user_args())})
	check("normal_initial_health", is_equal_approx(p.hp, 100.0), {"hp": p.hp})
	for phase in [0, 1, 2, 3, 4, 5]:
		clean_damage()
		level.phase = phase
		level.wave_on = phase == 5
		level.wave_fired = phase == 5
		hit(5.0)
		check("damage_phase_%d" % phase, is_equal_approx(p.hp, 95.0) and is_equal_approx(Game.run.damage, 5.0), {"hp": p.hp, "damage": Game.run.damage})
	clean_damage()
	hit(5.0)
	hit(5.0)
	check("post_hit_grace_blocks_burst", is_equal_approx(p.hp, 95.0), {"hp": p.hp})
	p._tick_timers(0.41)
	hit(5.0)
	check("post_hit_grace_expires", is_equal_approx(p.hp, 90.0), {"hp": p.hp})
	clean_damage()
	p.roll_t = 0.2
	hit(5.0)
	check("existing_roll_protection", is_equal_approx(p.hp, 100.0), {"hp": p.hp})
	p.roll_t = 0.0
	p.dash_t = 0.2
	hit(5.0)
	check("existing_dash_protection", is_equal_approx(p.hp, 100.0), {"hp": p.hp})
	for boss in [false, true]:
		clean_damage()
		var z := Zombie.new()
		z.boss = boss
		z.level = level
		level.add_child(z)
		level.zombies.append(z)
		z.set_physics_process(false)
		z.global_position = p.global_position + Vector3.LEFT * 0.5
		z._rise = 0.0
		z._wind = 0.001
		z._physics_process(0.02)
		var wanted := 78.0 if boss else 95.0
		check("boss_melee_damage" if boss else "zombie_melee_damage", is_equal_approx(p.hp, wanted), {"hp": p.hp, "expected_hp": wanted})
		level.zombies.erase(z)
		z.queue_free()
	clean_damage()
	p.hp = 50.0
	p.since_damage = 0.0
	p._tick_timers(4.9)
	check("regen_waits_normal_5sec", is_equal_approx(p.hp, 50.0), {"hp": p.hp})
	p._tick_timers(0.2)
	check("regen_is_heal_not_immunity", p.hp > 50.0 and p.hp < 100.0, {"hp": p.hp, "regen_rate": Game.dv("regen_rate")})
	if p.has_method("grant_shield"):
		await test_shield()
	else:
		check("baseline_has_no_shield", true)
	var failed := checks.filter(func(c: Dictionary): return not c.passed)
	var out := {"engine": Engine.get_version_info(), "checks": checks, "passed": failed.is_empty(), "failed": failed.size()}
	var path := ProjectSettings.globalize_path("user://qa-regression-report.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	print("[regression] RESULT ", JSON.stringify({"passed": failed.is_empty(), "checks": checks.size(), "failed": failed.size(), "report": path}))
	Game.current = null
	Game.container = null
	Game.reset_time()
	get_tree().paused = false
	if is_instance_valid(level):
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
	await wait_real(3.3)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failed.is_empty() else 1)

func test_shield() -> void:
	clean_damage()
	p.clear_shield()
	check("fresh_shield_inactive", p.shield_t == 0.0 and not p.invulnerable())
	check("grant_shield_exact_5sec", p.grant_shield() and is_equal_approx(p.shield_t, 5.0), {"remaining": p.shield_t})
	hit(5.0)
	check("shield_blocks_damage_and_stat", is_equal_approx(p.hp, 100.0) and is_equal_approx(Game.run.damage, 0.0), {"hp": p.hp, "damage": Game.run.damage})
	p._tick_shield(2.0)
	check("shield_counts_down", is_equal_approx(p.shield_t, 3.0), {"remaining": p.shield_t})
	check("active_shield_cannot_stack_or_refresh", not p.grant_shield() and is_equal_approx(p.shield_t, 3.0), {"remaining": p.shield_t})
	p._tick_shield(2.1)
	check("shield_one_sec_warning", p._shield_warned and is_equal_approx(p.shield_t, 0.9), {"remaining": p.shield_t})
	p._tick_shield(0.89)
	hit(5.0)
	check("shield_protects_until_deadline", p.hp == 100.0 and p.shield_t > 0.0, {"remaining": p.shield_t, "hp": p.hp})
	p._tick_shield(0.02)
	check("shield_expiry_clears_visual", p.shield_t == 0.0 and not p._shield_visual.visible and not p.invulnerable())
	p.since_damage = 99.0
	hit(5.0)
	check("damage_resumes_after_shield", is_equal_approx(p.hp, 95.0), {"hp": p.hp})
	p.clear_shield()
	clean_damage()
	p.grant_shield()
	p.set_physics_process(true)
	await wait_real(0.25)
	level.pause_menu.open()
	var paused_left: float = p.shield_t
	await wait_real(0.6)
	check("pause_freezes_shield_real_runtime", is_equal_approx(p.shield_t, paused_left), {"before": paused_left, "after": p.shield_t})
	level.pause_menu.close()
	await wait_real(0.45)
	check("resume_continues_countdown", p.shield_t < paused_left and p.shield_t > paused_left - 0.5, {"before": paused_left, "after": p.shield_t})
	Game.bullet_time(2.0)
	var slow_left: float = p.shield_t
	await wait_real(0.6)
	var elapsed: float = slow_left - p.shield_t
	check("slowmo_does_not_extend_shield", elapsed > 0.45 and elapsed < 0.8, {"shield_elapsed": elapsed, "timescale": Engine.time_scale})
	Game.reset_time()
	p.set_physics_process(false)
	p.clear_shield()
	clean_damage()
	var pk := Pickup.new()
	pk.kind = "shield"
	pk.weapon = ""
	pk.level = level
	level.add_child(pk)
	level.pickups.append(pk)
	pk.set_process(false)
	pk.global_position = p.global_position + Vector3.RIGHT * 5.0
	check("one_ground_shield_detected", level.has_ground_shield())
	pk._collect()
	check("pickup_grants_and_is_consumed", pk.taken and p.shield_t == 5.0 and not level.pickups.has(pk), {"taken": pk.taken, "remaining": p.shield_t})
	var pk2 := Pickup.new()
	pk2.kind = "shield"
	pk2.weapon = ""
	pk2.level = level
	level.add_child(pk2)
	level.pickups.append(pk2)
	pk2.set_process(false)
	pk2.global_position = p.global_position + Vector3.RIGHT * 5.0
	p._tick_shield(2.0)
	pk2._collect()
	check("active_shield_leaves_extra_loot_unconsumed", not pk2.taken and p.shield_t == 3.0 and level.pickups.has(pk2), {"taken": pk2.taken, "remaining": p.shield_t})
	pk2._process(11.99)
	check("ground_shield_lives_below_12sec", not pk2.is_queued_for_deletion() and level.pickups.has(pk2))
	pk2._process(0.02)
	check("ground_shield_expires_after_12sec", pk2.is_queued_for_deletion() and not level.pickups.has(pk2))
	p.clear_shield()
	level.wave_t = 0.0
	level.wave_on = true
	level.wave_fired = true
	level._shield_acc = Level.SHIELD_DROP_INTERVAL - 0.01
	level._tick_wave(0.02)
	check("rare_opportunity_spawns_one_ground_shield", shield_count() == 1, {"ground_shields": shield_count()})
	level._tick_wave(Level.SHIELD_DROP_INTERVAL)
	check("ground_shield_cap_skips_next_opportunity", shield_count() == 1 and level._shield_acc == 0.0, {"ground_shields": shield_count(), "banked_time": level._shield_acc})
	for ground in level.pickups.duplicate():
		if ground.kind == "shield":
			level.pickups.erase(ground)
			ground.queue_free()
	p.grant_shield()
	level._tick_wave(Level.SHIELD_DROP_INTERVAL)
	check("active_shield_skips_drop_without_banking", shield_count() == 0 and level._shield_acc == 0.0, {"ground_shields": shield_count(), "banked_time": level._shield_acc})
	p.clear_shield()
	level._tick_wave(0.01)
	check("skipped_opportunity_cannot_chain_on_expiry", shield_count() == 0, {"ground_shields": shield_count()})
	level.finished = true
	level._process(Level.SHIELD_DROP_INTERVAL)
	check("finished_level_cannot_spawn_shield", shield_count() == 0)
	p.clear_shield()
	check("finished_run_rejects_shield", not p.grant_shield())
	level.finished = false
	p.grant_shield()
	p._die()
	check("death_clears_shield", p.dead and p.shield_t == 0.0 and not p._shield_visual.visible)
	check("dead_player_rejects_shield", not p.grant_shield())
	Game.reset_time()
	var old := level
	start_level()
	old.queue_free()
	check("new_run_resets_shield_and_hp", p.shield_t == 0.0 and p.hp == 100.0 and not p.dead and Game.run.damage == 0.0, {"hp": p.hp, "remaining": p.shield_t})
	p.grant_shield()
	level.pause_menu.open()
	Game.goto("level")
	# Stop actors as soon as the real restart constructs the new Level.
	# This avoids creating unrelated nine-second skill tutorials during teardown.
	while Game.current == level:
		await get_tree().process_frame
	level = Game.current
	p = level.player
	level.set_process(false)
	for e in level.enemies:
		e.set_physics_process(false)
	p.set_physics_process(false)
	while Game._busy:
		await get_tree().process_frame
	check("actual_restart_clears_shield_and_pause", p.shield_t == 0.0 and p.hp == 100.0 and not p.dead and not get_tree().paused and Game.run.damage == 0.0 and is_equal_approx(Engine.time_scale, 1.0), {"hp": p.hp, "remaining": p.shield_t, "paused": get_tree().paused, "timescale": Engine.time_scale})

func shield_count() -> int:
	return level.pickups.filter(func(pk: Pickup): return is_instance_valid(pk) and not pk.taken and pk.kind == "shield").size()
