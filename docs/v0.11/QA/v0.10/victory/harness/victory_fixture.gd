extends Node
## Independent regression of production Level. Only Game.goto is recorded in the copied fixture.
## Actors are frozen so this validates mission rules, not gameplay difficulty or doorway physics.

class ProbeLevel extends Level:
	var reject_boss := false
	var boss_attempts := 0
	var regular_attempts := 0
	func _spawn_zombie(is_boss: bool) -> Zombie:
		if is_boss:
			boss_attempts += 1
			if reject_boss:
				return null
		else:
			regular_attempts += 1
		return super._spawn_zombie(is_boss)

class CleanupSpy extends Zombie:
	var cleanup_requests := 0
	func finale_pop(delay: float) -> void:
		cleanup_requests += 1

var holder: Node
var level: ProbeLevel
var checks: Array[Dictionary] = []
var transitions: Array[Dictionary] = []
var failed := 0
var wall_start := 0
var report_path := "res://../evidence/victory-report.json"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Online.server_url = ""
	Game.autotest = false
	Game.touch = false
	wall_start = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.substr(9)
	holder = Node.new()
	holder.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(holder)
	call_deferred("run_all")

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - wall_start > 120000:
		check("wall_timeout", false)
		save_report()
		get_tree().quit(2)

func check(id: String, passed: bool, detail: Dictionary = {}) -> void:
	checks.append({"id": id, "passed": passed, "detail": detail})
	if not passed:
		failed += 1
	print("[victory-qa] ", "PASS " if passed else "FAIL ", id, " ", JSON.stringify(detail))

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func setup(diff: String) -> void:
	Game.reset_time()
	Game.qa_routes.clear()
	Game.set_difficulty(diff, false)
	Game.container = holder
	level = ProbeLevel.new()
	Game.current = level
	holder.add_child(level)
	level.set_process(false)
	level.player.set_physics_process(false)
	level.player.bot_enabled = true
	level.hostage.set_physics_process(false)
	for enemy in level.enemies:
		enemy.set_physics_process(false)
	for i in 12:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(level.zombie_navigation_map(true)) > 0:
			break

func teardown() -> void:
	get_tree().paused = false
	Game.reset_time()
	transitions.append_array(Game.qa_routes.duplicate(true))
	Game.current = null
	level.queue_free()
	level = null
	await frames(5)

func freeze_zombies() -> void:
	for z in level.zombies:
		z.set_physics_process(false)
		z._rise = 0.0

func activate_wave() -> void:
	Game.run.rescued = true
	level.wave_on = true
	level.wave_fired = true
	level.phase = 5

func kill_boss(z: Zombie) -> void:
	z._rise = 0.0
	z.take_hit(z.hp + 1.0, Vector3.RIGHT, level.player.global_position, level.player)
	Game.reset_time()

func death_side_effect_snapshot() -> Dictionary:
	var pickup_ids: Array = []
	for pickup in level.pickups:
		pickup_ids.append(pickup.get_instance_id())
	var feed_ids: Array = []
	for item in level.hud._feed.get_children():
		feed_ids.append(item.get_instance_id())
	return {"score": int(Game.run.score), "kills": int(Game.run.zombies), "heal_drops": level.heal_drops_spawned, "pickup_ids": pickup_ids, "hud_combo": level.hud._combo, "hud_combo_text": level.hud._combo_label.text, "hud_feed_ids": feed_ids, "effect_children": level.get_child_count()}

func add_spy(is_boss: bool, is_dead: bool) -> CleanupSpy:
	var z := CleanupSpy.new()
	z.boss = is_boss
	z.level = level
	z.position = Vector3(0, 0, 16)
	level.add_child(z)
	level.zombies.append(z)
	z.set_physics_process(false)
	z._rise = 0.0
	z.dead = is_dead
	return z

func run_difficulty(diff: String, required: int) -> void:
	await setup(diff)
	check(diff + "_new_level_reset", level.boss_required == required and level._boss_spawned == 0 and level._boss_defeated == 0 and level._boss_dead_ids.is_empty() and level.wave_t == 0.0 and not Game.run.rescued, {"required": level.boss_required})
	activate_wave()
	level.reject_boss = true
	level._spawn_acc = 1000.0
	level._shield_acc = 1000.0
	level._heal_acc = 1000.0
	level._grenade_acc = 1000.0
	level._tick_wave(100.0)
	check(diff + "_failed_spawn_stays_pending", level._boss_spawned == 0 and level._boss_defeated == 0 and level.boss_attempts == 1 and level.remaining_bosses() == required and not level.can_finish_wave() and not level.finished)
	check(diff + "_deadline_caps_stops_spawns_supplies", level.wave_t == 60.0 and level.regular_attempts == 0 and level.pickups.is_empty() and level._spawn_acc == 1000.0 and level._shield_acc == 1000.0 and level._heal_acc == 1000.0 and level._grenade_acc == 1000.0)
	check(diff + "_deadline_hud_remaining_zero_timer", level.hud._objective.title == "消灭剩余鼠王" and level.hud._objective.progress == "剩余 %d 只 · 00秒" % required, {"title": level.hud._objective.title, "progress": level.hud._objective.progress})
	level.reject_boss = false
	level._tick_wave(1.0 / 60.0)
	freeze_zombies()
	check(diff + "_skipped_schedule_retries_all_configured", level._boss_spawned == required and level.zombies.size() == required and level.boss_attempts == required + 1, {"spawned": level._boss_spawned, "zombies": level.zombies.size()})
	var boss_hp: Array = []
	for z in level.zombies:
		boss_hp.append(z.hp)
	level._finale()
	await frames(500)
	var hp_unchanged := true
	for i in level.zombies.size():
		hp_unchanged = hp_unchanged and not level.zombies[i].dead and level.zombies[i].hp == boss_hp[i]
	check(diff + "_expiry_alive_boss_no_finale_or_result", not level.finished and Game.qa_routes.is_empty() and hp_unchanged and level._boss_defeated == 0)
	if diff == "normal":
		level.wave_t = 58.0
		level._spawn_acc = 0.0
		level._shield_acc = 0.0
		level._heal_acc = 0.0
		level._grenade_acc = 0.0
		level.set_process(true)
		get_tree().paused = true
		await frames(90)
		check("pause_holds_wave_and_boss_counts", level.wave_t == 58.0 and level._boss_spawned == 1 and level._boss_defeated == 0)
		get_tree().paused = false
		await frames(30)
		level.set_process(false)
		check("resume_advances_without_reset", level.wave_t > 58.0 and level.wave_t < 60.0 and level._boss_spawned == 1 and level._boss_defeated == 0, {"wave_t": level.wave_t})
	freeze_zombies()
	var bosses := level.zombies.filter(func(z: Zombie) -> bool: return z.boss)
	for i in bosses.size():
		var z: Zombie = bosses[i]
		kill_boss(z)
		var count_after_kill := level._boss_defeated
		var score_before_duplicate := int(Game.run.score)
		var effects_before_duplicate := death_side_effect_snapshot()
		level.on_zombie_killed(z)
		var effects_after_duplicate := death_side_effect_snapshot()
		Game.reset_time()
		check(diff + "_death_%d_counted_once" % (i + 1), count_after_kill == i + 1 and level._boss_defeated == count_after_kill and level._boss_dead_ids.size() == i + 1, {"defeated": level._boss_defeated, "duplicate_score_delta": int(Game.run.score) - score_before_duplicate})
		check(diff + "_death_%d_duplicate_no_side_effects" % (i + 1), effects_after_duplicate == effects_before_duplicate, {"before": effects_before_duplicate, "after": effects_after_duplicate})
		if i < required - 1:
			level._tick_wave(1.0 / 60.0)
			check(diff + "_partial_boss_clear_no_win", not level.finished and not level.can_finish_wave() and Game.qa_routes.is_empty() and level.remaining_bosses() == required - i - 1)
	if diff == "normal":
		level._finale()
		check("early_boss_clear_waits_for_timer", not level.finished and not level.can_finish_wave() and Game.qa_routes.is_empty())
	level.wave_t = 60.0
	Game.run.rescued = false
	level._finale()
	check(diff + "_rescue_prerequisite", not level.can_finish_wave() and not level.finished)
	Game.run.rescued = true
	level.player.dead = true
	level._tick_wave(1.0)
	level._finale()
	check(diff + "_dead_player_cannot_win", not level.can_finish_wave() and not level.finished and Game.qa_routes.is_empty())
	level.player.dead = false
	var dead_boss_spy := add_spy(true, true)
	var ordinary_spy := add_spy(false, false)
	check(diff + "_all_real_boss_deaths_enable_finish", level.can_finish_wave() and level.remaining_bosses() == 0 and level._boss_defeated == required)
	level._tick_wave(1.0 / 60.0)
	level._finale()
	level._finale()
	check(diff + "_finale_starts_once", level.finished and not level.wave_on and not level.can_finish_wave())
	await frames(600)
	check(diff + "_results_success_exactly_once", Game.qa_routes.size() == 1 and Game.qa_routes[0].screen == "results" and Game.qa_routes[0].data.get("success", false), {"routes": Game.qa_routes.duplicate(true)})
	check(diff + "_cleanup_excludes_every_boss", dead_boss_spy.cleanup_requests == 0 and ordinary_spy.cleanup_requests == 1 and level._boss_defeated == required, {"boss_cleanup_requests": dead_boss_spy.cleanup_requests, "ordinary_cleanup_requests": ordinary_spy.cleanup_requests})
	await teardown()

func run_failure() -> void:
	await setup("normal")
	activate_wave()
	level._tick_wave(60.0)
	freeze_zombies()
	for z in level.zombies.duplicate():
		kill_boss(z)
	level.player.dead = true
	level.on_player_dead()
	level._tick_wave(1.0)
	level._finale()
	check("failure_before_victory_locks_success_gate", level.finished and not level.can_finish_wave())
	await frames(240)
	check("player_death_routes_failure_only", Game.qa_routes.size() == 1 and Game.qa_routes[0].screen == "results" and not Game.qa_routes[0].data.get("success", true), {"routes": Game.qa_routes.duplicate(true)})
	await teardown()

func save_report() -> void:
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"checks": checks, "failed": failed, "transitions": transitions, "wall_seconds": (Time.get_ticks_msec() - wall_start) / 1000.0, "scope": "Production Level mission-rule execution; actual spawned and take_hit-defeated bosses; Game.goto recorder in fixture copy; frozen actor physics; not difficulty or navigation proof"}, "\t"))
	else:
		push_error("Cannot write report: " + report_path)
		failed += 1

func run_all() -> void:
	await run_difficulty("easy", 1)
	await run_difficulty("normal", 1)
	await run_difficulty("hard", 2)
	await run_difficulty("insane", 3)
	await run_failure()
	save_report()
	print("[victory-qa] RESULT ", JSON.stringify({"checks": checks.size(), "failed": failed, "report": report_path}))
	get_tree().quit(0 if failed == 0 else 1)
