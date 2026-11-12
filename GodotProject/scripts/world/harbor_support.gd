class_name HarborSupport
extends Node3D
## 第二章 · 连杀支援（COD 式）：击退僵尸鼠攒「支援点」，攒满按数字键呼叫。
##   1 空投补给（20 杀）：飞机往准星处丢一个补给箱：一把神装 + 手雷（受伤时还有回血）
##   2 空袭（45 杀）：地上亮一条黄线 → 战机掠过，沿线连环轰炸
##   3 炮艇（80 杀）：12 秒内天上的炮艇不停点射你周围的僵尸鼠（鼠王 / 机甲优先）
## 三种支援各自计数，用掉哪个哪个清零；打爆 Boss 额外 +10。

const KINDS := [
	{"id": "drop", "name": "空投补给", "need": 20, "color": Color("7CFFB2")},
	{"id": "air", "name": "空袭", "need": 45, "color": Color("FFC93C")},
	{"id": "gunship", "name": "炮艇", "need": 80, "color": Color("FF7A5A")},
]

var level: HarborLevel
var points := [0, 0, 0]
var used := 0
var gunship_t := 0.0
var _gun_cd := 0.0
var _announced := [false, false, false]


func add_kills(n: int) -> void:
	for i in 3:
		points[i] = mini(points[i] + n, int(KINDS[i].need))
		if points[i] >= int(KINDS[i].need) and not _announced[i]:
			_announced[i] = true
			Sfx.play("powerup", -8.0, 1.3, 0.0)
			level.hud.toast("%s 就绪！按 %d 呼叫" % [KINDS[i].name, i + 1])
			if used == 0 and i == 0:
				level.tip("support")


func is_ready_slot(i: int) -> bool:
	return points[i] >= int(KINDS[i].need)


func _unhandled_input(e: InputEvent) -> void:
	if level == null or level.stage != "play" or level.player.dead:
		return
	for i in 3:
		if e.is_action_pressed("support_%d" % (i + 1)):
			call_support(i)
			get_viewport().set_input_as_handled()


func call_support(i: int) -> void:
	if not is_ready_slot(i):
		Sfx.play("ui_click", -10.0, 0.7)
		level.hud.toast("%s 还差 %d 杀" % [KINDS[i].name, int(KINDS[i].need) - points[i]])
		return
	points[i] = 0
	_announced[i] = false
	used += 1
	var aim := _aim_point()
	match KINDS[i].id:
		"drop":
			_care_package(aim)
		"air":
			_airstrike(aim)
		"gunship":
			gunship_t = 12.0
			_gun_cd = 0.6
			level.hhud.big_banner("炮 艇 支 援", Color("FF7A5A"), 100)
			level.hud.radio.say("chief", "炮艇到达上空！[color=#FF7A5A]12 秒火力覆盖[/color]！", 0.0, true)
			Sfx.play("alarm", -10.0, 0.6, 0.0)
	if Game.autotest:
		print("[support] %s at t=%.1f" % [KINDS[i].id, level.t])


func _aim_point() -> Vector3:
	var p := level.player
	var a: Vector3 = p.aim_point
	a.y = 0
	var pp := p.global_position
	pp.y = 0
	if a.distance_to(pp) < 3.0 or a.distance_to(pp) > 18.0:
		a = pp + p.aim_dir * 8.0
	a.x = clampf(a.x, -HarborBuilder.HALF_X + 1.0, HarborBuilder.HALF_X - 1.0)
	a.z = clampf(a.z, HarborBuilder.DOCK_EDGE_Z + 1.0, HarborBuilder.GATE_Z - 1.0)
	return a


# ------------------------------------------------------------------ 空投补给

func _care_package(at: Vector3) -> void:
	level.hud.radio.say("chief", "空投补给马上到——[color=#7CFFB2]绿烟[/color]那里！", 0.0, true)
	Sfx.play("radio", -6.0)
	var smoke := Lob.disk(level, at, 1.4, Color("7CFFB2"))
	smoke.scale = Vector3.ONE
	_plane(at, Color("7CFFB2"))
	var crate := Node3D.new()
	level.add_child(crate)
	var box := MeshInstance3D.new()
	box.mesh = Models.box(Vector3(1.0, 0.8, 1.0))
	box.material_override = Toon.mat(Color("5C8A4A"), true, Pal.OUTLINE_PROP, 0.03)
	box.position.y = 0.4
	crate.add_child(box)
	var band := MeshInstance3D.new()
	band.mesh = Models.box(Vector3(1.04, 0.12, 1.04))
	band.material_override = Toon.prop(Pal.YELLOW)
	band.position.y = 0.4
	crate.add_child(band)
	var chute := MeshInstance3D.new()
	chute.mesh = Models.sphere(1.1)
	chute.material_override = Toon.prop(Color("F2F2F2"))
	chute.scale = Vector3(1, 0.45, 1)
	chute.position.y = 2.6
	crate.add_child(chute)
	crate.global_position = at + Vector3(0, 16, 0)
	var tw := crate.create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(crate, "global_position:y", 0.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		chute.queue_free()
		smoke.queue_free()
		Fx.dust(level, at, 10, Color(1, 0.95, 0.85, 0.8), 2.5, 0.35)
		Sfx.play("stamp", -6.0, 0.8, 0.0)
		if level.stage != "play":
			crate.queue_free()
			return
		# 补给：一把神装（不占整局上限）+ 手雷 + 受伤时回血
		level._weapon_drops = 0
		var w: String = HarborLevel.WEAPON_POOL[randi() % HarborLevel.WEAPON_POOL.size()]
		level.spawn_pickup(at + Vector3(0, 0, 1.4), "weapon", w, 0.8, at)
		level._grenade_drops = 0
		level.spawn_pickup(at + Vector3(-1.3, 0, 0), "grenade", "", 0.8, at)
		if level.player.hp < level.player.max_hp * 0.8:
			level.spawn_pickup(at + Vector3(1.3, 0, 0), "heal", "", 0.8, at)
		var t2 := crate.create_tween()
		t2.tween_interval(1.0)
		t2.tween_property(crate, "scale", Vector3.ONE * 0.01, 0.3)
		t2.tween_callback(crate.queue_free)
	)


# ------------------------------------------------------------------ 空袭

func _airstrike(at: Vector3) -> void:
	var p := level.player
	var dir := at - p.global_position
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3(0, 0, -1)
	var side := Vector3(-dir.z, 0, dir.x)
	level.hud.radio.say("chief", "空袭授权！[color=#FFC93C]离黄线远点[/color]！", 0.0, true)
	level.hhud.big_banner("空 袭", Pal.YELLOW, 110)
	Sfx.play("alarm", -8.0, 1.1, 0.0)
	# 沿准星方向的一条线（与玩家视线同向），以准星为中心 16 米长
	var n := 9
	for k in n:
		var t := (k / float(n - 1) - 0.5) * 16.0
		var pt := at + dir * t + side * randf_range(-0.6, 0.6)
		pt.x = clampf(pt.x, -HarborBuilder.HALF_X + 0.5, HarborBuilder.HALF_X - 0.5)
		pt.z = clampf(pt.z, HarborBuilder.DOCK_EDGE_Z + 0.5, HarborBuilder.GATE_Z - 0.5)
		Lob.shot(level, pt + Vector3(0, 14, 0) - dir * 6.0, pt, 0.9 + k * 0.07, 2.6, 0.0, Pal.YELLOW, 0.45, false, 16.0, 0.0, 2.2)
	_plane(at, Pal.YELLOW, dir)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_callback(func(): Game.shake(0.35))


## 一架飞机从屏幕外掠过（只是看的）
func _plane(at: Vector3, col: Color, dir := Vector3(1, 0, -0.4)) -> void:
	dir = dir.normalized()
	var plane := Node3D.new()
	level.add_child(plane)
	var body := MeshInstance3D.new()
	body.mesh = Models.box(Vector3(0.9, 0.5, 3.4))
	body.material_override = Toon.mat(Color("4A5568"), true, Pal.OUTLINE_PROP, 0.03)
	plane.add_child(body)
	var wing := MeshInstance3D.new()
	wing.mesh = Models.box(Vector3(5.0, 0.12, 1.1))
	wing.material_override = body.material_override
	plane.add_child(wing)
	var tail := MeshInstance3D.new()
	tail.mesh = Models.box(Vector3(0.12, 0.9, 0.7))
	tail.material_override = Toon.prop(col)
	tail.position = Vector3(0, 0.5, -1.4)
	plane.add_child(tail)
	var from := at - dir * 40.0 + Vector3(0, 11, 0)
	var to := at + dir * 40.0 + Vector3(0, 11, 0)
	plane.global_position = from
	plane.look_at(to, Vector3.UP)
	plane.rotate_object_local(Vector3.UP, PI)
	var tw := plane.create_tween()
	tw.tween_property(plane, "global_position", to, 1.8)
	tw.tween_callback(plane.queue_free)
	Sfx.play("dash", -4.0, 0.5, 0.0)


# ------------------------------------------------------------------ 炮艇

func _process(delta: float) -> void:
	if gunship_t <= 0.0 or level == null or level.stage != "play":
		return
	gunship_t -= delta
	_gun_cd -= delta
	if _gun_cd > 0.0:
		return
	_gun_cd = 0.28
	var pp := level.player.global_position
	var best: Zombie = null
	var bd := 1e9
	for z in level.zombies:
		if z.dead:
			continue
		var d := z.global_position.distance_to(pp)
		if d > 16.0:
			continue
		d += randf_range(0.0, 6.0) - (8.0 if z.boss else 0.0)
		if d < bd:
			bd = d
			best = z
	if best == null:
		return
	var at := best.global_position
	var from := at + Vector3(-6.0, 18.0, -6.0)
	# 曳光弹：一道从天而降的光
	var beam := MeshInstance3D.new()
	beam.mesh = Models.box(Vector3(1, 1, 1))
	beam.material_override = Toon.glow(Color(1.0, 0.55, 0.35), 2.6)
	level.add_child(beam)
	beam.global_position = (from + at) * 0.5
	beam.look_at(at, Vector3.UP)
	beam.scale = Vector3(0.14, 0.14, from.distance_to(at))
	var tw := beam.create_tween()
	tw.tween_property(beam, "scale:x", 0.01, 0.12)
	tw.parallel().tween_property(beam, "scale:y", 0.01, 0.12)
	tw.tween_callback(beam.queue_free)
	Fx.ring(level, at, Color(1.0, 0.55, 0.35), 2.2, 0.25)
	Fx.spark(level, at + Vector3(0, 0.3, 0), Vector3.UP, Pal.ORANGE, 8, 6.0)
	Sfx.play("explosion", -12.0, randf_range(1.2, 1.5), 0.1)
	level.explode(at, 2.2, 9.0, level.player, true)
