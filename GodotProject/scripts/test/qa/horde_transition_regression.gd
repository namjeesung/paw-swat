extends Node
## Production transition regression. No network or public score submission.
## --headless verifies state and CPU font caching, NOT GPU frame time.
var failed := 0
var checks := 0
var level: Level
var frames := 0
var previous_us := 0
var worst_us := 0
var timing := false

func _ready() -> void:
	Online.server_url = ""
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.wait_time = 45.0
	watchdog.ignore_time_scale = true
	watchdog.timeout.connect(func(): print("[horde-qa] TIMEOUT"); get_tree().quit(2))
	add_child(watchdog)
	watchdog.start()
	call_deferred("_run")

func _process(_delta: float) -> void:
	frames += 1
	var now := Time.get_ticks_usec()
	if timing and previous_us > 0:
		var elapsed := now - previous_us
		worst_us = maxi(worst_us, elapsed)
		if elapsed > 50000:
			print("[horde-frame] %.2fms wave=%s time=%.2f" % [elapsed / 1000.0, level.wave_on, level.t])
	previous_us = now

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failed += 1
	print("[horde-qa] %s %s" % ["PASS" if ok else "FAIL", description])

func wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _run() -> void:
	var font := Style.title_font()
	var begin_frame := frames
	await Style.prewarm_text(self, [[font, "僵尸鼠来袭！", 110, 22, 1.0]])
	check(frames - begin_frame >= 5, "glyph rasterization spread across frames")
	var ts := TextServerManager.get_primary_interface()
	for character in "僵尸鼠来袭！":
		for rid in font.get_rids():
			if not ts.font_has_char(rid, character.unicode_at(0)):
				continue
			var glyph := ts.font_get_glyph_index(rid, 110, character.unicode_at(0), 0)
			check(ts.font_get_glyph_list(rid, Vector2i(110, 0)).has(glyph), "cached fill " + character)
			check(ts.font_get_glyph_list(rid, Vector2i(110, 22)).has(glyph), "cached outline " + character)
			break
	# Use the actual Font drawing path to check fractional viewport caches,
	# including nominal shaping, fallback fonts, subpixel glyphs and atlases.
	var canvas := RenderingServer.canvas_item_create()
	var specs := [
		[Style.title_font(), "僵尸鼠来袭！", 110, 22, 0.75],
		[Style.title_font(), "实验罐头泄漏 · 保护小米", 30, 8, 0.75],
		[Style.num_font(), "FIRE!", 220, 40, 0.75],
		[Style.title_font(), "神器组装中...", 18, 6, 1.0],
		[Style.title_font(), "神器装备！", 24, 8, 1.0],
		[Style.title_font(), "罐头加特林", 22, 8, 1.0],
		[Style.num_font(), "FIRE!", 52, 12, 1.0],
	]
	for spec in specs:
		await Style.prewarm_text(self, [spec])
		var face: Font = spec[0]
		var before := cache_snapshot(ts, face)
		face.draw_string(canvas, Vector2.ZERO, spec[1], HORIZONTAL_ALIGNMENT_CENTER, 1400, spec[2], Color.WHITE, 3, TextServer.DIRECTION_AUTO, TextServer.ORIENTATION_HORIZONTAL, spec[4])
		face.draw_string_outline(canvas, Vector2.ZERO, spec[1], HORIZONTAL_ALIGNMENT_CENTER, 1400, spec[2], spec[3], Color.WHITE, 3, TextServer.DIRECTION_AUTO, TextServer.ORIENTATION_HORIZONTAL, spec[4])
		RenderingServer.canvas_item_clear(canvas)
		check(before == cache_snapshot(ts, face), "real drawing reuses complete cache: " + spec[1])
	RenderingServer.free_rid(canvas)
	# Cancellation must not resume work on a freed level/HUD during restart.
	var owner := Node.new()
	add_child(owner)
	Style.prewarm_text(owner, [[font, "提前退出", 113, 23]])
	owner.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(owner), "prewarm owner can be freed safely")
	Game.autotest = false
	Game.set_difficulty("normal", false)
	Game.boot(self)
	await wait_real(0.8)
	Game.goto("level")
	await wait_real(2.0)
	level = Game.current
	check(level != null, "production level ready")
	for e in level.enemies:
		e.set_physics_process(false)
	level.player.bot_enabled = true
	level.player.bot = {"move": Vector2.ZERO, "shoot": false, "aim": false}
	check(level._env.fog_enabled, "fog shader path active from level creation")
	check(is_zero_approx(level._env.fog_density), "clear air before horde")
	check(is_zero_approx(level._env.fog_height_density), "no height fog added")
	check(not level.wave_on and not level.wave_fired, "prewarming does not start gameplay")
	timing = true
	var t_before := level.t
	level.on_hostage_rescued()
	await wait_real(3.5)
	check(level.wave_on, "horde starts after original 3.4 second dialogue")
	check(not level.wave_fired, "60 second countdown still waits for artifact")
	check(level._env.fog_enabled, "same fog variant across horde onset")
	check(level._env.fog_density > 0.0, "original fog density tween runs")
	check(level.t > t_before + 3.0, "game clock is not paused to hide preparation")
	await wait_real(2.2)
	check(is_instance_valid(level._artifact), "story-critical gatling drop preserved")
	check(absf(level._env.fog_density - 0.004) < 0.00001, "final fog density unchanged")
	check(level.WAVE_TIME == 60.0, "horde duration unchanged")
	check(level.boss_required == int(Game.diff_info("normal").bosses), "boss requirement unchanged")
	timing = false
	print("[horde-frame] worst_transition_ms=%.2f" % (worst_us / 1000.0))
	level.wave_fired = true
	level.wave_t = level.WAVE_TIME
	level._boss_spawned = level.boss_required
	level._boss_defeated = 0
	check(not level.can_finish_wave(), "deadline does not bypass required boss kills")
	level._boss_defeated = level.boss_required
	check(level.can_finish_wave(), "victory allowed after all required boss kills")
	level.finished = true
	print("[horde-qa] RESULT checks=%d failed=%d renderer=%s" % [checks, failed, RenderingServer.get_current_rendering_method()])
	Game.current = null
	Game.container = null
	Game.reset_time()
	get_tree().paused = false
	level.queue_free()
	level = null
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
	get_tree().quit(1 if failed else 0)

func cache_snapshot(ts: TextServer, font: Font) -> Array:
	var caches := []
	for rid in font.get_rids():
		caches.append(ts.font_get_size_cache_info(rid))
	return caches
