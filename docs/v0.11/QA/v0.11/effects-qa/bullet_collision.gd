extends Node
## The real Bullet implementation runs in an isolated physics world with
## recording targets. There is no game/network/ranking submission.
class RecordingHud extends Hud:
	var markers := 0
	func hitmarker(_kill: bool) -> void:
		markers += 1
class RecordingLevel extends Level:
	var blasts: Array = []
	func _ready() -> void:
		set_process(false)
		hud = RecordingHud.new()
	func explode(pos: Vector3, radius: float, damage: float, source: Node) -> void:
		blasts.append([pos,radius,damage,source])
class RecordingTarget extends StaticBody3D:
	var damage_received := 0.0
	var hits := 0
	var accepts := true
	func take_hit(damage: float, _knock: Vector3, _origin: Vector3, _source: Node) -> bool:
		if not accepts:
			return false
		damage_received += damage
		hits += 1
		return true
	func is_active() -> bool:
		return true
var failures: Array[String] = []
var checks: Array = []
var out_path := ""
func _ready() -> void:
	Online.server_url = ""
	Game.new_run()
	Game.reset_time()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--effects-out="):
			out_path = arg.substr(14)
	call_deferred("_run")
func check(ok: bool, text: String) -> void:
	checks.append({"check":text,"pass":ok})
	if not ok:
		failures.append(text)
	print("[bullet-qa] ","PASS " if ok else "FAIL ",text)
func target(level: Level, z: float, layer: int, accepts := true) -> RecordingTarget:
	var t := RecordingTarget.new()
	t.collision_layer = layer
	t.collision_mask = 0
	t.accepts = accepts
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5,0.5,0.5)
	shape.shape = box
	t.add_child(shape)
	level.add_child(t)
	t.position = Vector3(0,0.72,z)
	return t
func cover(level: Level, z: float, layer := 32) -> StaticBody3D:
	var t := StaticBody3D.new()
	t.collision_layer = layer
	t.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5,0.5,0.5)
	shape.shape = box
	t.add_child(shape)
	level.add_child(t)
	t.position = Vector3(0,0.72,z)
	return t
func shoot(level: Level, opts := {}, player := true, source: Node = null) -> Bullet:
	var b := Bullet.new()
	b.setup(level,Vector3(0,0.72,0),Vector3.FORWARD,player,1.25,source,opts)
	level.add_child(b)
	b.set_physics_process(false)
	b._physics_process(0.4 if not player else 0.1)
	return b
func clear_level(level: RecordingLevel) -> void:
	level.hud.free()
	level.queue_free()
	await get_tree().process_frame
func _run() -> void:
	var lv := RecordingLevel.new()
	add_child(lv)
	var shooter := target(lv,-0.4,4)
	var victim := target(lv,-2,4)
	await get_tree().physics_frame
	shoot(lv,{},true,shooter)
	check(shooter.hits == 0 and victim.hits == 1 and is_equal_approx(victim.damage_received,1.25),"shooter excluded; player damage exactly 1.25")
	await clear_level(lv)
	lv = RecordingLevel.new(); add_child(lv)
	cover(lv,-1.0)
	victim = target(lv,-3.0,4)
	await get_tree().physics_frame
	shoot(lv)
	check(victim.hits == 1,"low cover within 1.8m is passed")
	await clear_level(lv)
	lv = RecordingLevel.new(); add_child(lv)
	cover(lv,-2.3)
	victim = target(lv,-4.0,4)
	await get_tree().physics_frame
	shoot(lv)
	check(victim.hits == 0,"distant low cover blocks the shot")
	await clear_level(lv)
	lv = RecordingLevel.new(); add_child(lv)
	cover(lv,-1.0,1)
	victim = target(lv,-3.0,4)
	await get_tree().physics_frame
	shoot(lv)
	check(victim.hits == 0,"world walls block shots")
	await clear_level(lv)
	lv = RecordingLevel.new(); add_child(lv)
	var one := target(lv,-1.0,4)
	var two := target(lv,-2.0,4)
	var three := target(lv,-3.0,4)
	var four := target(lv,-4.0,4)
	await get_tree().physics_frame
	shoot(lv,{"pierce":2})
	check(one.hits==1 and two.hits==1 and three.hits==1 and four.hits==0,"pierce=2 damages exactly three unique targets")
	await clear_level(lv)
	for safe in [true,false]:
		lv = RecordingLevel.new(); add_child(lv)
		var hostage := target(lv,-1.0,8)
		victim = target(lv,-2.0,4)
		await get_tree().physics_frame
		shoot(lv,{"safe":safe})
		check(hostage.hits == (0 if safe else 1) and victim.hits == (1 if safe else 0),"hostage collision safe="+str(safe))
		await clear_level(lv)
	lv = RecordingLevel.new(); add_child(lv)
	var immune := target(lv,-1.0,4,false)
	victim = target(lv,-2.0,4)
	await get_tree().physics_frame
	shoot(lv)
	check(immune.hits==0 and victim.hits==1,"invulnerable target is excluded and ray continues")
	await clear_level(lv)
	lv = RecordingLevel.new(); add_child(lv)
	var ally := target(lv,-1.0,4)
	var player := target(lv,-2.0,2)
	await get_tree().physics_frame
	shoot(lv,{},false)
	check(ally.hits==0 and player.hits==1,"enemy mask ignores enemies and hits player")
	await clear_level(lv)
	lv = RecordingLevel.new(); add_child(lv)
	var b := shoot(lv,{"kind":"rocket","explode":3.4,"max_dist":2.0})
	check(lv.blasts.size()==1 and lv.blasts[0][1]==3.4 and lv.blasts[0][2]==1.25,"rocket max range calls unchanged explosion radius and damage")
	await clear_level(lv)
	var report := {"kind":"headless deterministic collision regression", "checks":checks,"failures":failures,"result":"PASS" if failures.is_empty() else "FAIL"}
	var f := FileAccess.open(out_path,FileAccess.WRITE)
	if f == null:
		get_tree().quit(2); return
	f.store_string(JSON.stringify(report,"\t")); f.close()
	print("[bullet-qa] RESULT ",report.result)
	get_tree().quit(0 if failures.is_empty() else 1)
