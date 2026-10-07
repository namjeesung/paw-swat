extends Node
var checks := 0
var failed := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
		print("[packed-victory] FAIL ", label)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	Online.server_url = ""
	Game.autotest = false
	for diff in ["easy", "normal", "hard", "insane"]:
		Game.reset_time()
		Game.set_difficulty(diff, false)
		var level := Level.new()
		add_child(level)
		level.set_process(false)
		level.player.set_physics_process(false)
		level.hostage.set_physics_process(false)
		for e in level.enemies:
			e.set_physics_process(false)
		for i in 3:
			await get_tree().physics_frame
		Game.run.rescued = true
		level.wave_fired = true
		level.wave_t = Level.WAVE_TIME
		check(diff + " requires correct boss count", level.boss_required == int(Game.diff_info(diff).bosses))
		level._tick_wave(0.0)
		check(diff + " all pending kings spawned at deadline", level._boss_spawned == level.boss_required)
		check(diff + " live kings block success", not level.finished and not level.can_finish_wave())
		check(diff + " remaining count includes all kings", level.remaining_bosses() == level.boss_required)
		var kings := level.zombies.duplicate()
		for z in kings:
			z.set_physics_process(false)
			z._rise = 0.0
			z.take_hit(z.max_hp + 1.0, Vector3.ZERO, z.global_position, level.player)
		check(diff + " real deaths accounted", level._boss_defeated == level.boss_required)
		check(diff + " dead kings unlock predicate", level.can_finish_wave())
		var score: int = int(Game.run.score)
		level.on_zombie_killed(kings[0])
		check(diff + " duplicate death does not reward", Game.run.score == score)
		level.player.dead = true
		check(diff + " death blocks victory", not level.can_finish_wave())
		level.player.dead = false
		level.wave_t = Level.WAVE_TIME - 0.01
		check(diff + " early kills do not finish early", not level.can_finish_wave())
		level.queue_free()
		for i in 3:
			await get_tree().physics_frame
	Game.reset_time()
	print("[packed-victory] RESULT ", JSON.stringify({"checks": checks, "failed": failed, "classes_from_final_export": true}))
	get_tree().quit(0 if failed == 0 else 1)
