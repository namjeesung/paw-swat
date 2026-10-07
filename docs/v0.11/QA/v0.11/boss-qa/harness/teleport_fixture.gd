extends Node
## Runs live production Zombie CharacterBody3D physics at the Web/mobile 60Hz setting.
## Dynamic colliders simulate doors/temporary blockages not represented in a baked map.
const DT := 1.0 / 60.0
var holder: Node
var level: Level
var boss_actor: Zombie
var checks: Array[Dictionary] = []
var traces: Array[Dictionary] = []
var failed := 0
var wall_start := 0
var report_path := "user://teleport-report.json"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.physics_ticks_per_second = 60
	Online.server_url = ""
	Game.autotest = false
	Game.touch = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.substr(9)
	wall_start = Time.get_ticks_msec()
	holder = Node.new()
	holder.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(holder)
	call_deferred("run_all")

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - wall_start > 120000:
		check("wall_timeout", false)
		save_report()
		get_tree().quit(2)

func check(id: String, good: bool, detail: Dictionary = {}) -> void:
	checks.append({"id": id, "passed": good, "detail": detail})
	if not good:
		failed += 1
	print("[teleport-qa] ", "PASS " if good else "FAIL ", id, " ", JSON.stringify(detail))

func vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

func step(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func setup() -> void:
	Game.reset_time()
	Game.set_difficulty("normal", false)
	Game.container = holder
	level = Level.new()
	Game.current = level
	holder.add_child(level)
	level.set_process(false)
	level.player.set_physics_process(false)
	level.player.bot_enabled = true
	level.player.position = Vector3(0, 0, 16)
	level.player.max_hp = 100000
	level.player.hp = level.player.max_hp
	level.hostage.set_physics_process(false)
	for enemy in level.enemies:
		enemy.set_physics_process(false)
	await step(6)

func teardown() -> void:
	get_tree().paused = false
	Game.reset_time()
	Game.current = null
	level.queue_free()
	level = null
	boss_actor = null
	await step(5)

func spawn(pos: Vector3, is_boss := true) -> Zombie:
	var z := Zombie.new()
	z.boss = is_boss
	z.level = level
	z.position = pos
	level.add_child(z)
	level.zombies.append(z)
	z._rise = 0.0
	return z

func block_box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Bullet.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	level.add_child(body)
	body.position = pos + Vector3(0, size.y * 0.5, 0)
	return body

func cage(pos: Vector3, half_width := 0.95) -> Array[StaticBody3D]:
	var bodies: Array[StaticBody3D] = []
	for sign_value in [-1.0, 1.0]:
		bodies.append(block_box(pos + Vector3(half_width * sign_value, 0, 0), Vector3(0.2, 2.6, half_width * 2.0 + 0.2)))
		bodies.append(block_box(pos + Vector3(0, 0, half_width * sign_value), Vector3(half_width * 2.0 + 0.2, 2.6, 0.2)))
	return bodies

func overlap(z: Zombie) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.7 if z.boss else 0.32
	capsule.height = 2.2 if z.boss else 1.0
	q.shape = capsule
	q.transform = Transform3D(Basis.IDENTITY, z.global_position + Vector3(0, capsule.height * 0.5 + 0.06, 0))
	q.margin = 0.01
	q.exclude = [z.get_rid()]
	q.collision_mask = Bullet.LAYER_WORLD | Bullet.LAYER_LOWCOVER | Bullet.LAYER_PLAYER | Bullet.LAYER_ENEMY
	return not z.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

func wait_warning(max_seconds := 5.0) -> float:
	var elapsed := 0.0
	while elapsed < max_seconds:
		await step(1)
		elapsed += DT
		if boss_actor._teleport_left > 0.0:
			return elapsed
	return -1.0

func wait_teleport(previous: int, max_seconds := 4.0) -> float:
	var elapsed := 0.0
	while elapsed < max_seconds:
		await step(1)
		elapsed += DT
		if boss_actor._teleport_count > previous:
			return elapsed
	return -1.0

func blocked_recovery() -> void:
	await setup()
	var origin := Vector3(-8, 0, 16)
	cage(origin)
	boss_actor = spawn(origin)
	await step(2)
	check("initial_exact_capsule_clear", not overlap(boss_actor))
	var hp := boss_actor.hp
	var speed := boss_actor.speed
	var warn_at := await wait_warning()
	check("stationary_blockage_repaths_then_warns", warn_at >= 2.4 and warn_at < 3.4 and boss_actor._forced_repaths > 0 and boss_actor._teleport_count == 0, {"warning_seconds": warn_at, "forced_repaths": boss_actor._forced_repaths})
	if warn_at < 0:
		await teardown()
		return
	check("one_second_visible_marker", is_instance_valid(boss_actor._teleport_marker) and boss_actor._teleport_marker.get_child_count() == 2 and boss_actor._teleport_left > 0.95)
	var destination := boss_actor._teleport_destination
	var before := boss_actor.global_position
	await step(30)
	check("warning_no_early_jump", boss_actor._teleport_count == 0 and boss_actor.global_position.distance_to(before) < 0.4)
	boss_actor.take_hit(1.0, Vector3.RIGHT, level.player.global_position, level.player)
	Game.reset_time()
	check("warning_has_no_invulnerability", boss_actor.hp == hp - 1.0)
	var landed_at := await wait_teleport(0)
	var landing := boss_actor.global_position
	var distance := landing.distance_to(level.player.global_position)
	check("lands_beside_player_clear_and_reachable", landed_at > 0.4 and boss_actor._teleport_count == 1 and distance >= 2.0 and distance <= 3.0 and not overlap(boss_actor) and boss_actor._teleport_spot_valid(landing), {"landing": vec(landing), "destination": vec(destination), "distance": distance})
	check("teleport_preserves_hp_speed_sets_cooldown", boss_actor.hp == hp - 1.0 and boss_actor.speed == speed and boss_actor._teleport_cd > 7.95 and boss_actor._attack_recovery > 0.58)
	var approach := (landing - level.player.global_position).normalized()
	level.player.global_position = landing - approach * 1.3
	boss_actor.take_hit(1.0, Vector3.RIGHT, level.player.global_position, level.player)
	Game.reset_time()
	check("recovery_has_no_invulnerability", boss_actor.hp == hp - 2.0)
	await step(30)
	check("recovery_prevents_attack_for_half_second", boss_actor._wind <= 0.0 and level.player.hp == level.player.max_hp)
	await step(12)
	check("attacks_resume_after_brief_recovery", boss_actor._wind > 0.0 and boss_actor._attack_recovery <= 0.0)
	traces.append({"case": "blocked_recovery", "origin": vec(origin), "warn_seconds": warn_at, "landing": vec(landing), "hp": boss_actor.hp, "speed": boss_actor.speed})
	await teardown()

func moving_and_blocked_landing() -> void:
	await setup()
	cage(Vector3(-8, 0, 16))
	boss_actor = spawn(Vector3(-8, 0, 16))
	var warn_at := await wait_warning()
	check("moving_target_initial_warning", warn_at > 0)
	var origin := boss_actor.global_position
	level.player.position = Vector3(6, 0, 16)
	await step(75)
	check("warning_expiry_revalidates_player_position", boss_actor._teleport_count == 0 and boss_actor._teleport_left <= 0.0 and boss_actor.global_position.distance_to(origin) < 0.5)
	warn_at = await wait_warning(5.0)
	check("retarget_after_cancel_gets_new_warning", warn_at > 0 and boss_actor._teleport_destination.distance_to(level.player.global_position) >= 2.0 and boss_actor._teleport_destination.distance_to(level.player.global_position) <= 3.0)
	var obstruction := block_box(boss_actor._teleport_destination, Vector3(1.6, 2.5, 1.6))
	await step(75)
	check("warning_expiry_revalidates_new_wall", boss_actor._teleport_count == 0 and boss_actor._teleport_left <= 0.0)
	obstruction.queue_free()
	warn_at = await wait_warning(5.0)
	var landed_at := await wait_teleport(0)
	check("moving_target_recovery_eventually_safe", warn_at > 0 and landed_at > 0 and boss_actor._teleport_count == 1 and not overlap(boss_actor) and boss_actor.global_position.distance_to(level.player.global_position) >= 2.0 and boss_actor.global_position.distance_to(level.player.global_position) <= 3.0)
	await teardown()

func no_safe_spot() -> void:
	await setup()
	cage(Vector3(-8, 0, 16))
	cage(level.player.global_position)
	boss_actor = spawn(Vector3(-8, 0, 16))
	await step(420)
	check("no_safe_destination_never_forces_teleport", boss_actor._teleport_count == 0 and boss_actor._teleport_left <= 0.0 and boss_actor._find_teleport_destination() == Vector3.INF and boss_actor._forced_repaths > 0 and boss_actor.global_position.distance_to(Vector3(-8, 0, 16)) < 0.5, {"forced_repaths": boss_actor._forced_repaths, "position": vec(boss_actor.global_position)})
	check("invalid_player_overlap_wall_infinite_spots_rejected", not boss_actor._teleport_spot_valid(level.player.global_position) and not boss_actor._teleport_spot_valid(Vector3(-12, 0, 8)) and not boss_actor._teleport_spot_valid(Vector3.INF))
	await teardown()

func oscillation() -> void:
	await setup()
	var origin := Vector3(-8, 0, 17)
	cage(origin, 1.1)
	boss_actor = spawn(origin)
	var distance_travelled := 0.0
	var previous := boss_actor.global_position
	var warning := false
	for i in 360:
		level.player.position = Vector3(0 if (i / 30) % 2 == 0 else -14, 0, 17)
		await step(1)
		distance_travelled += boss_actor.global_position.distance_to(previous)
		previous = boss_actor.global_position
		if boss_actor._teleport_left > 0.0:
			warning = true
			break
	check("oscillation_detected_by_net_progress", warning and distance_travelled > 0.6 and boss_actor.global_position.distance_to(origin) < 0.5, {"travelled": distance_travelled, "net": boss_actor.global_position.distance_to(origin), "warning": warning})
	await teardown()

func cooldown() -> void:
	await setup()
	cage(Vector3(-8, 0, 16))
	boss_actor = spawn(Vector3(-8, 0, 16))
	await wait_warning()
	await wait_teleport(0)
	var landing := boss_actor.global_position
	cage(landing, 0.9)
	await step(420)
	check("cooldown_prevents_repeat_teleport_for_seven_seconds", boss_actor._teleport_count == 1 and boss_actor._teleport_left <= 0.0 and boss_actor._teleport_cd > 0.9)
	var warning := await wait_warning(3.0)
	var jumped := await wait_teleport(1, 3.0)
	check("cooldown_allows_later_warned_recovery", warning > 0.7 and jumped >= 0.9 and boss_actor._teleport_count == 2 and not overlap(boss_actor), {"warning_after_seven_seconds": warning, "warning_duration": jumped})
	await teardown()

func suppressed_states() -> void:
	await setup()
	cage(Vector3(-8, 0, 16))
	boss_actor = spawn(Vector3(-8, 0, 16))
	boss_actor._wind = 4.0
	await step(180)
	check("attack_windup_never_counts_as_stuck", boss_actor._teleport_count == 0 and boss_actor._teleport_left == 0.0 and boss_actor._progress_positions.is_empty())
	boss_actor._wind = 0.0
	boss_actor.stun(4.0)
	await step(180)
	check("stun_never_counts_as_stuck", boss_actor._teleport_count == 0 and boss_actor._teleport_left == 0.0 and boss_actor._progress_positions.is_empty())
	boss_actor._stun = 0.0
	boss_actor._rise = 4.0
	await step(180)
	check("rise_never_counts_as_stuck", boss_actor._teleport_count == 0 and boss_actor._teleport_left == 0.0 and boss_actor._progress_positions.is_empty())
	boss_actor._rise = 0.0
	await wait_warning()
	var left := boss_actor._teleport_left
	get_tree().paused = true
	await step(120)
	check("pause_preserves_warning_without_jump", boss_actor._teleport_left == left and boss_actor._teleport_count == 0 and is_instance_valid(boss_actor._teleport_marker))
	get_tree().paused = false
	boss_actor.stun(1.0)
	check("stun_cancels_pending_warning", boss_actor._teleport_left == 0.0 and boss_actor._teleport_marker == null)
	await step(65)
	await wait_warning()
	level.player.dead = true
	await step(5)
	check("player_death_cancels_pending_warning", boss_actor._teleport_count == 0 and boss_actor._teleport_left == 0.0 and boss_actor._teleport_marker == null)
	level.player.dead = false
	await wait_warning()
	level.finished = true
	await step(5)
	check("level_finish_cancels_pending_warning", boss_actor._teleport_count == 0 and boss_actor._teleport_left == 0.0 and boss_actor._teleport_marker == null)
	level.finished = false
	await wait_warning()
	boss_actor.take_hit(boss_actor.hp + 1, Vector3.RIGHT, level.player.global_position, level.player)
	check("boss_death_cancels_pending_warning", boss_actor.dead and boss_actor._teleport_left == 0.0 and boss_actor._teleport_marker == null)
	await teardown()
	await setup()
	boss_actor = spawn(Vector3(-8, 0, 16))
	check("new_actor_resets_recovery_state", boss_actor._teleport_count == 0 and boss_actor._teleport_cd == 0.0 and boss_actor._attack_recovery == 0.0 and boss_actor._progress_positions.is_empty())
	await teardown()

func normal_and_door() -> void:
	await setup()
	cage(Vector3(-8, 0, 16))
	var regular := spawn(Vector3(-8, 0, 16), false)
	await step(180)
	check("ordinary_stall_repaths_without_teleport", regular._forced_repaths > 0 and regular._teleport_count == 0 and regular._teleport_left == 0.0)
	await teardown()
	await setup()
	level.player.position = Vector3(-4, 0, 11.2)
	boss_actor = spawn(Vector3(-4, 0, 5.3))
	var travelled := 0.0
	var before := boss_actor.global_position
	for i in 600:
		await step(1)
		travelled += boss_actor.global_position.distance_to(before)
		before = boss_actor.global_position
		if boss_actor.global_position.z > 8.85 and boss_actor.global_position.distance_to(level.player.global_position) < 2.6:
			break
	check("unblocked_door_route_walks_normally", boss_actor.global_position.z > 8.85 and boss_actor._teleport_count == 0 and boss_actor._teleport_left == 0.0 and travelled > 4.0, {"position": vec(boss_actor.global_position), "travelled": travelled})
	await teardown()

func continuous_moving_player() -> void:
	await setup()
	level.player.position = Vector3(-4, 0, 11.2)
	boss_actor = spawn(Vector3(-4, 0, 5.3))
	var goals: Array[Vector3] = [Vector3(0, 0, 7.2), Vector3(3, 0, 5.5), Vector3(0, 0, 9.8), Vector3(-4, 0, 11.2)]
	var goal_i := 0
	var player_travelled := 0.0
	var boss_travelled := 0.0
	var player_before := level.player.global_position
	var boss_before := boss_actor.global_position
	var unsafe_landings := 0
	var previous_teleports := 0
	var crossed_inside := false
	var crossed_outside := false
	for i in 1200:
		var delta_pos := goals[goal_i] - level.player.global_position
		delta_pos.y = 0.0
		if delta_pos.length() < 0.25:
			goal_i = (goal_i + 1) % goals.size()
			delta_pos = goals[goal_i] - level.player.global_position
		level.player.velocity = delta_pos.normalized() * 2.2
		level.player._move()
		# Apply the same knock damping as Player._physics_process, which is
		# disabled here so the fixture owns its moving-player input.
		level.player.knock = level.player.knock.move_toward(Vector3.ZERO, 30.0 * DT)
		await step(1)
		Game.reset_time()
		player_travelled += level.player.global_position.distance_to(player_before)
		boss_travelled += boss_actor.global_position.distance_to(boss_before)
		player_before = level.player.global_position
		boss_before = boss_actor.global_position
		crossed_inside = crossed_inside or boss_actor.global_position.z < 7.2
		crossed_outside = crossed_outside or boss_actor.global_position.z > 8.85
		if boss_actor._teleport_count != previous_teleports:
			if overlap(boss_actor) or boss_actor.global_position.distance_to(level.player.global_position) < 1.05:
				unsafe_landings += 1
			previous_teleports = boss_actor._teleport_count
	check("continuous_physical_player_door_pursuit", player_travelled > 25.0 and boss_travelled > 15.0 and crossed_inside and crossed_outside and unsafe_landings == 0, {"player_travelled": player_travelled, "boss_travelled": boss_travelled, "teleports": boss_actor._teleport_count, "unsafe_landings": unsafe_landings, "crossed_inside": crossed_inside, "crossed_outside": crossed_outside, "boss_position": vec(boss_actor.global_position)})
	check("normal_progress_does_not_false_teleport", boss_actor._teleport_count == 0 and boss_actor._teleport_left <= 0.0)
	await teardown()

func save_report() -> void:
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"checks": checks, "failed": failed, "traces": traces, "wall_seconds": (Time.get_ticks_msec() - wall_start) / 1000.0, "scope": "Live production Zombie CharacterBody3D physics at 60Hz; real Level boss navmap; stationary, oscillating and moving targets; dynamic blocker fixtures; frozen player/other AI; no performance or real-phone claim"}, "\t"))
	else:
		failed += 1

func run_all() -> void:
	await blocked_recovery()
	await moving_and_blocked_landing()
	await no_safe_spot()
	await oscillation()
	await cooldown()
	await suppressed_states()
	await normal_and_door()
	await continuous_moving_player()
	# Drain detached audio/visual completion timers before inspecting shutdown.
	await step(180)
	save_report()
	print("[teleport-qa] RESULT ", JSON.stringify({"checks": checks.size(), "failed": failed, "report": report_path}))
	get_tree().quit(0 if failed == 0 else 1)
