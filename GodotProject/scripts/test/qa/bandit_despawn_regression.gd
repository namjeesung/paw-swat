extends Node
## Production actors and mission flow; no network, no permanent immunity.
var level: Level
var checks := 0
var failed := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Online.server_url = ""
	call_deferred("run_all")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
	print("[bandit-qa] %s %s" % ["PASS" if ok else "FAIL", label])

func wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func run_all() -> void:
	Game.autotest = false
	Game.set_difficulty("normal", false)
	Game.container = self
	level = Level.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	Game.current = level
	add_child(level)
	level.player.bot_enabled = true
	level.player.bot = {"move": Vector2.ZERO, "shoot": false, "aim": false}
	level.player.set_physics_process(false)
	level.hostage.set_physics_process(false)
	for e in level.enemies:
		e.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	level._set_phase(1)
	var initial_total := level.enemies.size()
	var front_total := level._front_total
	var first: Enemy = level._front_enemies()[0]
	var first_ref: WeakRef = weakref(first)
	level.player.lock_target = first
	first.drop = "shotgun"
	first.set_physics_process(true)
	first._path = PackedVector3Array([Vector3.ONE])
	first._burst = 2
	first._lunge = 1.0
	first.velocity = Vector3.ONE
	first.knock = Vector3.ONE
	var bullet := Bullet.new()
	bullet.setup(level, Vector3(200, 0.72, 200), Vector3.RIGHT, false, 1, first, {"speed": 0.1})
	level.add_child(bullet)
	bullet.set_physics_process(false)
	var downs := int(Game.run.downs)
	var cuffs := int(Game.run.cuffs)
	var zombies := int(Game.run.get("zombies", 0))
	Game.bullet_time(2.0)
	check(first.take_hit(999, Vector3.ZERO, Vector3.ZERO, null), "first lethal hit accepted")
	check(first.state == "defeated" and first.hp == 0, "terminal defeat state immediately")
	check(not first.is_active() and not first.can_interact(level.player), "no attack or cuff interaction")
	check(first.collision_layer == 0 and first.collision_mask == 0, "no collision participation")
	check(first.velocity == Vector3.ZERO and first.knock == Vector3.ZERO, "movement and knockback stop immediately")
	check(not first.is_physics_processing() and not first.is_processing(), "actor callbacks stopped")
	check(first._path.is_empty() and first._burst == 0 and first._lunge == 0, "navigation and attacks cleared")
	check(not level.enemies.has(first) and not level.targets().has(first), "actor registry and targeting cleared")
	check(level.player.lock_target == null, "player target cleared before free")
	check(int(Game.run.downs) == downs + 1 and int(Game.run.cuffs) == cuffs + 1, "one defeat plus permanent subdue recorded")
	check(level._front_defeated == 1 and level._front_total == front_total, "stable mission denominator")
	check(level._weapon_drops == 1 and first.drop == "", "single designated weapon drop consumed")
	var weapons := level._weapon_drops
	var points := int(Game.run.score)
	check(not first.take_hit(999, Vector3.ZERO, Vector3.ZERO, null), "repeat damage rejected")
	first._go_down(Vector3.ZERO)
	first.cuff()
	level.on_enemy_down(first)
	check(int(Game.run.score) == points and level._weapon_drops == weapons, "no duplicate reward or loot")
	check(level._bandits_defeated == 1, "duplicate completion event ignored")
	check(int(Game.run.get("zombies", 0)) == zombies and not bool(Game.run.get("boss", false)), "bandit cannot count as zombie or boss")
	await wait_real(0.6)
	check(Engine.time_scale < 1.0, "despawn check runs during active slow motion")
	check(first_ref.get_ref() == null, "whole enemy freed on real-time dissolve during slow motion")
	bullet._physics_process(0.01)
	check(bullet.shooter == null, "in-flight bullet safely forgets freed shooter")
	bullet.queue_free()
	for e in level._front_enemies().duplicate():
		e.take_hit(999, Vector3.ZERO, Vector3.ZERO, null)
	check(level.phase == 2 and level.door.breachable, "clearing front opens breach objective")
	check(level._front_defeated == front_total, "front progress retained after actor removal")
	level._on_breached()
	check(level.phase == 3, "breach still targets hostage taker")
	var tk: Enemy = level.taker
	var tk_ref: WeakRef = weakref(tk)
	tk.take_hit(999, Vector3.ZERO, Vector3.ZERO, null)
	check(level.phase == 4 and level.hostage.state == "free", "taker defeat releases hostage and advances mission")
	check(level.taker == null and level._taker_defeated, "no dangling taker reference")
	check(level.guide_target() == level.hostage.global_position, "guide follows hostage rather than freed taker")
	for e in level.enemies.duplicate():
		e.take_hit(999, Vector3.ZERO, Vector3.ZERO, null)
	check(level.enemies.is_empty() and level._bandits_defeated == initial_total, "all enemy registrations removed")
	check(level._all_bandits_bonus, "all-subdued bonus retained exactly once")
	Game.reset_time()
	await wait_real(0.65)
	check(tk_ref.get_ref() == null, "taker node also freed")
	var survivors := 0
	for child in level.get_children():
		if child is Enemy:
			survivors += 1
	check(survivors == 0, "zero hidden enemy corpses or countdown nodes")
	level.hostage.rescue()
	check(Game.run.rescued and level.phase == 5, "rescue starts existing horde sequence")
	level.wave_fired = true
	level.wave_t = level.WAVE_TIME
	level._boss_spawned = level.boss_required
	level._boss_defeated = 0
	check(not level.can_finish_wave(), "bandit clears cannot bypass required boss kills")
	level.finished = true
	print("[bandit-qa] RESULT checks=%d failed=%d" % [checks, failed])
	Game.current = null
	Game.container = null
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if failed else 0)
