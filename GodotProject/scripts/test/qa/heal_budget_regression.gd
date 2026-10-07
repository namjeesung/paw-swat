extends Node
## Development-only actual-class healing budget QA; never uses --god or online score requests.
var checks: Array[Dictionary] = []
var holder: Node
var level: Level
var p: Player
var output_path := "user://heal-budget-regression-report.json"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Online.server_url = ""
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.wait_time = 40.0
	watchdog.ignore_time_scale = true
	watchdog.timeout.connect(func(): print("[heal-qa] TIMEOUT"); get_tree().quit(2))
	add_child(watchdog)
	watchdog.start()
	holder = Node.new()
	holder.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(holder)
	call_deferred("_run")

func check(name: String, ok: bool, details: Dictionary = {}) -> void:
	checks.append({"name": name, "passed": ok, "details": details})
	print("[heal-qa] ", "PASS " if ok else "FAIL ", name, " ", JSON.stringify(details))

func wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func stop_simulation() -> void:
	level.set_process(false)
	p.set_physics_process(false)
	p.bot_enabled = true
	p.bot = {"move": Vector2.ZERO, "shoot": false, "aim": false}
	for e in level.enemies:
		e.set_physics_process(false)
	level.hostage.set_physics_process(false)

func start_level(diff: String) -> void:
	var old := level
	Game.reset_time()
	get_tree().paused = false
	Game.set_difficulty(diff, false)
	Game.autotest = false
	Game.container = holder
	level = Level.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	Game.current = level
	holder.add_child(level)
	p = level.player
	stop_simulation()
	if is_instance_valid(old):
		old.queue_free()

func count_ground(kind: String) -> int:
	return level.pickups.filter(func(pk: Pickup): return is_instance_valid(pk) and not pk.taken and pk.kind == kind).size()

func ground_heal() -> Pickup:
	for pk in level.pickups:
		if is_instance_valid(pk) and not pk.taken and pk.kind == "heal":
			return pk
	return null

func quiet_new_pickups() -> void:
	for pk in level.pickups:
		pk.set_process(false)

func spawn_heal() -> Pickup:
	var pk := level.spawn_pickup(p.global_position + Vector3.RIGHT * 3.0, "heal", "", 0.0, p.global_position)
	if pk != null:
		pk.set_process(false)
	return pk

func collect_with_deficit(pk: Pickup, deficit: float) -> void:
	p.hp = p.max_hp - deficit
	pk._collect()

func label_texts() -> Array[String]:
	var labels: Array[String] = []
	for child in level.find_children("*", "Label3D", true, false):
		labels.append(child.text)
	return labels

func periodic_heal() -> void:
	level.wave_on = true
	level.wave_fired = true
	level.wave_t = 0.0
	level._heal_acc = Game.dv("heal_every") - 0.01
	level._tick_wave(0.02)
	quiet_new_pickups()

func kill_real_boss() -> void:
	var z := Zombie.new()
	z.boss = true
	z.level = level
	level.add_child(z)
	z.set_physics_process(false)
	z.global_position = p.global_position + Vector3.RIGHT * 4.0
	level.zombies.append(z)
	z._rise = 0.0
	z._die()
	Game.reset_time()
	quiet_new_pickups()

func _run() -> void:
	check("no_god_arguments", not OS.get_cmdline_user_args().has("--god"), {"arguments": Array(OS.get_cmdline_user_args())})
	var limits := {"easy": 1, "normal": 2, "hard": 3, "insane": 4}
	for diff: String in limits:
		start_level(diff)
		var expected: int = limits[diff]
		check("%s_captured_limit_%d" % [diff, expected], level.heal_drop_limit == expected and level.heal_drops_spawned == 0 and int(Game.run.get("heal_drops", -1)) == 0, {"limit": level.heal_drop_limit, "spawned": level.heal_drops_spawned})
		for i in range(1, expected + 1):
			var pk := spawn_heal()
			check("%s_spawn_%d_spends_budget" % [diff, i], pk != null and level.heal_drops_spawned == i and int(Game.run.get("heal_drops", -1)) == i and count_ground("heal") == 1, {"spawned": level.heal_drops_spawned, "ground": count_ground("heal")})
			if pk == null:
				break
			var denied := spawn_heal()
			check("%s_spawn_%d_single_ground_cap" % [diff, i], denied == null and level.heal_drops_spawned == i and count_ground("heal") == 1)
			p.hp = p.max_hp
			pk.global_position = p.global_position
			pk._process(0.01)
			check("%s_spawn_%d_full_hp_keeps_loot" % [diff, i], not pk.taken and level.pickups.has(pk) and level.heal_drops_spawned == i and is_equal_approx(p.hp, p.max_hp), {"taken": pk.taken, "spawned": level.heal_drops_spawned})
			var full_hp_notice_tween: Tween = level.hud._toast_tw
			pk._process(0.01)
			check("%s_spawn_%d_full_hp_notice_only_once" % [diff, i], pk._full_heal_notice and level.hud._toast_label.text.contains("生命已满") and level.hud._toast_tw == full_hp_notice_tween)
			var before_labels := label_texts()
			collect_with_deficit(pk, 60.0)
			var healed_hp := p.max_hp - 25.0
			var after_labels := label_texts()
			check("%s_spawn_%d_heals_once_35" % [diff, i], pk.taken and not level.pickups.has(pk) and is_equal_approx(p.hp, healed_hp) and level.heal_drops_spawned == i, {"hp": p.hp, "expected_hp": healed_hp, "spawned": level.heal_drops_spawned})
			check("%s_spawn_%d_feedback_actual_35" % [diff, i], after_labels.count("+35") > before_labels.count("+35"), {"new_plus_35_labels": after_labels.count("+35") - before_labels.count("+35")})
			pk._collect()
			check("%s_spawn_%d_repeated_collection_is_idempotent" % [diff, i], is_equal_approx(p.hp, healed_hp) and level.heal_drops_spawned == i and label_texts().size() == after_labels.size(), {"hp": p.hp, "labels_before": after_labels.size(), "labels_after": label_texts().size()})
		check("%s_global_spawn_cap_exhausted" % diff, spawn_heal() == null and level.heal_drops_spawned == expected and count_ground("heal") == 0, {"spawned": level.heal_drops_spawned, "limit": expected})
		var shield := level.spawn_pickup(p.global_position + Vector3.LEFT * 3.0, "shield", "", 0.0, p.global_position)
		if shield:
			shield.set_process(false)
		var gun := level.spawn_pickup(p.global_position + Vector3.FORWARD * 3.0, "weapon", "shotgun", 0.0, p.global_position)
		if gun:
			gun.set_process(false)
		check("%s_heal_cap_does_not_block_shield_or_weapon" % diff, shield != null and gun != null and level.heal_drops_spawned == expected)
		p.clear_shield()
		check("%s_shield_grant_independent_of_heal_budget" % diff, p.grant_shield() and level.heal_drops_spawned == expected)
		p.clear_shield()
	await check_health_cap_and_feedback()
	await check_mixed_sources()
	await check_spawn_not_collection()
	await check_pause_restart_and_capture()
	check_invalid_state_guards()
	check("all_109_behavior_assertions_executed", checks.size() == 109, {"executed_behavior_assertions": checks.size(), "expected": 109})
	var failed := checks.filter(func(c: Dictionary): return not c.passed)
	var report := {"engine": Engine.get_version_info(), "checks": checks, "passed": failed.is_empty(), "failed": failed.size(), "scope": "Actual production healing logic in isolated headless copy; no audible audio or browser claim"}
	var path := ProjectSettings.globalize_path(output_path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[heal-qa] RESULT ", JSON.stringify({"passed": failed.is_empty(), "checks": checks.size(), "failed": failed.size(), "report": path}))
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
	await wait_real(0.5)
	await get_tree().process_frame
	get_tree().quit(0 if failed.is_empty() else 1)

func check_health_cap_and_feedback() -> void:
	start_level("normal")
	var pk := spawn_heal()
	if pk == null:
		check("health_cap_pickup_available", false)
		return
	var before := label_texts()
	collect_with_deficit(pk, 10.0)
	var after := label_texts()
	check("near_full_health_capped_at_max", is_equal_approx(p.hp, p.max_hp), {"hp": p.hp, "max_hp": p.max_hp})
	check("near_full_feedback_reports_actual_10", after.count("+10") > before.count("+10") and after.count("+35") == before.count("+35"), {"new_plus_10_labels": after.count("+10") - before.count("+10"), "new_plus_35_labels": after.count("+35") - before.count("+35")})

func check_mixed_sources() -> void:
	start_level("insane")
	periodic_heal()
	check("periodic_source_spends_shared_budget", level.heal_drops_spawned == 1 and count_ground("heal") == 1)
	kill_real_boss()
	check("boss_source_cannot_overlap_periodic_ground_loot", level.heal_drops_spawned == 1 and count_ground("heal") == 1)
	collect_with_deficit(ground_heal(), 35.0)
	kill_real_boss()
	check("boss_source_spends_same_global_budget", level.heal_drops_spawned == 2 and count_ground("heal") == 1)
	check("future_central_source_cannot_overlap_boss_ground_loot", spawn_heal() == null and level.heal_drops_spawned == 2 and count_ground("heal") == 1)
	collect_with_deficit(ground_heal(), 35.0)
	var third := spawn_heal()
	check("future_central_source_uses_shared_budget", third != null and level.heal_drops_spawned == 3 and count_ground("heal") == 1)
	if third:
		collect_with_deficit(third, 35.0)
	periodic_heal()
	check("periodic_source_reaches_four_spawn_cap", level.heal_drops_spawned == 4 and count_ground("heal") == 1)
	collect_with_deficit(ground_heal(), 35.0)
	kill_real_boss()
	periodic_heal()
	var extra := spawn_heal()
	check("all_sources_reject_after_global_budget_exhausted", extra == null and level.heal_drops_spawned == 4 and count_ground("heal") == 0, {"spawned": level.heal_drops_spawned, "ground": count_ground("heal")})

func check_spawn_not_collection() -> void:
	start_level("easy")
	var pk := spawn_heal()
	check("uncollected_spawn_already_counts_against_budget", pk != null and not pk.taken and level.heal_drops_spawned == 1)
	if pk:
		level.pickups.erase(pk)
		pk.queue_free()
	check("discarded_uncollected_loot_does_not_refund_budget", spawn_heal() == null and level.heal_drops_spawned == 1 and count_ground("heal") == 0)

func check_pause_restart_and_capture() -> void:
	start_level("hard")
	var pk := spawn_heal()
	level.pause_menu.open()
	await wait_real(0.2)
	check("pause_retains_spawn_budget_and_ground_loot", get_tree().paused and level.heal_drop_limit == 3 and level.heal_drops_spawned == 1 and level.pickups.has(pk) and not pk.taken)
	level.pause_menu.close()
	await wait_real(0.3)
	check("resume_retains_spawn_budget", not get_tree().paused and level.heal_drop_limit == 3 and level.heal_drops_spawned == 1)
	Game.set_difficulty("insane", false)
	check("midrun_difficulty_change_does_not_change_captured_budget", level.heal_drop_limit == 3 and String(Game.run.difficulty) == "hard", {"limit": level.heal_drop_limit, "run_difficulty": Game.run.difficulty, "selected_difficulty": Game.difficulty})
	level.pause_menu.open()
	Game.goto("level")
	while Game.current == level:
		await get_tree().process_frame
	level = Game.current
	p = level.player
	stop_simulation()
	while Game._busy:
		await get_tree().process_frame
	check("actual_restart_captures_selected_budget_and_resets_spawns", level.heal_drop_limit == 4 and level.heal_drops_spawned == 0 and count_ground("heal") == 0 and not get_tree().paused and String(Game.run.difficulty) == "insane", {"limit": level.heal_drop_limit, "spawned": level.heal_drops_spawned, "ground": count_ground("heal"), "paused": get_tree().paused})
	start_level("normal")
	check("new_run_resets_selected_normal_budget", level.heal_drop_limit == 2 and level.heal_drops_spawned == 0 and count_ground("heal") == 0)

func check_invalid_state_guards() -> void:
	start_level("normal")
	level.finished = true
	check("finished_state_rejects_new_heal_without_spending", spawn_heal() == null and level.heal_drops_spawned == 0 and int(Game.run.heal_drops) == 0)
	level.finished = false
	p.dead = true
	check("dead_player_rejects_new_heal_without_spending", spawn_heal() == null and level.heal_drops_spawned == 0 and int(Game.run.heal_drops) == 0)
	p.dead = false
	level.player = null
	check("missing_player_rejects_new_heal_without_spending", spawn_heal() == null and level.heal_drops_spawned == 0 and int(Game.run.heal_drops) == 0)
	level.player = p
	var pk := spawn_heal()
	if pk == null:
		check("invalid_collection_guard_pickup_available", false)
		return
	p.hp = p.max_hp - 35.0
	p.dead = true
	pk._collect()
	check("dead_player_cannot_collect_stale_heal", not pk.taken and level.pickups.has(pk) and is_equal_approx(p.hp, p.max_hp - 35.0) and level.heal_drops_spawned == 1)
	p.dead = false
	level.finished = true
	pk._collect()
	check("finished_level_cannot_collect_stale_heal", not pk.taken and level.pickups.has(pk) and is_equal_approx(p.hp, p.max_hp - 35.0) and level.heal_drops_spawned == 1)
	level.finished = false
	pk._collect()
	check("resumed_valid_state_collects_once_without_spending_again", pk.taken and is_equal_approx(p.hp, p.max_hp) and level.heal_drops_spawned == 1 and int(Game.run.heal_drops) == 1)
