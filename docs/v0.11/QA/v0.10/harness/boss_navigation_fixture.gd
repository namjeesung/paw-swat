extends Node
## Real production Level geometry/nav and live Zombie physics. Boss positions are never repaired/teleported.
var holder: Node
var level: Level
var p: Player
var results: Array[Dictionary] = []
var lifecycle: Array[Dictionary] = []
var spawn_checks: Array[Dictionary] = []
var mode := "quick"
var output_path := "user://boss-navigation-report.json"
var wall_start := 0
var shots_dir := ""
var shot_n := 0
var DT := 1.0 / 60.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.physics_ticks_per_second = 60
	DT = 1.0 / Engine.physics_ticks_per_second
	Online.server_url = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--boss-qa="):
			mode = arg.substr(10)
		if arg.begins_with("--report="):
			output_path = arg.substr(9)
		if arg.begins_with("--shots="):
			shots_dir = arg.substr(8)
	wall_start = Time.get_ticks_msec()
	holder = Node.new()
	holder.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(holder)
	call_deferred("_run")

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - wall_start > 120000:
		print("[boss-qa] WALL TIMEOUT")
		save_report(false)
		get_tree().quit(2)

func vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

func map_for_boss() -> RID:
	return level.call("zombie_navigation_map", true) if level.has_method("zombie_navigation_map") else level.get_world_3d().navigation_map

func setup_level(diff: String) -> void:
	Game.reset_time()
	Game.touch = false
	Game.autotest = false
	Game.set_difficulty(diff, false)
	Game.container = holder
	var started := Time.get_ticks_usec()
	level = Level.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	Game.current = level
	holder.add_child(level)
	p = level.player
	level.set_process(false)
	p.set_physics_process(false)
	p.bot_enabled = true
	p.bot = {"move": Vector2.ZERO, "shoot": false}
	p.max_hp = Game.dv("player_hp") if mode == "native" else 100000.0
	p.hp = p.max_hp
	level.hostage.set_physics_process(false)
	for e in level.enemies:
		e.set_physics_process(false)
	var meshes: Array[Dictionary] = []
	for region in level.find_children("*", "NavigationRegion3D", true, false):
		var nm: NavigationMesh = region.navigation_mesh
		if nm:
			meshes.append({"radius": nm.agent_radius, "height": nm.agent_height, "cell_size": nm.cell_size, "polygons": nm.get_polygon_count(), "map_id": region.get_navigation_map().get_id()})
	lifecycle.append({"stage": "level_ready", "difficulty": diff, "load_ms": (Time.get_ticks_usec() - started) / 1000.0, "maps": NavigationServer3D.get_maps().size(), "nav_meshes": meshes})
	for i in 12:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map_for_boss()) > 0:
			break

func cleanup_level() -> void:
	var old_map := map_for_boss()
	var is_dedicated := old_map != level.get_world_3d().navigation_map
	Game.current = null
	level.queue_free()
	level = null
	p = null
	for i in 4:
		await get_tree().physics_frame
	var gone := not NavigationServer3D.get_maps().has(old_map)
	lifecycle.append({"stage": "level_exit", "had_dedicated_boss_map": is_dedicated, "boss_map_removed": gone if is_dedicated else true, "maps_remaining": NavigationServer3D.get_maps().size()})

func clear_bosses() -> void:
	for z in level.zombies:
		z.queue_free()
	level.zombies.clear()
	for i in 3:
		await get_tree().physics_frame

func sample(z: Zombie) -> Dictionary:
	var collisions: Array[Dictionary] = []
	for i in z.get_slide_collision_count():
		var c := z.get_slide_collision(i)
		var col := c.get_collider()
		var d := {"position": vec(c.get_position()), "normal": vec(c.get_normal()), "collider": str(col.get_path()) if col is Node else str(col)}
		if col is Node3D:
			d["collider_center"] = vec(col.global_position)
			for child in col.get_children():
				if child is CollisionShape3D and child.shape is BoxShape3D:
					d["box_size"] = vec(child.shape.size)
		collisions.append(d)
	var path: Array = []
	for v in z._path:
		path.append(vec(v))
	return {"position": vec(z.global_position), "distance": z.global_position.distance_to(p.global_position), "velocity": vec(z.velocity), "wind": z._wind, "path_index": z._path_i, "path": path, "collisions": collisions, "line_of_sight": level.line_of_sight(z.center(), p.center())}

func scenario(id: String, starts: Array, target: Vector3, max_seconds := 18.0, kept_bosses: Array = [], crossing: Dictionary = {}) -> Array:
	var bosses: Array = kept_bosses
	if bosses.is_empty():
		await clear_bosses()
		for start: Vector3 in starts:
			var z := Zombie.new()
			z.level = level
			z.boss = true
			z.position = start
			level.add_child(z)
			level.zombies.append(z)
			z._rise = 0.0
			z._attack_cd = 0.0
			bosses.append(z)
	p.global_position = target
	p.hp = p.max_hp
	p.dead = false
	p.since_damage = 99.0
	Game.run.damage = 0.0
	var initial: Array = []
	for z: Zombie in bosses:
		initial.append(vec(z.global_position))
	var trace: Array[Dictionary] = []
	var entrance_shot := false
	if mode == "native":
		level.hud.radio.clear()
		level.hud.set_objective("鼠王通行 · 实际物理测试", "店内→店外" if target.z > 8 else "店外→店内")
		level.cam.snap()
		# The storefront leaves are cosmetic. Hold initial actors only while their original rise tween completes.
		if DisplayServer.get_name() != "headless":
			for z in bosses:
				z.set_physics_process(false)
			await get_tree().create_timer(0.55, true, false, true).timeout
			level._process(0.55)
			await screenshot(id + "_initial")
			for z in bosses:
				z.set_physics_process(true)
	var elapsed := 0.0
	var reached := false
	var wall_winds := 0
	var collision_samples := 0
	var last_wind: Array = []
	for z: Zombie in bosses:
		last_wind.append(z._wind)
	while elapsed < max_seconds:
		await get_tree().physics_frame
		elapsed += DT
		p._tick_timers(DT)
		reached = true
		for i in bosses.size():
			var z: Zombie = bosses[i]
			var los := level.line_of_sight(z.center(), p.center())
			if z._wind > 0.0 and float(last_wind[i]) <= 0.0 and not los:
				wall_winds += 1
			last_wind[i] = z._wind
			var axis: String = crossing.get("axis", "z")
			var plane: float = crossing.get("plane", 8.0)
			var bv := z.global_position.x if axis == "x" else z.global_position.z
			var tv := target.x if axis == "x" else target.z
			var crossed := bv >= plane + 0.86 if tv > plane else bv <= plane - 0.86
			if not crossed or z.global_position.distance_to(target) > 2.55:
				reached = false
		if int(elapsed * 2.0) != int((elapsed - DT) * 2.0):
			var states: Array = []
			for z: Zombie in bosses:
				var s := sample(z)
				if not s.collisions.is_empty():
					collision_samples += 1
				states.append(s)
			trace.append({"t": snappedf(elapsed, 0.01), "bosses": states})
		if mode == "native" and not entrance_shot and absf(bosses[0].global_position.z - 8.0) < 0.6:
			entrance_shot = true
			await screenshot(id + "_near_entrance")
		if reached:
			if mode == "native":
				await screenshot(id + "_reached")
			break
	var final_states: Array = []
	for z: Zombie in bosses:
		final_states.append(sample(z))
	var r := {"id": id, "difficulty": Game.difficulty, "initial_positions": initial, "target": vec(target), "boss_count": bosses.size(), "crossing_plane": crossing, "speed": bosses[0].speed, "capsule_radius": 0.7, "reached": reached, "elapsed_sim_seconds": snappedf(elapsed, 0.01), "wall_blocked_windups": wall_winds, "collision_samples": collision_samples, "damage_to_finite_target": Game.run.damage, "final": final_states, "trace": trace}
	results.append(r)
	print("[boss-qa] ", "PASS " if reached and wall_winds == 0 else "FAIL ", id, " ", JSON.stringify({"difficulty": Game.difficulty, "reached": reached, "elapsed": r.elapsed_sim_seconds, "wall_winds": wall_winds, "final": final_states, "damage": Game.run.damage}))
	save_report(false)
	return bosses

func _run() -> void:
	seed(20261006)
	var diffs := ["normal"] if mode in ["quick", "tight", "native"] else ["easy", "normal", "hard", "insane"]
	for diff: String in diffs:
		await setup_level(diff)
		if mode == "native":
			await scenario("native_inside_outside", [Vector3(-4,0,6.3)], Vector3(0,0,11))
			await scenario("native_outside_inside", [Vector3(4,0,11)], Vector3(0,0,5.3))
		elif mode == "tight":
			await tight_cases()
		else:
			if mode != "quick":
				await scenario(diff + "_center_inside_out", [Vector3(0,0,5.3)], Vector3(0,0,12))
				await scenario(diff + "_center_outside_in", [Vector3(0,0,12)], Vector3(0,0,5.3))
			await scenario(diff + "_left_inside_out", [Vector3(-4,0,6.3)], Vector3(-4,0,11.2))
			await scenario(diff + "_left_outside_in", [Vector3(-4,0,10.8)], Vector3(-4,0,5.3))
			if mode != "quick":
				await scenario(diff + "_right_inside_out", [Vector3(3.8,0,6.3)], Vector3(4,0,11.2))
				await scenario(diff + "_right_outside_in", [Vector3(4,0,10.8)], Vector3(4,0,5.3))
			if diff == "normal":
				await scenario("near_wall_inside_out", [Vector3(-4,0,7.2)], Vector3(-4,0,9))
				await scenario("near_wall_outside_in", [Vector3(4,0,8.9)], Vector3(4,0,7))
			if mode != "quick" and diff == "insane":
				var bs := await scenario("three_boss_inside_out", [Vector3(-0.9,0,5.8),Vector3(0.9,0,5.8),Vector3(0,0,4.2)], Vector3(0,0,12), 24.0)
				bs = await scenario("three_boss_switch_inside", [], Vector3(-3.8,0,5.3), 24.0, bs)
				bs = await scenario("three_boss_switch_outside_right", [], Vector3(4,0,11.2), 24.0, bs)
				bs = await scenario("three_boss_switch_inside_right", [], Vector3(4,0,5.3), 24.0, bs)
		await cleanup_level()
	var failed := results.filter(func(r: Dictionary): return not r.reached or r.wall_blocked_windups > 0)
	var lifecycle_failed := lifecycle.filter(func(r: Dictionary): return r.stage == "level_exit" and not r.boss_map_removed)
	save_report(true)
	print("[boss-qa] RESULT ", JSON.stringify({"cases": results.size(), "failed": failed.size(), "lifecycle_failed": lifecycle_failed.size(), "report": output_path, "wall_seconds": (Time.get_ticks_msec()-wall_start)/1000.0}))
	Game.container = null
	Sfx.music("")
	Sfx._music.stream = null
	for a in Sfx._players:
		a.stop()
		a.stream = null
	Sfx._cache.clear()
	Fx._res.clear()
	Actor._blob_mat = null
	Fx._tex.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failed.is_empty() and lifecycle_failed.is_empty() else 1)

func save_report(complete: bool) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(output_path), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"engine": Engine.get_version_info(), "mode": mode, "complete": complete, "results": results, "lifecycle": lifecycle, "spawn_checks": spawn_checks, "boss_teleport_recovery_used": false, "physics_enabled": true, "physics_hz": Engine.physics_ticks_per_second, "boss_initial_attack_cd": 0, "fixture_target": "Static actual Player, finite100000HP; initial and side-switch placement only; no --god or gameplay acceptance", "wall_seconds": (Time.get_ticks_msec()-wall_start)/1000.0}, "\t"))
		file.close()

func tight_cases() -> void:
	level.door.breachable = true
	level.door.breach(level.door.global_position + Vector3(0,0,1.4))
	Game.reset_time()
	for i in 4:
		await get_tree().physics_frame
	lifecycle.append({"stage": "real_staff_door_breach", "done": level.door.done, "body_removed_from_tree": not is_instance_valid(level.door.body) or not level.door.body.is_inside_tree()})
	await scenario("staff_enter_left_skew", [Vector3(8.0,0,3.4)], Vector3(9.6,0,-3), 18.0, [], {"axis":"z", "plane":0.0})
	await scenario("staff_exit_right_skew", [Vector3(9.6,0,-3)], Vector3(8.0,0,3.4), 18.0, [], {"axis":"z", "plane":0.0})
	await scenario("staff_enter_right_skew", [Vector3(9.4,0,2)], Vector3(8.0,0,-3), 18.0, [], {"axis":"z", "plane":0.0})
	await scenario("staff_exit_left_skew", [Vector3(8.0,0,-3)], Vector3(9.4,0,2), 18.0, [], {"axis":"z", "plane":0.0})
	await scenario("storage_enter", [Vector3(3.7,0,5.7)], Vector3(8.4,0,5.6), 18.0, [], {"axis":"x", "plane":5.0})
	await scenario("storage_exit", [Vector3(8.4,0,5.6)], Vector3(3.7,0,5.7), 18.0, [], {"axis":"x", "plane":5.0})
	await clear_bosses()
	p.global_position = Vector3(8,0,10)
	for n in 16:
		seed(1000 + n)
		var z: Zombie = level._spawn_zombie(true)
		var rec := {"seed": 1000+n, "spawned": z != null, "overlaps": [], "clear": true}
		if z:
			z.set_physics_process(false)
			var query := PhysicsShapeQueryParameters3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.7
			capsule.height = 2.2
			query.shape = capsule
			query.transform = Transform3D(Basis(), z.global_position + Vector3(0,1.16,0))
			query.collision_mask = Bullet.LAYER_WORLD | Bullet.LAYER_LOWCOVER
			query.collide_with_areas = false
			var hits := level.get_world_3d().direct_space_state.intersect_shape(query, 32)
			rec["position"] = vec(z.global_position)
			rec["clear"] = hits.is_empty()
			for h in hits:
				var col: Node3D = h.collider
				rec.overlaps.append({"collider": str(col.get_path()), "position": vec(col.global_position)})
			level.zombies.erase(z)
			z.queue_free()
		spawn_checks.append(rec)
	print("[boss-qa] SPAWN ", JSON.stringify({"checks": spawn_checks.size(), "overlap_failures": spawn_checks.filter(func(r: Dictionary): return not r.clear).size()}))

func screenshot(label: String) -> void:
	if DisplayServer.get_name() == "headless" or shots_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(shots_dir)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	shot_n += 1
	var path := shots_dir.path_join("%02d_%s.png" % [shot_n, label])
	var err := img.save_png(path)
	print("[boss-qa] NATIVE IMAGE ", JSON.stringify({"label": label, "path": path, "width": img.get_width(), "height": img.get_height(), "error": err}))
