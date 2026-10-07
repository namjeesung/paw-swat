extends Node
## Integrated actual-class loot tests; isolated copy, no production edits or rank writes.
var holder: Node
var level: Level
var checks: Array[Dictionary] = []
var failed := 0
var report_path := "user://loot-report.json"
var wall_start := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.autotest = false
	Game.touch = false
	Online.server_url = ""
	wall_start = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.substr(9)
	holder = Node.new()
	holder.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(holder)
	call_deferred("run_all")

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - wall_start > 90000:
		check("wall_timeout", false)
		finish()

func check(id: String, good: bool, details: Dictionary = {}) -> void:
	checks.append({"id": id, "passed": good, "details": details})
	if not good:
		failed += 1
	print("[loot-qa] ", "PASS " if good else "FAIL ", id, " ", JSON.stringify(details))

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func freeze() -> void:
	level.set_process(false)
	level.player.set_physics_process(false)
	level.player.bot_enabled = true
	level.hostage.set_physics_process(false)
	for e in level.enemies:
		e.set_physics_process(false)
	for z in level.zombies:
		z.set_physics_process(false)
	for pk in level.pickups:
		pk.set_process(false)

func setup(diff := "normal") -> void:
	Game.reset_time()
	Game.set_difficulty(diff, false)
	get_tree().paused = false
	Game.container = holder
	level = Level.new()
	Game.current = level
	holder.add_child(level)
	freeze()
	level.player.position = Vector3(0, 0, 16)
	await frames(3)

func teardown() -> void:
	get_tree().paused = false
	Game.reset_time()
	Game.current = null
	level.queue_free()
	level = null
	await frames(5)

func loot(kind: String, weapon := "", height := 0.0) -> Pickup:
	var pk := level.spawn_pickup(Vector3(5, 0, 16), kind, weapon, height)
	if pk:
		pk.set_process(false)
	return pk

func ground(kind: String) -> Array[Pickup]:
	var out: Array[Pickup] = []
	for pk in level.pickups:
		if is_instance_valid(pk) and not pk.taken and pk.kind == kind:
			out.append(pk)
	return out

func wave_tick(delta := 0.01) -> void:
	level.wave_on = true
	level.wave_fired = true
	level.wave_t = 0.0
	level._tick_wave(delta)
	freeze()

func grenade_sources() -> void:
	await setup()
	check("central_caps_and_interval", Level.GRENADE_DROP_LIMIT == 2 and Level.GRENADE_GROUND_CAP == 1 and Level.OPTIONAL_WEAPON_DROP_LIMIT == 3 and Level.OPTIONAL_GROUND_CAP == 4 and Level.GRENADE_SUPPLY_INTERVAL == 24.0)
	check("first_grenade_roll_guaranteed_without_spending", level.roll_grenade_drop() and level.roll_grenade_drop() and level._grenade_drops == 0)
	level.player.grenades = Player.MAX_GRENADES
	check("full_inventory_rejects_spawn_without_spending", loot("grenade") == null and level._grenade_drops == 0 and not level.roll_grenade_drop())
	level.player.grenades = 0
	var enemies_down := 0
	for enemy in level.enemies:
		if enemy.kind == "rat":
			enemy.drop = ""
			enemy._go_down(Vector3.RIGHT)
			enemies_down += 1
	Game.reset_time()
	freeze()
	check("burst_enemy_drops_one_successful_crate", enemies_down >= 4 and level._grenade_drops == 1 and ground("grenade").size() == 1, {"enemies_down": enemies_down, "spawned": level._grenade_drops, "ground": ground("grenade").size()})
	check("duplicate_ground_spawn_does_not_spend", loot("grenade") == null and level._grenade_drops == 1)
	level._grenade_acc = 24.1
	wave_tick()
	check("enemy_airdrop_overlap_shares_ground_and_budget", level._grenade_drops == 1 and ground("grenade").size() == 1)
	var first := ground("grenade")[0]
	first._collect()
	check("first_grenade_collection_gives_two_without_refund", first.taken and level.player.grenades == 2 and level._grenade_drops == 1 and ground("grenade").is_empty())
	level.player.grenades = 0
	seed(20261006)
	var success_rolls := 0
	for i in 10000:
		if level.roll_grenade_drop():
			success_rolls += 1
	check("later_enemy_roll_is_rare_and_nonspending", success_rolls >= 1000 and success_rolls <= 1400 and level._grenade_drops == 1, {"successes_in_10000_seeded_rolls": success_rolls})
	wave_tick()
	check("airdrop_spends_second_shared_successful_spawn", level._grenade_drops == 2 and ground("grenade").size() == 1)
	var second := ground("grenade")[0]
	level.player.grenades = Player.MAX_GRENADES
	second._collect()
	check("existing_crate_left_on_ground_when_inventory_full", not second.taken and level.pickups.has(second) and level.player.grenades == Player.MAX_GRENADES)
	level.player.grenades = 2
	second._collect()
	check("partial_inventory_collection_caps_at_three", second.taken and level.player.grenades == Player.MAX_GRENADES and not level.pickups.has(second))
	level.player.grenades = 0
	level._grenade_acc = 100.0
	wave_tick()
	check("all_sources_stop_at_two_even_after_use", loot("grenade") == null and not level.roll_grenade_drop() and level._grenade_drops == 2 and ground("grenade").is_empty())
	await teardown()
	await setup()
	level._grenade_acc = 23.99
	wave_tick(0.005)
	check("airdrop_not_before_24_seconds", level._grenade_drops == 0 and ground("grenade").is_empty())
	wave_tick(0.02)
	check("airdrop_after_24_seconds", level._grenade_drops == 1 and ground("grenade").size() == 1)
	await teardown()

func weapon_and_essential_caps() -> void:
	await setup()
	for i in 3:
		var pk := loot("weapon", ["shotgun", "laser", "rocket"][i])
		check("optional_weapon_%d_spends_successful_spawn" % (i + 1), pk != null and level._weapon_drops == i + 1 and level.optional_weapon_on_ground())
		check("optional_weapon_%d_ground_rejection_nonspending" % (i + 1), loot("weapon", "shotgun") == null and level._weapon_drops == i + 1)
		pk._collect()
		check("optional_weapon_%d_collect_keeps_budget" % (i + 1), pk.taken and level._weapon_drops == i + 1 and not level.optional_weapon_on_ground())
	check("optional_weapon_cap_three", loot("weapon", "shotgun") == null and level._weapon_drops == 3)
	await teardown()
	await setup()
	var gun := loot("weapon", "shotgun")
	var grenade := loot("grenade")
	var heal := loot("heal")
	var shield := loot("shield")
	check("four_type_optional_ground_cap_reached", gun != null and grenade != null and heal != null and shield != null and level.optional_pickups_on_ground() == 4)
	var before := [level._grenade_drops, level._weapon_drops, level.heal_drops_spawned]
	check("full_optional_cap_rejects_without_spending", loot("weapon", "laser") == null and loot("grenade") == null and loot("heal") == null and loot("shield") == null and before == [level._grenade_drops, level._weapon_drops, level.heal_drops_spawned])
	var essential := loot("weapon", "gatling", 9.0)
	check("essential_gatling_bypasses_full_optional_cap", essential != null and level.pickups.size() == 5 and level.optional_pickups_on_ground() == 4 and before == [level._grenade_drops, level._weapon_drops, level.heal_drops_spawned])
	essential._landed = true
	essential.position.y = 0.0
	essential._process(300.0)
	check("essential_gatling_no_ttl_and_no_optional_budget", not essential.taken and not essential.is_queued_for_deletion() and level.pickups.has(essential) and essential._ground_t == 0.0 and level._weapon_drops == 1)
	await teardown()

func ttl_and_pause() -> void:
	await setup()
	for spec in [["grenade", "", 20.0], ["weapon", "shotgun", 30.0], ["shield", "", 12.0]]:
		var pk := loot(spec[0], spec[1])
		var lifetime: float = spec[2]
		pk._process(lifetime - 0.01)
		check(spec[0] + "_ttl_survives_before_deadline", not pk.is_queued_for_deletion() and level.pickups.has(pk))
		pk._process(0.02)
		check(spec[0] + "_ttl_erases_pickup_list_at_deadline", pk.is_queued_for_deletion() and not level.pickups.has(pk))
		await frames(2)
		check(spec[0] + "_ttl_node_freed", not is_instance_valid(pk))
	check("expiration_does_not_refund_spawn_budgets", level._grenade_drops == 1 and level._weapon_drops == 1)
	var heal := loot("heal")
	var essential := loot("weapon", "gatling")
	heal._process(300.0)
	essential._process(300.0)
	check("heal_and_essential_remain_persistent", is_instance_valid(heal) and is_instance_valid(essential) and level.pickups.has(heal) and level.pickups.has(essential) and heal._ground_t == 0.0 and essential._ground_t == 0.0)
	var falling := loot("grenade", "", 8.0)
	falling._process(100.0)
	check("falling_pickup_ttl_waits_for_landing", falling._ground_t == 0.0 and not falling.is_queued_for_deletion())
	falling._landed = true
	falling.position.y = 0.0
	falling.set_process(true)
	await wait_real(0.3)
	get_tree().paused = true
	var paused_ground_t := falling._ground_t
	await wait_real(0.6)
	check("actual_pause_freezes_ground_ttl", is_equal_approx(falling._ground_t, paused_ground_t) and level.pickups.has(falling))
	get_tree().paused = false
	Game.bullet_time(10.0)
	var slow_before := falling._ground_t
	await wait_real(1.0)
	var real_elapsed := falling._ground_t - slow_before
	check("actual_slowmo_does_not_extend_ground_ttl", real_elapsed > 0.9 and real_elapsed < 1.1, {"ground_t_elapsed": real_elapsed, "timescale": Engine.time_scale})
	Game.reset_time()
	falling.set_process(false)
	await teardown()

func rejection_and_restart() -> void:
	await setup("hard")
	level.finished = true
	check("finished_rejections_spend_no_budget", loot("grenade") == null and loot("weapon", "shotgun") == null and loot("weapon", "gatling") == null and level._grenade_drops == 0 and level._weapon_drops == 0)
	level.finished = false
	level.player.dead = true
	check("dead_player_rejections_spend_no_budget", loot("grenade") == null and loot("weapon", "shotgun") == null and level._grenade_drops == 0 and level._weapon_drops == 0)
	level.player.dead = false
	loot("grenade")
	loot("weapon", "shotgun")
	loot("heal")
	check("pre_restart_budgets_are_spent", level._grenade_drops == 1 and level._weapon_drops == 1 and level.heal_drops_spawned == 1)
	var old := level
	Game.set_difficulty("insane", false)
	level.pause_menu.open()
	Game.goto("level")
	while Game.current == old:
		await get_tree().process_frame
	level = Game.current
	freeze()
	while Game._busy:
		await get_tree().process_frame
	check("actual_restart_clears_budgets_and_ground_loot", level._grenade_drops == 0 and level._weapon_drops == 0 and level.heal_drops_spawned == 0 and level.pickups.is_empty() and level.optional_pickups_on_ground() == 0 and not get_tree().paused and level.heal_drop_limit == 4 and String(Game.run.difficulty) == "insane")
	await teardown()

func finish() -> void:
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"checks": checks, "failed": failed, "wall_seconds": (Time.get_ticks_msec() - wall_start) / 1000.0, "scope": "Actual production Level/Enemy/Pickup/Player central loot logic and real pause/slowmo/restart in isolated candidate copy; no production changes, rank saves or performance claim"}, "\t"))
	print("[loot-qa] RESULT ", JSON.stringify({"checks": checks.size(), "failed": failed, "report": report_path}))
	get_tree().quit(0 if failed == 0 else 1)

func run_all() -> void:
	await grenade_sources()
	await weapon_and_essential_caps()
	await ttl_and_pause()
	await rejection_and_restart()
	await frames(180)
	finish()
